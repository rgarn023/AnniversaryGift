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

        val launch = packageManager.getLaunchIntentForPackage(packageName)
        if (launch != null) {
            launch.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            startActivity(launch)
        }
        finish()
    }
}
