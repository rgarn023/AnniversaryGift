/**
 * Local source / contract tests for permanent-scroll Edge Functions.
 * Does NOT call the remote database or deploy anything.
 *
 *   deno test --allow-read permanent_scroll_source_test.ts
 */

import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  assertNoSensitiveKeys,
  recipientScrollSafe,
  sentScrollSafe,
} from "../functions/_shared/scroll_meta.ts";

const ROOT = new URL("../functions/", import.meta.url);

async function readFn(name: string): Promise<string> {
  return await Deno.readTextFile(new URL(`${name}/index.ts`, ROOT));
}

Deno.test("send-scroll creates state via ensure_scroll_party_states", async () => {
  const src = await readFn("send-scroll");
  assertStringIncludes(src, "requirePrivateMember");
  assertStringIncludes(src, "ensure_scroll_party_states");
  assertStringIncludes(src, "scroll_recipient_states");
  assertStringIncludes(src, "scroll_sender_states");
  assert(
    !src.includes('sender_id: body.sender_id') &&
      !src.includes("sender_id: body[") &&
      src.includes("sender_id: me"),
    "must derive sender_id from session (me), not client body",
  );
});

Deno.test("open-scroll uses mark_recipient_scroll_opened via user client", async () => {
  const src = await readFn("open-scroll");
  assertStringIncludes(src, "requirePrivateMember");
  assertStringIncludes(src, "mark_recipient_scroll_opened");
  assertStringIncludes(src, "createUserClient");
  assertStringIncludes(src, "deleted_at");
  // Must not authoritatively write legacy fields directly anymore.
  assert(
    !src.includes('.update({ is_opened: true, opened_at:'),
    "open-scroll must not directly update scrolls.is_opened",
  );
});

Deno.test("get-chest uses recipient state and excludes saved/deleted", async () => {
  const src = await readFn("get-chest");
  assertStringIncludes(src, "scroll_recipient_states");
  assertStringIncludes(src, 'eq("is_saved", false)');
  assertStringIncludes(src, '.is("deleted_at", null)');
  assertStringIncludes(src, "friend_requests");
  assert(!src.includes("ciphertext"));
});

Deno.test("get-saved-scrolls filters saved recipient state", async () => {
  const src = await readFn("get-saved-scrolls");
  assertStringIncludes(src, 'eq("is_saved", true)');
  assertStringIncludes(src, "requirePrivateMember");
  assertStringIncludes(src, "favorites_only");
  assert(!src.toLowerCase().includes("decrypt"));
});

Deno.test("favorite / delete functions call secured RPCs", async () => {
  const fav = await readFn("update-scroll-favorite");
  const delR = await readFn("delete-received-scroll");
  const delS = await readFn("delete-sent-scroll");
  assertStringIncludes(fav, "set_recipient_scroll_favorite");
  assertStringIncludes(delR, "soft_delete_recipient_scroll");
  assertStringIncludes(delS, "soft_delete_sender_scroll");
  assertStringIncludes(fav, "requirePrivateMember");
  assertStringIncludes(delR, "requirePrivateMember");
  assertStringIncludes(delS, "requirePrivateMember");
  assertStringIncludes(delR, "physical_erasure: false");
  assertStringIncludes(delS, "recalled: false");
});

Deno.test("get-sent-scrolls joins sender state", async () => {
  const src = await readFn("get-sent-scrolls");
  assertStringIncludes(src, "scroll_sender_states");
  assertStringIncludes(src, '.is("deleted_at", null)');
  assertStringIncludes(src, "scroll_recipient_states");
});

Deno.test("safe metadata helpers never include sensitive keys", () => {
  const item = recipientScrollSafe({
    scroll: {
      id: "s1",
      sender_id: "a",
      recipient_id: "b",
      title: "Hi",
      unlock_at: new Date().toISOString(),
      has_password: true,
      created_at: new Date().toISOString(),
    },
    state: {
      is_read: true,
      is_saved: true,
      is_favorite: false,
      first_opened_at: null,
      last_opened_at: null,
      opened_count: 1,
    },
  });
  assertEquals(item.is_saved, true);
  assertNoSensitiveKeys(item);

  const sent = sentScrollSafe({
    scroll: {
      id: "s1",
      sender_id: "a",
      recipient_id: "b",
      title: "Hi",
      unlock_at: new Date().toISOString(),
      has_password: false,
      created_at: new Date().toISOString(),
    },
    senderState: { deleted_at: null },
    recipientState: { is_read: true, opened_count: 2, first_opened_at: "t", last_opened_at: "t2" },
  });
  assertEquals(sent.opened_count, 2);
  assertNoSensitiveKeys(sent);
});

Deno.test("assertNoSensitiveKeys catches ciphertext", () => {
  let threw = false;
  try {
    assertNoSensitiveKeys({ scroll: { ciphertext: "x" } });
  } catch {
    threw = true;
  }
  assert(threw);
});

Deno.test("all updated handlers require private membership", async () => {
  const names = [
    "send-scroll",
    "open-scroll",
    "get-chest",
    "get-sent-scrolls",
    "get-saved-scrolls",
    "update-scroll-favorite",
    "delete-received-scroll",
    "delete-sent-scroll",
  ];
  for (const name of names) {
    const src = await readFn(name);
    assertStringIncludes(src, "requirePrivateMember", `${name} missing private check`);
    assertStringIncludes(src, "requireUser", `${name} missing auth`);
  }
});
