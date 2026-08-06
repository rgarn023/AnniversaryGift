# Edge Functions — Chest of Love Notes

TypeScript Deno functions for friend graph + encrypted scrolls.

## Functions

| Name | Purpose |
|------|---------|
| `send-friend-request` | Create pending request by `recipient_id` or `friend_code` |
| `respond-to-friend-request` | Accept / decline / cancel; accept creates friendship |
| `block-user` | Block or unblock; removes friendship + pending requests |
| `send-scroll` | Validate friendship, encrypt message, optional password hash |
| `open-scroll` | Auth → recipient → deleted → block → unlock → rate limit → password → decrypt |
| `delete-account` | `{ confirm: true }` hard-deletes auth user (cascade) |
| `search-profiles` | Public profile fields only (no email) |
| `get-chest` | Recipient scroll metadata for the caller's chest |
| `get-friends` | Friends + pending incoming/outgoing requests |
| `get-sent-scrolls` | Sender scroll metadata |

## Required secrets

Set via `supabase secrets set` (never commit real values):

```bash
supabase secrets set MESSAGE_ENCRYPTION_KEY="<base64-or-hex-32-bytes>"
```

Supabase injects automatically in hosted / local edge runtime:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`

Generate a local encryption key:

```bash
openssl rand -base64 32
```

Password hashing uses **bcrypt** as a Deno-compatible fallback. Prefer **Argon2id** in production if you swap the hasher in `_shared/crypto.ts`.

## Local serve

```bash
# from repo: side_projects/ChestOfLoveNotes
supabase start
supabase db reset   # applies migrations + seed (seed is a no-op)
supabase functions serve --env-file .env.local
```

Example `.env.local` (do not commit):

```env
MESSAGE_ENCRYPTION_KEY=REPLACE_WITH_BASE64_32_BYTES
```

## Deploy

```bash
supabase link --project-ref <your-project-ref>
supabase db push
supabase functions deploy send-friend-request
supabase functions deploy respond-to-friend-request
supabase functions deploy block-user
supabase functions deploy send-scroll
supabase functions deploy open-scroll
supabase functions deploy delete-account
supabase functions deploy search-profiles
supabase functions deploy get-chest
supabase functions deploy get-friends
supabase functions deploy get-sent-scrolls
supabase secrets set MESSAGE_ENCRYPTION_KEY="$(openssl rand -base64 32)"
```

Or deploy all:

```bash
supabase functions deploy
```

## Client calling convention

```http
POST /functions/v1/<name>
Authorization: Bearer <user-access-token>
apikey: <anon-key>
Content-Type: application/json
```

Never send `sender_id` from the client as an authority — the function always uses the JWT subject.
