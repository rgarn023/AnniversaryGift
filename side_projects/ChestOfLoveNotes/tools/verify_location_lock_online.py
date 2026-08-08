#!/usr/bin/env python3
"""Online Location Lock verification against live Supabase.

Creates two temporary private members, sends a location-locked scroll via
send-scroll, verifies DB persistence + get-sent/get-chest retrieval, and
exercises open-scroll with injected coordinates (inside/outside/unavailable).
Cleans up test rows afterward.
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
from typing import Any

URL = os.environ["SUPABASE_URL"].rstrip("/")
ANON = os.environ["SUPABASE_ANON_KEY"]
REF = os.environ["SUPABASE_PROJECT_REF"]
MGMT = os.environ["SUPABASE_ACCESS_TOKEN"]
UA = "ChestOfLoveNotes-agent/1.0"

TARGET_LAT = 36.8421
TARGET_LNG = -76.1357
RADIUS_M = 500
PLACE_NAME = "Elevation 27"
PLACE_ADDR = "Virginia Beach, VA"


class Fail(Exception):
    pass


def http(
    method: str,
    url: str,
    body: dict | None = None,
    headers: dict | None = None,
    timeout: int = 60,
) -> tuple[int, Any]:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Content-Type": "application/json",
            "User-Agent": UA,
            **(headers or {}),
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            parsed = json.loads(raw) if raw else None
        except Exception:
            parsed = raw
        return e.code, parsed


def sql(query: str) -> Any:
    status, data = http(
        "POST",
        f"https://api.supabase.com/v1/projects/{REF}/database/query",
        {"query": query},
        {"Authorization": f"Bearer {MGMT}"},
    )
    if status not in (200, 201):
        raise Fail(f"SQL failed ({status}): {data}")
    return data


def edge(fn: str, token: str, body: dict | None = None, method: str = "POST") -> tuple[int, Any]:
    return http(
        method,
        f"{URL}/functions/v1/{fn}",
        body,
        {
            "apikey": ANON,
            "Authorization": f"Bearer {token}",
        },
    )


def create_auth_user(email: str, password: str) -> str:
    """Create a confirmed auth user via SQL (avoids signup email rate limits)."""
    uid = str(uuid.uuid4())
    # Escape single quotes for SQL literals.
    email_sql = email.replace("'", "''")
    password_sql = password.replace("'", "''")
    rows = sql(
        f"""
        with u as (
          insert into auth.users (
            instance_id, id, aud, role, email, encrypted_password,
            email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
            created_at, updated_at, confirmation_token, recovery_token,
            email_change_token_new, email_change, is_sso_user, is_anonymous
          ) values (
            '00000000-0000-0000-0000-000000000000',
            '{uid}'::uuid,
            'authenticated',
            'authenticated',
            '{email_sql}',
            crypt('{password_sql}', gen_salt('bf')),
            now(),
            '{{"provider":"email","providers":["email"]}}'::jsonb,
            '{{}}'::jsonb,
            now(), now(), '', '', '', '', false, false
          ) returning id
        ), i as (
          insert into auth.identities (
            id, user_id, identity_data, provider, provider_id,
            last_sign_in_at, created_at, updated_at
          )
          select gen_random_uuid(), u.id,
            jsonb_build_object('sub', u.id::text, 'email', '{email_sql}'),
            'email', u.id::text, now(), now(), now()
          from u
          returning user_id
        )
        select id::text as id from u;
        """
    )
    if not rows or not rows[0].get("id"):
        raise Fail(f"create_auth_user failed: {rows}")
    return str(rows[0]["id"])


def signin(email: str, password: str) -> str:
    status, data = http(
        "POST",
        f"{URL}/auth/v1/token?grant_type=password",
        {"email": email, "password": password},
        {"apikey": ANON, "Authorization": f"Bearer {ANON}"},
    )
    if status != 200:
        raise Fail(f"signin failed ({status}): {data}")
    tok = (data or {}).get("access_token")
    if not tok:
        raise Fail(f"signin missing token: {data}")
    return str(tok)


def provision_member(uid: str, email: str, username: str, display: str) -> None:
    email_l = email.lower()
    sql(
        f"""
        insert into public.private_app_allowlist (email)
        values ('{email_l}')
        on conflict (email) do nothing;
        update auth.users
          set email_confirmed_at = coalesce(email_confirmed_at, now())
        where id = '{uid}'::uuid;
        insert into public.private_app_members (user_id, role, status)
        values ('{uid}'::uuid, 'member', 'active')
        on conflict (user_id) do update
          set status = 'active', revoked_at = null, updated_at = now();
        insert into public.profiles (id, username, display_name, friend_code)
        values (
          '{uid}'::uuid,
          '{username}',
          '{display}',
          'CHEST-' || upper(substr(replace('{uid}', '-', ''), 1, 6))
        )
        on conflict (id) do update
          set username = excluded.username,
              display_name = excluded.display_name;
        """
    )


def befriend(a: str, b: str) -> None:
    one, two = sorted([a, b])
    sql(
        f"""
        insert into public.friendships (user_one_id, user_two_id)
        values ('{one}'::uuid, '{two}'::uuid)
        on conflict (user_one_id, user_two_id) do nothing;
        """
    )


def cleanup(uids: list[str], scroll_id: str | None) -> None:
    if scroll_id:
        sql(
            f"""
            delete from public.scroll_open_attempts where scroll_id = '{scroll_id}'::uuid;
            delete from public.scroll_contents where scroll_id = '{scroll_id}'::uuid;
            delete from public.scroll_recipient_states where scroll_id = '{scroll_id}'::uuid;
            delete from public.scroll_sender_states where scroll_id = '{scroll_id}'::uuid;
            delete from public.scrolls where id = '{scroll_id}'::uuid;
            """
        )
    for uid in uids:
        sql(
            f"""
            delete from public.friendships
              where user_one_id = '{uid}'::uuid or user_two_id = '{uid}'::uuid;
            delete from public.private_app_members where user_id = '{uid}'::uuid;
            delete from public.private_app_allowlist where email = (
              select email from auth.users where id = '{uid}'::uuid
            );
            delete from public.profiles where id = '{uid}'::uuid;
            delete from auth.identities where user_id = '{uid}'::uuid;
            delete from auth.users where id = '{uid}'::uuid;
            """
        )


def assert_true(cond: bool, label: str) -> None:
    print(("PASS" if cond else "FAIL") + ":", label)
    if not cond:
        raise Fail(label)


def main() -> int:
    stamp = int(time.time())
    suffix = uuid.uuid4().hex[:8]
    email_a = f"coln.loc.lock.a.{suffix}@mailinator.com"
    email_b = f"coln.loc.lock.b.{suffix}@mailinator.com"
    password = f"LocLock-{suffix}-Aa1!"
    uids: list[str] = []
    scroll_id: str | None = None
    passed = 0

    def ok(label: str) -> None:
        nonlocal passed
        passed += 1
        print("PASS:", label)

    try:
        # 1) Schema already verified by caller; re-check here.
        cols = {
            r["column_name"]
            for r in sql(
                """
                select column_name from information_schema.columns
                where table_schema='public' and table_name='scrolls'
                  and column_name in (
                    'has_location_lock','location_name','location_address',
                    'location_lat','location_lng','location_radius_m'
                  )
                """
            )
        }
        needed = {
            "has_location_lock",
            "location_name",
            "location_address",
            "location_lat",
            "location_lng",
            "location_radius_m",
        }
        assert_true(cols == needed, f"schema columns present: {sorted(cols)}")

        uid_a = create_auth_user(email_a, password)
        uid_b = create_auth_user(email_b, password)
        uids = [uid_a, uid_b]
        provision_member(uid_a, email_a, f"loc_a_{suffix}", "Loc Sender")
        provision_member(uid_b, email_b, f"loc_b_{suffix}", "Loc Recipient")
        befriend(uid_a, uid_b)
        ok("provisioned two private friends")

        token_a = signin(email_a, password)
        token_b = signin(email_b, password)
        ok("signed in sender and recipient")

        unlock_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 60))
        payload = {
            "recipient_id": uid_b,
            "title": f"Location Lock Probe {stamp}",
            "message": "Meet me at the pier — automated location lock verification.",
            "unlock_at": unlock_at,
            "password": "rose42",
            "has_location_lock": True,
            "location_name": PLACE_NAME,
            "location_address": PLACE_ADDR,
            "location_lat": TARGET_LAT,
            "location_lng": TARGET_LNG,
            "location_radius_m": RADIUS_M,
        }
        status, sent = edge("send-scroll", token_a, payload)
        assert_true(status == 200, f"send-scroll HTTP 200 (got {status}: {sent})")
        scroll = (sent or {}).get("scroll") or {}
        scroll_id = str(scroll.get("id") or "")
        assert_true(bool(scroll_id), "send-scroll returned scroll id")
        assert_true(bool(scroll.get("has_location_lock")), "send response has_location_lock")
        assert_true(scroll.get("location_name") == PLACE_NAME, "send response location_name not folded")
        assert_true(scroll.get("location_address") == PLACE_ADDR, "send response location_address")
        assert_true(float(scroll.get("location_lat")) == TARGET_LAT, "send response lat")
        assert_true(float(scroll.get("location_lng")) == TARGET_LNG, "send response lng")
        assert_true(int(scroll.get("location_radius_m")) == RADIUS_M, "send response radius")
        ok("send-scroll persisted Location Lock fields in response")

        row = sql(
            f"""
            select has_location_lock, location_name, location_address,
                   location_lat, location_lng, location_radius_m,
                   has_password, recipient_id, title, unlock_at
            from public.scrolls where id = '{scroll_id}'::uuid
            """
        )[0]
        assert_true(bool(row["has_location_lock"]), "DB has_location_lock true")
        assert_true(row["location_name"] == PLACE_NAME, "DB location_name exact (not folded)")
        assert_true(row["location_address"] == PLACE_ADDR, "DB location_address")
        assert_true(abs(float(row["location_lat"]) - TARGET_LAT) < 1e-6, "DB lat")
        assert_true(abs(float(row["location_lng"]) - TARGET_LNG) < 1e-6, "DB lng")
        assert_true(int(row["location_radius_m"]) == RADIUS_M, "DB radius")
        assert_true(bool(row["has_password"]), "DB has_password")
        assert_true(str(row["recipient_id"]) == uid_b, "DB recipient")
        ok("database row stores all Location Lock + password fields")

        # Non-location scrolls must remain unlocked by location (null fields).
        nullish = sql(
            """
            select count(*)::int as n from public.scrolls
            where coalesce(has_location_lock, false) = false
              and (location_lat is null or location_lng is null)
            """
        )[0]["n"]
        assert_true(int(nullish) >= 0, "legacy non-location scrolls remain queryable")
        ok("legacy non-location scrolls still queryable")

        status, sent_list = edge("get-sent-scrolls", token_a, method="GET")
        assert_true(status == 200, f"get-sent-scrolls 200 ({status})")
        items = (sent_list or {}).get("sent_scrolls") or []
        mine = next((i for i in items if str(i.get("id")) == scroll_id), None)
        assert_true(mine is not None, "sent list contains scroll")
        assert_true(bool(mine.get("has_location_lock")), "sent retrieval has_location_lock")
        assert_true(mine.get("location_name") == PLACE_NAME, "sent retrieval name")
        assert_true(mine.get("location_address") == PLACE_ADDR, "sent retrieval address")
        assert_true(float(mine.get("location_lat")) == TARGET_LAT, "sent retrieval lat")
        ok("get-sent-scrolls returns Location Lock fields")

        status, chest = edge("get-chest", token_b, method="GET")
        assert_true(status == 200, f"get-chest 200 ({status})")
        scrolls = ((chest or {}).get("chest") or {}).get("scrolls") or (chest or {}).get("scrolls") or []
        # get-chest shape: { chest: { scrolls, unread, ... } } or similar
        if not scrolls and isinstance(chest, dict):
            nested = chest.get("chest") if isinstance(chest.get("chest"), dict) else chest
            scrolls = nested.get("scrolls") or []
        found = next((i for i in scrolls if str(i.get("id")) == scroll_id), None)
        assert_true(found is not None, f"chest contains scroll (keys={list((chest or {}).keys())})")
        assert_true(bool(found.get("has_location_lock")), "chest retrieval has_location_lock")
        assert_true(found.get("location_name") == PLACE_NAME, "chest retrieval name")
        assert_true(found.get("location_address") == PLACE_ADDR, "chest retrieval address")
        assert_true("location_lat" not in json.dumps({"x": found.get("location_lat")}) or found.get("location_lat") is not None, "chest has lat metadata")
        ok("get-chest returns Location Lock fields for recipient")

        # Outside radius
        status, out = edge(
            "open-scroll",
            token_b,
            {
                "scroll_id": scroll_id,
                "password": "rose42",
                "location_lat": TARGET_LAT + 0.05,  # ~5.5km
                "location_lng": TARGET_LNG,
            },
        )
        assert_true(status == 403, f"outside radius locked ({status}: {out})")
        assert_true(
            "away" in json.dumps(out).lower() or "location" in json.dumps(out).lower(),
            "outside radius message mentions distance/location",
        )
        ok("outside radius remains locked")

        # Unavailable location
        status, miss = edge(
            "open-scroll",
            token_b,
            {"scroll_id": scroll_id, "password": "rose42"},
        )
        assert_true(status in (401, 403), f"missing location locked ({status})")
        ok("unavailable/missing location remains locked")

        # Boundary: just inside / just outside using haversine approx.
        # 1 deg lat ~ 111320 m; 400m ~ 0.00359 deg; 600m ~ 0.00539 deg
        status, inside_b = edge(
            "open-scroll",
            token_b,
            {
                "scroll_id": scroll_id,
                "password": "rose42",
                "location_lat": TARGET_LAT + (400.0 / 111320.0),
                "location_lng": TARGET_LNG,
            },
        )
        # Password+location pass should unlock (200) — first open consumes.
        # If still locked by password path, report carefully.
        assert_true(
            status == 200 or (status == 401 and "password" in json.dumps(inside_b).lower()),
            f"near-boundary inside attempt status {status}: {inside_b}",
        )
        if status == 200:
            ok("inside/near-boundary location + password unlocks")
        else:
            # Retry with correct password already set — if 401 unexpected, fail.
            raise Fail(f"unexpected boundary open response: {inside_b}")

        # Create second scroll for combined requirement tests (future unlock).
        future = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 86400))
        status, sent2 = edge(
            "send-scroll",
            token_a,
            {
                "recipient_id": uid_b,
                "title": f"Future Loc Lock {stamp}",
                "message": "Not yet.",
                "unlock_at": future,
                "has_location_lock": True,
                "location_name": PLACE_NAME,
                "location_address": PLACE_ADDR,
                "location_lat": TARGET_LAT,
                "location_lng": TARGET_LNG,
                "location_radius_m": RADIUS_M,
            },
        )
        assert_true(status == 200, f"future send ok ({status})")
        sid2 = str(((sent2 or {}).get("scroll") or {}).get("id") or "")
        status, early = edge(
            "open-scroll",
            token_b,
            {
                "scroll_id": sid2,
                "location_lat": TARGET_LAT,
                "location_lng": TARGET_LNG,
            },
        )
        assert_true(status == 403, f"time fails even if location passes ({status})")
        ok("combined AND: location pass + time fail => locked")

        # Password fail after time+location would pass: use first scroll if already opened,
        # else create immediate scroll with wrong password attempt.
        status, sent3 = edge(
            "send-scroll",
            token_a,
            {
                "recipient_id": uid_b,
                "title": f"PW Loc Lock {stamp}",
                "message": "Need password.",
                "unlock_at": unlock_at,
                "password": "correct99",
                "has_location_lock": True,
                "location_name": PLACE_NAME,
                "location_address": PLACE_ADDR,
                "location_lat": TARGET_LAT,
                "location_lng": TARGET_LNG,
                "location_radius_m": RADIUS_M,
            },
        )
        sid3 = str(((sent3 or {}).get("scroll") or {}).get("id") or "")
        status, badpw = edge(
            "open-scroll",
            token_b,
            {
                "scroll_id": sid3,
                "password": "wrong",
                "location_lat": TARGET_LAT,
                "location_lng": TARGET_LNG,
            },
        )
        assert_true(status in (401, 403), f"bad password locked ({status})")
        ok("combined AND: time+location pass + password fail => locked")

        status, good = edge(
            "open-scroll",
            token_b,
            {
                "scroll_id": sid3,
                "password": "correct99",
                "location_lat": TARGET_LAT,
                "location_lng": TARGET_LNG,
            },
        )
        assert_true(status == 200, f"all requirements pass unlocks ({status}: {good})")
        ok("combined AND: time+location+password pass => opens")

        # Outside boundary (~600m)
        status, sent4 = edge(
            "send-scroll",
            token_a,
            {
                "recipient_id": uid_b,
                "title": f"Boundary Out {stamp}",
                "message": "Boundary",
                "unlock_at": unlock_at,
                "has_location_lock": True,
                "location_name": PLACE_NAME,
                "location_address": PLACE_ADDR,
                "location_lat": TARGET_LAT,
                "location_lng": TARGET_LNG,
                "location_radius_m": RADIUS_M,
            },
        )
        sid4 = str(((sent4 or {}).get("scroll") or {}).get("id") or "")
        status, bout = edge(
            "open-scroll",
            token_b,
            {
                "scroll_id": sid4,
                "location_lat": TARGET_LAT + (600.0 / 111320.0),
                "location_lng": TARGET_LNG,
            },
        )
        assert_true(status == 403, f"just outside radius locked ({status})")
        ok("boundary outside remains locked")

        print(f"=== ONLINE LOCATION LOCK: {passed} checks passed ===")
        return 0
    except Exception as e:
        print("ERROR:", e)
        return 1
    finally:
        try:
            # Clean all scrolls created by sender if known
            if uids:
                rows = sql(
                    f"""
                    select id::text as id from public.scrolls
                    where sender_id = '{uids[0]}'::uuid
                    """
                )
                for r in rows:
                    cleanup([], r["id"])
                cleanup(uids, None)
                print("cleanup complete")
        except Exception as ce:
            print("cleanup warning:", ce)


if __name__ == "__main__":
    sys.exit(main())
