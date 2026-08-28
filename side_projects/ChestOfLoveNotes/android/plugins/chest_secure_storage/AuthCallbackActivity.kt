package com.charoitegames.chestoflovenotes.securestorage

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle

/**
 * Dedicated exported receiver for Supabase password-recovery / Google OAuth
 * callbacks.  The Godot launcher is an activity-alias generated late in the
 * export process, so attaching the VIEW filter to that alias proved unreliable.
 *
 * This Activity validates the exact callback, commits it to the same private
 * SharedPreferences used by ChestNotifyPlugin, brings the normal launcher task
 * to the foreground, and immediately finishes.  No token/code is logged.
 */
class AuthCallbackActivity : Activity() {
    companion object {
        private const val AUTH_SCHEME = "com.charoitegames.chestoflovenotes"
        private const val AUTH_HOST = "auth-callback"
        private const val PREFS = "coln_notify"
        private const val KEY_PENDING_AUTH_CALLBACK = "pending_auth_callback"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleAuthIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAuthIntent(intent)
    }

    private fun handleAuthIntent(source: Intent?) {
        val uri: Uri? = source?.data
        if (uri == null || uri.scheme != AUTH_SCHEME || uri.host != AUTH_HOST) {
            finish()
            return
        }

        // Synchronous commit prevents a race with Godot resuming and reading the
        // pending callback immediately after this forwarding Activity closes.
        applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PENDING_AUTH_CALLBACK, uri.toString())
            .commit()

        // The callback is already committed, so the sign-in completes on the next
        // app open even if none of the launches below succeed. Still, try hard to
        // bring the app forward now: leaving the user parked in the browser looks
        // like a failed sign-in.
        val launch = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
                setPackage(packageName)
            }
        // NOT FLAG_ACTIVITY_CLEAR_TOP. The Godot launcher (GodotAppLauncher) is an
        // activity-alias with launchMode=standard — CI reports this on every build —
        // so CLEAR_TOP tears the activity down and recreates it, restarting the app
        // and replaying the splash on return from Google. getLaunchIntentForPackage
        // already carries FLAG_ACTIVITY_NEW_TASK, and MAIN/LAUNCHER + NEW_TASK is
        // Android's "resume the existing task" path, which is what we want: the app
        // comes back as the user left it and the warm-resume consumer picks the
        // callback up.
        launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        try {
            startActivity(launch)
        } catch (_: Exception) {
            // No resolvable launcher entry; the pending callback still stands.
        }
        finish()
    }
}
