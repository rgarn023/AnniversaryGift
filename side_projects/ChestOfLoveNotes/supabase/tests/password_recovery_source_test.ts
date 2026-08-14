/**
 * Source / contract tests for sender Magic Password recovery.
 * Does NOT call remote DB, create users, or deploy.
 *
 *   deno test --allow-read password_recovery_source_test.ts
 */

import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

const ROOT = new URL("../", import.meta.url);

async function read(rel: string): Promise<string> {
  return await Deno.readTextFile(new URL(rel, ROOT));
}

Deno.test("migration creates scroll_sender_secrets with forced RLS and no client policies", async () => {
  const sql = await read("migrations/20260807120000_scroll_sender_secrets.sql");
  assertStringIncludes(sql, "create table if not exists public.scroll_sender_secrets");
  for (const col of [
    "scroll_id uuid primary key",
    "sender_id uuid not null",
    "encrypted_magic_password text not null",
    "encryption_iv text not null",
    "encryption_version text not null",
    "created_at timestamptz",
    "updated_at timestamptz",
  ]) {
    assertStringIncludes(sql, col);
  }
  assertStringIncludes(sql, "enable row level security");
  assertStringIncludes(sql, "force row level security");
  assertStringIncludes(sql, "revoke all on table public.scroll_sender_secrets from anon, authenticated, public");
  assertStringIncludes(sql, "grant all on table public.scroll_sender_secrets to service_role");
  assert(
    !sql.toLowerCase().includes("for select") &&
      !sql.toLowerCase().includes("for insert"),
    "must not create client SELECT/INSERT policies",
  );
  assert(!/\bdrop table\b/i.test(sql), "migration must not drop tables");
  assert(!/\btruncate\b/i.test(sql), "migration must not truncate");
  assert(!/\bdelete from\b/i.test(sql), "migration must not delete rows");
});

Deno.test("send-scroll hashes password and stores encrypted recovery separately", async () => {
  const src = await read("functions/send-scroll/index.ts");
  const crypto = await read("functions/_shared/crypto.ts");
  assertStringIncludes(src, "hashPassword");
  assertStringIncludes(src, "encryptMagicPasswordForSender");
  assertStringIncludes(src, "scroll_sender_secrets");
  assertStringIncludes(src, "password_hash");
  assertStringIncludes(crypto, "MAGIC_PASSWORD_RECOVERY_KEY");
  assertStringIncludes(crypto, "MESSAGE_ENCRYPTION_KEY");
  assert(
    crypto.includes("parseKeyFromEnv(\"MAGIC_PASSWORD_RECOVERY_KEY\")") ||
      crypto.includes('parseKeyFromEnv("MAGIC_PASSWORD_RECOVERY_KEY")'),
    "recovery uses dedicated key parser",
  );
  assert(!src.includes("console.log(body.password)"), "must not log password");
  assert(!src.includes("console.log(magicPassword)"), "must not log magic password");
});

Deno.test("reveal-sent-scroll-password enforces sender-only access", async () => {
  const src = await read("functions/reveal-sent-scroll-password/index.ts");
  assertStringIncludes(src, "requirePrivateMember");
  assertStringIncludes(src, "requireUser");
  assertStringIncludes(src, "scroll.sender_id !== me");
  assertStringIncludes(src, "403");
  assertStringIncludes(src, "scroll_sender_states");
  assertStringIncludes(src, "deleted_at");
  assertStringIncludes(src, "decryptMagicPasswordForSender");
  assertStringIncludes(src, "magic_password: password");
  assertStringIncludes(src, "jsonResponse({");
  assert(
    !/password_hash\s*:/.test(src),
    "must not return password_hash as a response field",
  );
  assert(!src.includes("encrypted_magic_password: secret"), "must not return ciphertext value");
});

Deno.test("recovery key name is documented and not hardcoded as a literal secret", async () => {
  const crypto = await read("functions/_shared/crypto.ts");
  assertStringIncludes(crypto, 'Deno.env.get(envName)');
  assert(!/MAGIC_PASSWORD_RECOVERY_KEY\s*=\s*["'][A-Za-z0-9+/=]{20,}/.test(crypto));
  const envExample = await read(".env.example");
  assertStringIncludes(envExample, "MAGIC_PASSWORD_RECOVERY_KEY=");
  assertStringIncludes(envExample, "replace-me");
});
