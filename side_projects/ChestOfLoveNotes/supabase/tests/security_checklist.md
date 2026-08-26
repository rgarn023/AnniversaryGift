# Chest of Love Notes — Security Checklist

Manual / automated assertions for the Supabase backend.

## Auth & identity

- [ ] Every edge function rejects requests without a valid JWT (`401`).
- [ ] Caller id is always taken from `auth.getUser()` — never from `body.sender_id`.
- [ ] `SUPABASE_SERVICE_ROLE_KEY` and `MESSAGE_ENCRYPTION_KEY` exist only in edge secrets / server env — never shipped in the Godot client.

## Profiles

- [ ] Authenticated users can upsert / update **their own** profile only.
- [ ] Profile search returns `id, username, display_name, friend_code, avatar_url` only — **never email**.
- [ ] `username` is citext-unique; `friend_code` is unique (`CHEST-XXXXXX`).

## Friend requests & friendships

- [ ] No self friend requests (DB check + edge validation).
- [ ] At most one pending request per directed pair.
- [ ] Requests are visible only to sender and recipient.
- [ ] Only the recipient can accept/decline; only the sender can cancel.
- [ ] Accept creates a normalized friendship (`user_one_id < user_two_id`).
- [ ] Friendships are readable only by participants; clients cannot insert friendships directly.

## Blocks

- [ ] Blocker can insert/select/delete own blocks.
- [ ] Blocking removes friendship and cancels pending requests.
- [ ] `is_blocked` prevents friend requests and scroll send/open.

## Scrolls & contents

- [ ] Clients can `SELECT` scroll **metadata** only when they are sender or recipient and `deleted_at IS NULL`.
- [ ] Clients **cannot** `INSERT` / `UPDATE` / `DELETE` on `scrolls` (no RLS policies).
- [ ] Clients **cannot** `SELECT` / `INSERT` / `UPDATE` / `DELETE` on `scroll_contents` (no RLS policies).
- [ ] `unlock_at`, `is_opened`, `opened_at` are not client-writable.
- [ ] `send-scroll` requires friendship, encrypts with AES-GCM, hashes optional password (4–64 chars), writes both tables via service role.
- [ ] `open-scroll` enforces check order: auth → recipient → not deleted → blocks → unlock_at → rate limit → password → decrypt → mark opened → return message.
- [ ] Failed password attempts are recorded in `scroll_open_attempts` and rate-limited.

## Account deletion

- [ ] `delete-account` requires `{ confirm: true }` and deletes the auth user (cascade cleans related rows).

## Automated test

Run (against local Supabase with env configured):

```bash
cd supabase/tests
deno test --allow-env --allow-net rls_security_test.ts
```

If env vars are missing, the suite skips with a clear message (see `rls_security_test.ts`).
