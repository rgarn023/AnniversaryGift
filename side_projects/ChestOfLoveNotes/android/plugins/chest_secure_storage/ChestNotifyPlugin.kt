package com.charoitegames.chestoflovenotes.securestorage

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.util.Log
import android.view.View
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Local notifications for new scrolls, lock progress, and lock completion.
 * Never includes message body, password, or coordinates.
 * Scheduled-ready uses AlarmManager (inexact) so delivery works while the app is closed.
 */
class ChestNotifyPlugin(godot: Godot) : GodotPlugin(godot) {

	companion object {
		private const val TAG = "ChestNotify"
		private const val PLUGIN_NAME = "ChestNotify"
		const val CH_SCROLLS = "coln_scrolls"
		const val CH_CHALLENGES = "coln_challenges"
		const val CH_CONNECTIONS = "coln_connections"
		/** Legacy aliases kept for existing schedule payloads. */
		const val CH_NEW = CH_SCROLLS
		const val CH_READY = CH_SCROLLS
		const val CH_ACTIVITY = CH_CHALLENGES
		const val CH_FOCUS = CH_CHALLENGES
		private const val PREFS = "coln_notify"
		private const val KEY_PENDING_DEEPLINK = "pending_deeplink"
		private const val KEY_PENDING_AUTH_CALLBACK = "pending_auth_callback"
		/** Custom scheme for Supabase → app auth redirects (password recovery + OAuth). */
		const val AUTH_SCHEME = "com.charoitegames.chestoflovenotes"
		const val AUTH_HOST = "auth-callback"
	}

	override fun getPluginName(): String = PLUGIN_NAME

	private fun appContext(): Context {
		val ctx = godot.context ?: error("Godot context unavailable")
		return ctx.applicationContext
	}

	@UsedByGodot
	fun notify_plugin_available(): Boolean = true

	@UsedByGodot
	fun ensure_channels(): Boolean {
		return try {
			if (Build.VERSION.SDK_INT >= 26) {
				val nm = appContext().getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
				nm.createNotificationChannel(NotificationChannel(CH_SCROLLS, "Scrolls", NotificationManager.IMPORTANCE_DEFAULT))
				nm.createNotificationChannel(NotificationChannel(CH_CHALLENGES, "Challenges", NotificationManager.IMPORTANCE_DEFAULT))
				nm.createNotificationChannel(NotificationChannel(CH_CONNECTIONS, "Connections", NotificationManager.IMPORTANCE_DEFAULT))
			}
			true
		} catch (e: Exception) {
			Log.w(TAG, "ensure_channels failed: ${e.javaClass.simpleName}")
			false
		}
	}

	/** Capture launch deep link extras for Godot cold/warm start. */
	override fun onMainCreate(activity: Activity?): View? {
		val view = super.onMainCreate(activity)
		captureDeepLink(activity?.intent)
		captureAuthCallback(activity?.intent)
		return view
	}

	override fun onMainResume() {
		super.onMainResume()
		// GodotActivity.onNewIntent() replaces Activity.intent before the app resumes,
		// so reading the current intent here covers OAuth/recovery warm returns without
		// relying on a non-existent GodotPlugin.onMainNewIntent lifecycle hook.
		captureDeepLink(getActivity()?.intent)
		captureAuthCallback(getActivity()?.intent)
	}

