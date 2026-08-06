/**
 * RLS / security smoke tests for Chest of Love Notes.
 *
 * Run against a local Supabase stack when configured:
 *
 *   export SUPABASE_URL=http://127.0.0.1:54321
 *   export SUPABASE_ANON_KEY=...
 *   export SUPABASE_SERVICE_ROLE_KEY=...
 *   deno test --allow-env --allow-net rls_security_test.ts
 *
 * If required env vars are absent, all cases are skipped (exit 0)
 * so CI without a live DB does not fail.
 */

import {
  assert,
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const URL = Deno.env.get("SUPABASE_URL") ?? "";
const ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const configured = Boolean(URL && ANON && SERVICE);

function skipMsg(): string {
  return "Skipping: set SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY to run against local Supabase";
}

Deno.test({
  name: "env configured or skip suite",
  ignore: false,
  fn() {
    if (!configured) {
      console.warn(skipMsg());
    }
    assert(true);
  },
});

Deno.test({
  name: "anon cannot select scroll_contents",
  ignore: !configured,
  async fn() {
    const anon = createClient(URL, ANON);
    const { data, error } = await anon.from("scroll_contents").select("*").limit(1);
    // RLS should deny — either error or empty with no rows readable.
    assert(
      error !== null || data === null || data.length === 0,
      "anon must not read scroll_contents",
    );
  },
});

Deno.test({
  name: "authenticated user cannot select scroll_contents (no policy)",
  ignore: !configured,
  async fn() {
    const service = createClient(URL, SERVICE, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const email = `sec_test_${crypto.randomUUID()}@example.com`;
    const password = "TestPassword123!";
    const { data: created, error: createErr } = await service.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    assertEquals(createErr, null);
    assertExists(created.user);

    const userClient = createClient(URL, ANON);
    const { error: signErr } = await userClient.auth.signInWithPassword({
      email,
      password,
    });
    assertEquals(signErr, null);

    const { data, error } = await userClient
      .from("scroll_contents")
      .select("*")
      .limit(1);

    assert(
      error !== null || data === null || data.length === 0,
      "authenticated client must not read scroll_contents",
    );

    await service.auth.admin.deleteUser(created.user!.id);
  },
});

Deno.test({
  name: "authenticated user cannot insert scrolls directly",
  ignore: !configured,
  async fn() {
    const service = createClient(URL, SERVICE, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const mk = async (label: string) => {
      const email = `${label}_${crypto.randomUUID()}@example.com`;
      const password = "TestPassword123!";
      const { data, error } = await service.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
      });
      assertEquals(error, null);
      const id = data.user!.id;
      await service.from("profiles").upsert({
        id,
        username: `${label}_${id.slice(0, 8)}`,
        display_name: label,
        friend_code: `CHEST-${id.replace(/-/g, "").slice(0, 6).toUpperCase()}`,
      });
      return { id, email, password };
    };

    const a = await mk("alice");
    const b = await mk("bob");

    const userClient = createClient(URL, ANON);
    await userClient.auth.signInWithPassword({
      email: a.email,
      password: a.password,
    });

    const { error } = await userClient.from("scrolls").insert({
      sender_id: a.id,
      recipient_id: b.id,
      title: "Should Fail",
    });

    assertExists(error, "client insert into scrolls must be denied by RLS");

    await service.auth.admin.deleteUser(a.id);
    await service.auth.admin.deleteUser(b.id);
  },
});

Deno.test({
  name: "user cannot update another user's profile",
  ignore: !configured,
  async fn() {
    const service = createClient(URL, SERVICE, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const mk = async (label: string) => {
      const email = `${label}_${crypto.randomUUID()}@example.com`;
      const password = "TestPassword123!";
      const { data, error } = await service.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
      });
      assertEquals(error, null);
      const id = data.user!.id;
      await service.from("profiles").upsert({
        id,
        username: `${label}_${id.slice(0, 8)}`,
        display_name: label,
        friend_code: `CHEST-${id.replace(/-/g, "").slice(0, 6).toUpperCase()}`,
      });
      return { id, email, password };
    };

    const a = await mk("pwa");
    const b = await mk("pwb");

    const userClient = createClient(URL, ANON);
    await userClient.auth.signInWithPassword({
      email: a.email,
      password: a.password,
    });

    const { data, error } = await userClient
      .from("profiles")
      .update({ display_name: "Hacked" })
      .eq("id", b.id)
      .select();

    // RLS using() should filter the row out → no update.
    assert(
      (error !== null) || !data || data.length === 0,
      "must not update another user's profile",
    );

    const { data: victim } = await service
      .from("profiles")
      .select("display_name")
      .eq("id", b.id)
      .single();
    assertEquals(victim?.display_name, "pwb");

    await service.auth.admin.deleteUser(a.id);
    await service.auth.admin.deleteUser(b.id);
  },
});

Deno.test({
  name: "service role can read scroll_contents (edge path)",
  ignore: !configured,
  async fn() {
    const service = createClient(URL, SERVICE, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { error } = await service.from("scroll_contents").select("scroll_id").limit(1);
    assertEquals(error, null, "service role must bypass RLS on scroll_contents");
  },
});

Deno.test({
  name: "documents open-scroll security order",
  ignore: false,
  fn() {
    // Living documentation assertion — keep in sync with open-scroll/index.ts.
    const order = [
      "auth",
      "private_membership",
      "recipient",
      "recipient_not_deleted",
      "blocks",
      "unlock_at",
      "rate_limit",
      "password_verify",
      "decrypt",
      "mark_recipient_scroll_opened",
      "return_message",
    ];
    assertEquals(order.length, 11);
    assertEquals(order[0], "auth");
    assertEquals(order[1], "private_membership");
    assertEquals(order[5], "unlock_at");
    assertEquals(order[9], "mark_recipient_scroll_opened");
    assertEquals(order[10], "return_message");
  },
});
