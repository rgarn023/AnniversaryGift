# Supabase setup — Chest of Love Notes

Backend lives entirely under `supabase/`.

## Quick start

1. Install [Supabase CLI](https://supabase.com/docs/guides/cli).
2. From this directory:

```bash
supabase start
supabase db reset
```

3. Copy keys from `supabase status` into a local `.env` for edge serve (never commit):

```env
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_ANON_KEY=...
SUPABASE_SERVICE_ROLE_KEY=...
MESSAGE_ENCRYPTION_KEY=<openssl rand -base64 32>
```

4. Serve functions:

```bash
supabase functions serve --env-file .env
```

5. Optional security tests:

```bash
cd supabase/tests
export SUPABASE_URL SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY
deno test --allow-env --allow-net rls_security_test.ts
```

## Profile bootstrap

There is **no** auth trigger that auto-creates a profile. After signup, the client should upsert:

```json
{
  "id": "<auth.uid()>",
  "username": "normalized_name",
  "display_name": "Display Name",
  "friend_code": "<from generate_friend_code() RPC or client helper>"
}
```

Use `select public.generate_friend_code()` / RPC to allocate a unique code.

## Demo content

`supabase/seed/demo_seed.sql` is intentionally a no-op. Fictional demo scrolls ship in the Godot **LOCAL DEMO MODE** only — not as real private DB messages.
