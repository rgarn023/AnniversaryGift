# V74 Auth Setup — Password Recovery + Google Sign-In

Chest of Love Notes v74 adds **Forgot Password** and **Continue with Google** using Supabase Auth.
The APK alone cannot complete Google login until Google Cloud and the Supabase dashboard are configured.

**Do not put secrets in this file or in the APK.** Placeholders only.

---

## Two redirect layers (read carefully)

There are **two different callbacks**. Mixing them up is the most common setup failure.

### 1) Google → Supabase (OAuth provider callback)

Google redirects the browser back to **Supabase**, not directly into the app.

Typical Supabase callback URL (replace with your project ref):

```text
https://YOUR_PROJECT_REF.supabase.co/auth/v1/callback
```

This value goes in:

- Google Cloud Console → OAuth client → **Authorized redirect URIs**
- Supabase uses this internally when the Google provider is enabled

### 2) Supabase → App (native deep link)

After Supabase finishes auth (Google OAuth or password recovery), it redirects into the Android app:

```text
com.charoitegames.chestoflovenotes://auth-callback
```

- **Scheme:** `com.charoitegames.chestoflovenotes`
- **Host:** `auth-callback`
- **Package ID:** `com.charoitegames.chestoflovenotes`

This value goes in:

- Supabase → Authentication → URL Configuration → **Redirect URLs** (allow list)
- Password recovery `redirect_to`
- Google OAuth `redirect_to` from the app

**Do not** register the app custom URI as Google’s OAuth redirect URI unless Supabase’s docs for your exact setup explicitly require that architecture. For standard Supabase Google provider setup, Google redirects to **Supabase**, and Supabase redirects to the **app**.

---

## Supabase dashboard steps

1. Open your Supabase project.
2. Go to **Authentication → Providers → Google**.
3. **Enable** the Google provider.
4. Paste the **Google Client ID** (Web client) into Supabase.
5. Paste the **Google Client Secret** into Supabase (dashboard only — never into the APK or git).
6. Save.

### Auth URL configuration

1. Go to **Authentication → URL Configuration**.
2. Add to **Redirect URLs**:

```text
com.charoitegames.chestoflovenotes://auth-callback
```

3. Keep any existing Site URL you already use for web/admin tools.
4. Optional but recommended: enable email password recovery if not already on (default for email provider).

### Identity linking (existing email accounts)

To reduce accidental duplicate accounts when a Google identity matches a verified email:

1. Review Supabase Auth settings for **automatic linking** / **manual linking** for your project version.
2. Prefer keeping automatic linking of verified same-email identities enabled when available.
3. The app also exposes **Link Google Account** under Profile → Account & Security for an already signed-in user (uses Supabase identity authorize / authorize fallback).

The app **never** copies user data between UUIDs or rewrites ownership by email.

---

## Google Cloud Console steps

1. Create or select a Google Cloud project.
2. Configure the **OAuth consent screen** (External or Internal as appropriate).
3. Create OAuth credentials:
   - **Web application** client (required by Supabase’s Google provider for client ID + secret).
4. On that Web client, add **Authorized redirect URI**:

```text
https://YOUR_PROJECT_REF.supabase.co/auth/v1/callback
```

5. Copy the Web client **Client ID** and **Client Secret** into Supabase (step above).

### Android package / SHA (when Google requires it)

If you also create an **Android** OAuth client (optional depending on Google/Supabase guidance):

- **Package name:** `com.charoitegames.chestoflovenotes`
- **SHA-1 / SHA-256:** use the certificate fingerprint of the keystore that signs the installed APK/AAB (same identity as v72/v73/v74).

You can inspect the release cert SHA-256 with:

```bash
keytool -list -v -keystore android/signing/chest_test_debug.keystore -alias androiddebugkey
```

(Use the production keystore fingerprint for Play Store builds.)

---

## Android app deep link (already in v74 code)

The install script registers an intent filter:

- Action: `VIEW`
- Categories: `DEFAULT`, `BROWSABLE`
- Data: scheme `com.charoitegames.chestoflovenotes`, host `auth-callback`

Cold start and warm start both capture the callback via the ChestNotify Android plugin (`consume_pending_auth_callback`). The URI is consumed once and never logged with tokens.

---

## What the APK contains (safe)

- Supabase **URL**
- Supabase **publishable/anon key**
- App redirect URI constant
- PKCE code verifier generated at runtime (not shipped)

## What must never be committed or embedded

- Google client **secret**
- Supabase **service role** key
- Any private OAuth credentials

---

## Smoke checklist after dashboard config

1. Forgot Password → email arrives → link opens app → Create New Password works.
2. Continue with Google → browser → returns to app → same session as email login.
3. Existing email user with matching Google email → lands on **same** Supabase user UUID (no second account).
4. Profile → Account & Security → providers reflect linked identities.
5. Sign out → secure session cleared → sign back in.

Until steps above are done:

**GOOGLE LOGIN REQUIRES DASHBOARD CONFIGURATION**
