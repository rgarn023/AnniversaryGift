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
4. Password recovery must be enabled for the email provider.
5. If you use a customized password-recovery email template, make sure it honors Supabase's redirect target (`RedirectTo`) so the recovery flow returns to the app callback above.

### Identity linking (existing email accounts)

Supabase can automatically link certain verified identities that share the same email, but the explicit **Link Google Account** button uses Supabase's manual identity-linking flow.

For that button to work:

1. Go to the project's **Authentication** configuration/settings.
2. Enable **Manual identity linking** for the project.
3. Keep the user signed in to the existing Chest account before tapping **Link Google Account**.
4. Complete Google OAuth in the browser and return to the app.
5. Verify Profile → Account & Security shows Google as linked.

The app uses Supabase's authenticated `/user/identities/authorize` flow for explicit linking. It deliberately does **not** fall back to ordinary Google sign-in if manual linking is unavailable, because ordinary sign-in could switch to a different Supabase user UUID instead of safely linking the identity.

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

You can inspect the test/release candidate cert SHA-256 with:

```bash
keytool -list -v -keystore android/signing/chest_test_debug.keystore -alias androiddebugkey
```

Use the production/Play signing certificate fingerprint for a Play Store production configuration.

---

## Android app deep link (already in v74 code)

The install script registers an intent filter:

- Action: `VIEW`
- Categories: `DEFAULT`, `BROWSABLE`
- Data: scheme `com.charoitegames.chestoflovenotes`, host `auth-callback`

Cold start and warm start capture the callback through the ChestNotify Android plugin. The callback is retained in app-private storage until AuthService reaches a terminal success/error; transient network failures keep it available for a retry. Raw callback URLs are never logged.

Google OAuth uses PKCE. The short-lived PKCE verifier/mode are encrypted separately with the existing Android Keystore-backed secure-storage plugin, so the Google browser flow can survive Android killing and recreating the app process. The transient PKCE state is expired and deleted automatically and is separate from the normal Keep Me Signed In session.

---

## What the APK contains (safe)

- Supabase **URL**
- Supabase **publishable/anon key**
- App redirect URI constant
- Code that generates PKCE verifiers at runtime using Godot's cryptographically secure `Crypto.generate_random_bytes()`

## What is generated only at runtime

- PKCE code verifier
- PKCE challenge
- authorization code
- access/refresh session tokens

The PKCE verifier is never shipped in the APK and is never stored as plaintext under `user://`.

## What must never be committed or embedded

- Google client **secret**
- Supabase **service role** key
- Any private OAuth credentials

---

## Smoke checklist after dashboard config

1. Forgot Password → email arrives → link opens app → Create New Password works.
2. Continue with Google → browser → returns to app → authenticated Chest session is created.
3. Start Google sign-in, background the app long enough for Android to recreate it, then complete browser OAuth → callback still succeeds.
4. Existing email user with matching Google email → verify it lands on the intended existing Supabase user UUID (no second disconnected account).
5. Signed-in email user → Link Google Account → provider becomes linked without changing the Chest user UUID.
6. Profile → Account & Security → providers reflect linked identities.
7. Sign out → secure session cleared → sign back in.
8. Temporarily lose connectivity as OAuth returns → restore connectivity/resume → pending callback can retry instead of being destroyed before processing.

Until the Google/Supabase dashboard steps above are done:

**GOOGLE LOGIN REQUIRES DASHBOARD CONFIGURATION**
