/**
 * Source / contract tests for private onboarding allowlist + claim flow.
 * Does NOT call the remote database, create users, or deploy anything.
 *
 *   deno test --allow-read private_onboarding_source_test.ts
 */

import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

const ROOT = new URL("../", import.meta.url);

async function read(rel: string): Promise<string> {
  return await Deno.readTextFile(new URL(rel, ROOT));
}

Deno.test("allowlist schema has exact columns and no enabled flag", async () => {
  const sql = await read("migrations/20260806200000_private_app_members.sql");
  assertStringIncludes(sql, "create table if not exists public.private_app_allowlist");
  for (const col of [
    "id uuid",
    "email text not null",
    "label text not null",
    "created_at timestamptz",
    "created_by uuid",
    "consumed_at timestamptz",
    "consumed_user_id uuid",
  ]) {
    assertStringIncludes(sql, col);
  }
  assertStringIncludes(sql, "email = lower(email)");
  assertStringIncludes(sql, "private_app_allowlist_email_unique");
  assert(!/\benabled\b/i.test(sql), "schema has no enabled column");
  assertStringIncludes(sql, "check (role in ('member', 'admin'))");
  assert(!sql.includes("'owner'"), "schema has no owner role");
});

Deno.test("claim normalizes email with lower(trim) and returns 403 when not allowlisted", async () => {
  const sql = await read("migrations/20260806200000_private_app_members.sql");
  const fn = await read("functions/claim-private-membership/index.ts");
  assertStringIncludes(sql, "normalized text := lower(trim(p_email))");
  assertStringIncludes(fn, ".trim().toLowerCase()");
  assertStringIncludes(fn, "403");
  assertStringIncludes(fn, "not invited to the private app");
  assert(
    !fn.includes("body.user_id") && !fn.includes("body.email"),
    "edge claim must derive identity from JWT, not client-selected ids",
  );
});

Deno.test("already active members can reclaim / re-enter", async () => {
  const sql = await read("migrations/20260806200000_private_app_members.sql");
  assertStringIncludes(sql, "if found and member_row.status = 'active' then");
  assertStringIncludes(sql, "consumed_at is null or consumed_user_id = p_user_id");
});

Deno.test("RLS blocks client reads of allowlist emails", async () => {
  const sql = await read("migrations/20260806200000_private_app_members.sql");
  assertStringIncludes(sql, "alter table public.private_app_allowlist enable row level security");
  assertStringIncludes(sql, "force row level security");
  assert(
    !sql.includes("on public.private_app_allowlist\n  for select"),
    "no authenticated SELECT policy on allowlist (emails stay private)",
  );
  assertStringIncludes(sql, "private_app_members_select_own");
});

Deno.test("SQL invite template uses placeholders only", async () => {
  const tpl = await read("sql/private_allowlist_templates.sql");
  assertStringIncludes(tpl, "ROBERT_EMAIL_PLACEHOLDER");
  assertStringIncludes(tpl, "MANDY_EMAIL_PLACEHOLDER");
  assertStringIncludes(tpl, "lower(trim(");
  assertStringIncludes(tpl, "on conflict (email) do update");
  assertStringIncludes(tpl, "role = 'admin'");
  assert(!/@[a-z0-9.-]+\.[a-z]{2,}/i.test(tpl), "template must not contain real email addresses");
});
