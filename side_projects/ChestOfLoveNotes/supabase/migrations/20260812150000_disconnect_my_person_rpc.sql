-- Atomic authenticated disconnect for My Person.
--
-- Root cause of "Can't disconnect" on device (v34):
-- Edge Function disconnect-person called record_my_person_pair_end after deleting
-- friendships. When migration 20260812140000 was not applied, that RPC was missing
-- → edge returned disconnect_failed → client correctly kept Mandy visible.
--
-- Fix:
-- 1) Ensure durable tombstone table exists (idempotent with prior migration).
-- 2) Provide disconnect_my_person() SECURITY DEFINER using auth.uid().
-- 3) Single transaction: find pair → tombstone → cancel requests → delete friendships → verify.
-- Either participant may call it. Unrelated users cannot affect others' pairs.
-- Scrolls / history are never touched.

set search_path to public, extensions;

-- ---------------------------------------------------------------------------
-- Idempotent tombstone (safe if 20260812140000 already applied)
-- ---------------------------------------------------------------------------
create table if not exists public.my_person_pair_ends (
  user_one_id uuid not null references public.profiles (id) on delete cascade,
  user_two_id uuid not null references public.profiles (id) on delete cascade,
  disconnected_at timestamptz not null default timezone('utc', now()),
  ended_by uuid null references public.profiles (id) on delete set null,
  constraint my_person_pair_ends_ordered check (user_one_id < user_two_id),
  primary key (user_one_id, user_two_id)
);

alter table public.my_person_pair_ends enable row level security;
alter table public.my_person_pair_ends force row level security;

drop policy if exists my_person_pair_ends_select_parties on public.my_person_pair_ends;
create policy my_person_pair_ends_select_parties
  on public.my_person_pair_ends
  for select
  to authenticated
  using (user_one_id = auth.uid() or user_two_id = auth.uid());

create or replace function public.record_my_person_pair_end(p_a uuid, p_b uuid, p_ended_by uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  u1 uuid := least(p_a, p_b);
  u2 uuid := greatest(p_a, p_b);
begin
  if p_a is null or p_b is null or p_a = p_b then
    return;
  end if;
  insert into public.my_person_pair_ends (user_one_id, user_two_id, ended_by, disconnected_at)
  values (u1, u2, p_ended_by, timezone('utc', now()))
  on conflict (user_one_id, user_two_id) do update
    set disconnected_at = excluded.disconnected_at,
        ended_by = coalesce(excluded.ended_by, public.my_person_pair_ends.ended_by);
end;
$$;

create or replace function public.clear_my_person_pair_end(p_a uuid, p_b uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  u1 uuid := least(p_a, p_b);
  u2 uuid := greatest(p_a, p_b);
begin
  if p_a is null or p_b is null or p_a = p_b then
    return;
  end if;
  delete from public.my_person_pair_ends
  where user_one_id = u1 and user_two_id = u2;
end;
$$;

revoke all on function public.record_my_person_pair_end(uuid, uuid, uuid) from public;
revoke all on function public.clear_my_person_pair_end(uuid, uuid) from public;
grant execute on function public.record_my_person_pair_end(uuid, uuid, uuid) to service_role;
grant execute on function public.clear_my_person_pair_end(uuid, uuid) to service_role;

-- ---------------------------------------------------------------------------
-- Canonical mutual disconnect (auth.uid() — never trust client actor id)
-- ---------------------------------------------------------------------------
create or replace function public.disconnect_my_person()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  r record;
  other_id uuid;
  deleted_ids uuid[] := '{}';
  other_ids uuid[] := '{}';
  rows_affected int := 0;
  still_active boolean := false;
  now_ts timestamptz := timezone('utc', now());
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  -- Same canonical active-person definition as has_active_person / get-friends:
  -- presence of a friendships row where the caller is either participant.
  for r in
    select f.id, f.user_one_id, f.user_two_id
    from public.friendships f
    where f.user_one_id = uid or f.user_two_id = uid
  loop
    deleted_ids := array_append(deleted_ids, r.id);
    other_id := case when r.user_one_id = uid then r.user_two_id else r.user_one_id end;
    if other_id is not null and not (other_id = any (other_ids)) then
      other_ids := array_append(other_ids, other_id);
    end if;
  end loop;

  rows_affected := coalesce(cardinality(deleted_ids), 0);
  if rows_affected = 0 then
    return jsonb_build_object(
      'success', false,
      'ok', false,
      'relationship_found', false,
      'disconnected', false,
      'verified_disconnected', false,
      'rows_affected', 0,
      'active_pairing', false,
      'person', null,
      'relationship_status', 'none',
      'error_code', 'not_connected',
      'failure_category', 'No Row'
    );
  end if;

  -- Tombstone BEFORE delete so concurrent reconcile/accept cannot recreate mid-flight.
  foreach other_id in array other_ids
  loop
    perform public.record_my_person_pair_end(uid, other_id, uid);

    update public.friend_requests fr
    set
      status = 'cancelled',
      responded_at = coalesce(fr.responded_at, now_ts),
      updated_at = now_ts
    where fr.status in ('accepted', 'pending')
      and (
        (fr.sender_id = uid and fr.recipient_id = other_id)
        or (fr.sender_id = other_id and fr.recipient_id = uid)
      );
  end loop;

  delete from public.friendships f
  where f.id = any (deleted_ids);

  select public.has_active_person(uid) into still_active;
  if still_active then
    raise exception 'disconnect_verify_failed'
      using errcode = 'P0001',
            hint = 'Active friendship remained after disconnect.';
  end if;

  return jsonb_build_object(
    'success', true,
    'ok', true,
    'relationship_found', true,
    'disconnected', true,
    'verified_disconnected', true,
    'rows_affected', rows_affected,
    'active_pairing', false,
    'person', null,
    'relationship_status', 'disconnected',
    'error_code', null,
    'failure_category', 'None'
  );
end;
$$;

comment on function public.disconnect_my_person() is
  'Authenticated mutual My Person disconnect. Either participant may end the active friendships row. Uses auth.uid().';

revoke all on function public.disconnect_my_person() from public;
grant execute on function public.disconnect_my_person() to authenticated, service_role;

-- Neutralize reconcile if older migration left recreate behavior (idempotent).
create or replace function public.reconcile_my_person_pairing()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  existing uuid;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  select f.id into existing
  from public.friendships f
  where f.user_one_id = uid or f.user_two_id = uid
  limit 1;
  return existing;
end;
$$;

revoke all on function public.reconcile_my_person_pairing() from public;
grant execute on function public.reconcile_my_person_pairing() to authenticated, service_role;