	private fun captureDeepLink(intent: Intent?) {
		if (intent == null) return
		val link = intent.getStringExtra("coln_deeplink")?.trim().orEmpty()
		if (link.isEmpty()) return
		appContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE)
			.edit()
			.putString(KEY_PENDING_DEEPLINK, link)
			.apply()
		Log.i(TAG, "captured deeplink")
		try {
			intent.removeExtra("coln_deeplink")
		} catch (_: Exception) {
		}
	}

	/**
	 * Capture Supabase auth redirect URIs (custom scheme).
	 * Never logs the URI — it may contain access/refresh tokens or auth codes.
	 */
	private fun captureAuthCallback(intent: Intent?) {
		if (intent == null) return
		val data = intent.data ?: return
		val scheme = data.scheme?.lowercase() ?: return
		if (scheme != AUTH_SCHEME) return
		val host = data.host?.lowercase().orEmpty()
		if (host != AUTH_HOST) return
		val uri = data.toString()
		if (uri.isBlank()) return
		appContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE)
			.edit()
			.putString(KEY_PENDING_AUTH_CALLBACK, uri)
			.apply()
		Log.i(TAG, "captured auth callback")
		try {
			intent.data = null
		} catch (_: Exception) {
		}
	}

	@UsedByGodot
	fun peek_pending_deeplink(): String {
		return try {
			appContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE)
				.getString(KEY_PENDING_DEEPLINK, "") ?: ""
		} catch (_: Exception) {
			""
		}
	}

	@UsedByGodot
	fun consume_pending_deeplink(): String {
		return try {
			val prefs = appContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE)
			val link = prefs.getString(KEY_PENDING_DEEPLINK, "") ?: ""
			if (link.isNotEmpty()) {
				prefs.edit().remove(KEY_PENDING_DEEPLINK).apply()
			}
			link
		} catch (_: Exception) {
			""
		}
	}

	@UsedByGodot
	fun peek_pending_auth_callback(): String {
		return try {
			appContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE)
				.getString(KEY_PENDING_AUTH_CALLBACK, "") ?: ""
		} catch (_: Exception) {
			""
		}
	}

	@UsedByGodot
	fun consume_pending_auth_callback(): String {
		/**
		 * Compatibility name used by GDScript. Deliberately non-destructive:
		 * AuthService clears only after terminal processing, so a process/network
		 * interruption cannot lose a still-usable PKCE callback.
		 */
		return peek_pending_auth_callback()
	}

	@UsedByGodot
	fun clear_pending_auth_callback(): Boolean {
		return try {
			appContext().getSharedPreferences(PREFS, Context.MODE_PRIVATE)
				.edit()
				.remove(KEY_PENDING_AUTH_CALLBACK)
				.commit()
		} catch (_: Exception) {
			false
		}
	}

	/** Open OAuth/recovery URLs with Android's native browser intent. */
	@UsedByGodot
	fun open_external_auth_url(url: String): Boolean {
		return try {
			val trimmed = url.trim()
			if (trimmed.isEmpty()) return false
			val uri = Uri.parse(trimmed)
			val scheme = uri.scheme?.lowercase().orEmpty()
			if (scheme != "https" && scheme != "http") return false
			val act = getActivity() ?: return false
			val intent = Intent(Intent.ACTION_VIEW, uri).apply {
				addCategory(Intent.CATEGORY_BROWSABLE)
			}
			// Do not preflight with resolveActivity(): Android package-visibility rules
			// can hide browsers from queries even though ACTION_VIEW launches correctly.
			act.startActivity(intent)
			true
		} catch (e: Exception) {
			Log.w(TAG, "open_external_auth_url failed: ${e.javaClass.simpleName}")
			false
		}
	}

	@UsedByGodot
	fun open_app_notification_settings(): Boolean {
		return try {
			val act = getActivity() ?: return false
			val intent = if (Build.VERSION.SDK_INT >= 26) {
				Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
					putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, act.packageName)
				}
			} else {
				Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
					data = android.net.Uri.fromParts("package", act.packageName, null)
				}
			}
			intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
			act.startActivity(intent)
			true
		} catch (e: Exception) {
			Log.w(TAG, "open_app_notification_settings failed: ${e.javaClass.simpleName}")
			false
		}
	}

	@UsedByGodot
	fun has_notification_permission(): Boolean {
		return if (Build.VERSION.SDK_INT >= 33) {
			appContext().checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
				PackageManager.PERMISSION_GRANTED
		} else {
			val nm = appContext().getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
			nm.areNotificationsEnabled()
		}
	}

	@UsedByGodot
	fun request_notification_permission(): Boolean {
		return try {
			if (Build.VERSION.SDK_INT < 33) {
				Log.i(TAG, "notification permission not runtime-controlled on this API")
				return has_notification_permission()
			}
			if (has_notification_permission()) return true
			val act = getActivity() ?: run {
				Log.w(TAG, "request_notification_permission: activity null")
				return false
			}
			Log.i(TAG, "permission notifications requested")
			act.runOnUiThread {
				try {
					act.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 0xC0F2)
				} catch (e: Exception) {
					Log.w(TAG, "requestPermissions failed: ${e.javaClass.simpleName}")
				}
			}
			false
		} catch (e: Exception) {
			Log.w(TAG, "request_notification_permission failed: ${e.javaClass.simpleName}")
			false
		}
	}

	/**
	 * After a prior denial, true means Android may still show the dialog again.
	 * False + still denied usually means permanently denied / Don't ask again.
	 */
	@UsedByGodot
	fun can_request_permission(permission: String): Boolean {
		return try {
			val act = getActivity() ?: return true
			if (act.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
				return false
			}
			act.shouldShowRequestPermissionRationale(permission)
		} catch (_: Exception) {
			true
		}
	}

	@UsedByGodot
	fun open_app_settings(): Boolean {
		return try {
			val act = getActivity() ?: return false
			val intent = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
				data = android.net.Uri.fromParts("package", act.packageName, null)
				addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
			}
			act.startActivity(intent)
			true
		} catch (e: Exception) {
			Log.w(TAG, "open_app_settings failed: ${e.javaClass.simpleName}")
			false
		}
	}

	/** Resolve a monochrome-safe small icon; never fall back to the generic dialog icon when app assets exist. */
	fun resolveSmallIcon(ctx: Context): Int {
		val pkg = ctx.packageName
		val res = ctx.resources
		val candidates = intArrayOf(
			res.getIdentifier("ic_coln_notification", "drawable", pkg),
			res.getIdentifier("icon", "mipmap", pkg),
			res.getIdentifier("icon", "drawable", pkg),
			ctx.applicationInfo.icon,
		)
		for (id in candidates) {
			if (id != 0) return id
		}
		return android.R.drawable.stat_notify_chat
	}

	@UsedByGodot
	fun show_notification(channel: String, title: String, body: String, deepLink: String, notifId: Int): Boolean {
		return try {
			ensure_channels()
			if (!has_notification_permission()) {
				Log.i(TAG, "show_notification skipped: permission not granted")
				return false
			}
			val ctx = appContext()
			val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName) ?: Intent()
			launch.putExtra("coln_deeplink", deepLink)
			launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
			val pi = PendingIntent.getActivity(
				ctx,
				notifId,
				launch,
				PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
			)
			val ch = when (channel) {
				"new_scroll", "scheduled_ready", "scrolls", "ready", CH_SCROLLS, CH_READY -> CH_SCROLLS
				"activity", "focus", "challenges", CH_CHALLENGES -> CH_CHALLENGES
				"connection", "connections", "friend_request", CH_CONNECTIONS -> CH_CONNECTIONS
				else -> CH_SCROLLS
			}
			val builder = if (Build.VERSION.SDK_INT >= 26) {
				Notification.Builder(ctx, ch)
			} else {
				@Suppress("DEPRECATION")
				Notification.Builder(ctx)
			}
			val notif = builder
				.setSmallIcon(resolveSmallIcon(ctx))
				.setContentTitle(title)
				.setContentText(body)
				.setStyle(Notification.BigTextStyle().bigText(body))
				.setContentIntent(pi)
				.setAutoCancel(true)
				.build()
			val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
			nm.notify(notifId, notif)
			true
		} catch (e: Exception) {
			Log.w(TAG, "show_notification failed: ${e.javaClass.simpleName}")
			false
		}
	}

	@UsedByGodot
	fun cancel_notification(notifId: Int): Boolean {
		return try {
			ScheduledNotifyReceiver.cancelAlarm(appContext(), notifId)
			val nm = appContext().getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
			nm.cancel(notifId)
			true
		} catch (_: Exception) {
			false
		}
	}

	/**
	 * Schedule a local notification for a future time (epoch ms).
	 * Uses inexact AlarmManager — works while app is closed; no exact-alarm permission.
	 */
	@UsedByGodot
	fun schedule_notification(
		channel: String,
		title: String,
		body: String,
		deepLink: String,
		notifId: Int,
		triggerAtEpochMs: Long,
	): Boolean {
		return try {
			ensure_channels()
			if (triggerAtEpochMs <= System.currentTimeMillis() + 2000L) {
				return show_notification(channel, title, body, deepLink, notifId)
			}
			ScheduledNotifyReceiver.scheduleAlarm(
				appContext(),
				notifId,
				channel,
				title,
				body,
				deepLink,
				triggerAtEpochMs,
			)
			true
		} catch (e: Exception) {
			Log.w(TAG, "schedule_notification failed: ${e.javaClass.simpleName}")
			false
		}
	}

	@UsedByGodot
	fun cancel_scheduled_notification(notifId: Int): Boolean {
		return try {
			ScheduledNotifyReceiver.cancelAlarm(appContext(), notifId)
			true
		} catch (_: Exception) {
			false
		}
	}

	@UsedByGodot
	fun reschedule_persisted_notifications(): Boolean {
		return try {
			ScheduledNotifyReceiver.rescheduleAll(appContext())
			true
		} catch (e: Exception) {
			Log.w(TAG, "reschedule_persisted_notifications failed: ${e.javaClass.simpleName}")
			false
		}
	}

	/**
	 * Stub until an FCM/client push token API is wired.
	 * Empty string means registration should no-op.
	 */
	@UsedByGodot
	fun get_push_token(): String = ""
}
