# Setup Supabase for Chest of Love Notes

Exact steps to connect a real backend. **Never commit production secrets.**

## 1. Create a Supabase project

1. Open https://supabase.com and create a new project.
2. Choose a strong database password and store it in a password manager.
3. Wait until the project is ready.

## 2. Obtain the project URL

Dashboard → **Project Settings → API → Project URL**

Example shape: `https://xxxx.supabase.co`

## 3. Obtain the publishable (anon) key

Dashboard → **Project Settings → API → anon public**

This is the only key allowed in the Godot client.

## 4. Enable email authentication

Dashboard → **Authentication → Providers → Email**

- Enable Email provider
- Enable email confirmations for production
- Configure SMTP / built-in email as needed

## 5. Configure email verification

- Require users to verify before accessing private features
- Customize confirmation email templates if desired
- For local CLI development, use Inbucket / local mail

## 6. Run migrations

From `side_projects/ChestOfLoveNotes`:

```bash
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

Or locally:

```bash
supabase start
supabase db reset
```

Migrations:

- `supabase/migrations/20260806000001_init_schema.sql`
- `supabase/migrations/20260806000002_rls_policies.sql`
- `supabase/migrations/20260806000003_functions.sql`

## 7. Create Edge Function secrets

Required secrets:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY` (server only — never in Godot)
- `MESSAGE_ENCRYPTION_KEY`

## 8. Set MESSAGE_ENCRYPTION_KEY

Generate a 32-byte key:

```bash
openssl rand -base64 32
```

Store it only as an Edge Function / server secret.

## 9. Deploy Edge Functions

```bash
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
```

## 10. Test RLS

```bash
cd supabase/tests
export SUPABASE_URL SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY
deno test --allow-env --allow-net rls_security_test.ts
```

Also walk the checklist in `supabase/tests/security_checklist.md`.

## 11. Create two test accounts

1. Register Account A and verify email
2. Complete profile setup (username + display name)
3. Register Account B and verify email
4. Complete profile setup
5. Exchange friend codes and accept a request
6. Send locked / unlocked / password scrolls

## 12. Android deep links (optional for v0.1)

Configure auth redirect URLs in Supabase for mobile email verification if using custom schemes. Not required for Local Demo Mode.

## 13. Connect the Godot app

From env (preferred for APK exports — never prints secret values):

```bash
# Requires SUPABASE_URL and SUPABASE_ANON_KEY in the environment.
python3 tools/prepare_backend_config.py
python3 tools/verify_backend_config_for_export.py
```

Or manually:

```bash
cp config/backend_config.example.json config/backend_config.json
```

Edit:

```json
{
  "supabase_url": "https://YOUR_PROJECT.supabase.co",
  "supabase_publishable_key": "YOUR_ANON_KEY",
  "environment": "development"
}
```

`config/backend_config.json` is gitignored. Private online APK exports must run the prepare/verify steps first; otherwise Android shows “Backend is not configured.”

## 14. Run backend tests

See step 10 and `supabase/functions/README.md`.

## 15. Confirm no privileged key is in the client

Search the Godot project and APK for:

- `service_role`
- `MESSAGE_ENCRYPTION_KEY`
- private PEM material

Only the project URL + publishable anon key may ship in the client.
