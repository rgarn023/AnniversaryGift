package com.charoitegames.chestoflovenotes.securestorage

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * Delivers scheduled-ready notifications and re-registers them after reboot.
 * Uses inexact AlarmManager timing — no SCHEDULE_EXACT_ALARM permission.
 */
class ScheduledNotifyReceiver : BroadcastReceiver() {

	companion object {
		private const val TAG = "ChestSchedNotify"
		const val ACTION_FIRE = "coln.notify.FIRE"
		const val ACTION_BOOT = Intent.ACTION_BOOT_COMPLETED
		const val PREFS = "coln_scheduled_notify"
		const val KEY_ITEMS = "items_json"
		/** Stable channel — must match ChestNotifyPlugin.CH_SCROLLS (not a one-off id). */
		const val CH_READY = ChestNotifyPlugin.CH_SCROLLS

		fun persistItem(
			ctx: Context,
			notifId: Int,
			channel: String,
			title: String,
			body: String,
			deepLink: String,
			triggerAtMs: Long,
		) {
			val arr = loadItems(ctx)
			// Replace same id
			val next = JSONArray()
			for (i in 0 until arr.length()) {
				val o = arr.getJSONObject(i)
				if (o.optInt("id") != notifId) next.put(o)
			}
			next.put(
				JSONObject()
					.put("id", notifId)
					.put("channel", channel)
					.put("title", title)
					.put("body", body)
					.put("deep_link", deepLink)
					.put("trigger_at_ms", triggerAtMs),
			)
			ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
				.edit().putString(KEY_ITEMS, next.toString()).apply()
		}

		fun removeItem(ctx: Context, notifId: Int) {
			val arr = loadItems(ctx)
			val next = JSONArray()
			for (i in 0 until arr.length()) {
				val o = arr.getJSONObject(i)
				if (o.optInt("id") != notifId) next.put(o)
			}
			ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
				.edit().putString(KEY_ITEMS, next.toString()).apply()
		}

		fun loadItems(ctx: Context): JSONArray {
			return try {
				val raw = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_ITEMS, "[]")
				JSONArray(raw ?: "[]")
			} catch (_: Exception) {
				JSONArray()
			}
		}

		fun scheduleAlarm(
			ctx: Context,
			notifId: Int,
			channel: String,
			title: String,
			body: String,
			deepLink: String,
			triggerAtMs: Long,
		) {
			persistItem(ctx, notifId, channel, title, body, deepLink, triggerAtMs)
			val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
			val intent = Intent(ctx, ScheduledNotifyReceiver::class.java).apply {
				action = ACTION_FIRE
				putExtra("id", notifId)
				putExtra("channel", channel)
				putExtra("title", title)
				putExtra("body", body)
				putExtra("deep_link", deepLink)
			}
			val pi = PendingIntent.getBroadcast(
				ctx,
				notifId,
				intent,
				PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
			)
			val whenMs = triggerAtMs.coerceAtLeast(System.currentTimeMillis() + 1500L)
			// Inexact / allow-while-idle — near-time is acceptable; no exact-alarm permission.
			if (Build.VERSION.SDK_INT >= 23) {
				am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, whenMs, pi)
			} else {
				@Suppress("DEPRECATION")
				am.set(AlarmManager.RTC_WAKEUP, whenMs, pi)
			}
		}

		fun cancelAlarm(ctx: Context, notifId: Int) {
			removeItem(ctx, notifId)
			val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
			val intent = Intent(ctx, ScheduledNotifyReceiver::class.java).apply { action = ACTION_FIRE }
			val pi = PendingIntent.getBroadcast(
				ctx,
				notifId,
				intent,
				PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
			)
			am.cancel(pi)
			val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
			nm.cancel(notifId)
		}

		fun rescheduleAll(ctx: Context) {
			val arr = loadItems(ctx)
			val now = System.currentTimeMillis()
			for (i in 0 until arr.length()) {
				val o = arr.getJSONObject(i)
				val at = o.optLong("trigger_at_ms", 0L)
				val id = o.optInt("id")
				if (at <= now + 500L) {
					fireNow(
						ctx,
						id,
						o.optString("channel", "scheduled_ready"),
						o.optString("title", "Scroll ready"),
						o.optString("body", "A scroll is now available to open."),
						o.optString("deep_link", "chest"),
					)
					removeItem(ctx, id)
				} else {
					scheduleAlarm(
						ctx,
						id,
						o.optString("channel", "scheduled_ready"),
						o.optString("title", "Scroll ready"),
						o.optString("body", "A scroll is now available to open."),
						o.optString("deep_link", "chest"),
						at,
					)
				}
			}
		}

		fun fireNow(
			ctx: Context,
			notifId: Int,
			channel: String,
			title: String,
			body: String,
			deepLink: String,
		) {
			try {
				if (Build.VERSION.SDK_INT >= 33) {
					val granted = ctx.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
						android.content.pm.PackageManager.PERMISSION_GRANTED
					if (!granted) {
						Log.i(TAG, "fireNow skipped: POST_NOTIFICATIONS not granted")
						return
					}
				} else {
					val nmCheck = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
					if (!nmCheck.areNotificationsEnabled()) {
						Log.i(TAG, "fireNow skipped: notifications disabled")
						return
					}
				}
				if (Build.VERSION.SDK_INT >= 26) {
					val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
					nm.createNotificationChannel(
						NotificationChannel(CH_READY, "Scrolls", NotificationManager.IMPORTANCE_DEFAULT),
					)
					nm.createNotificationChannel(
						NotificationChannel(ChestNotifyPlugin.CH_CHALLENGES, "Challenges", NotificationManager.IMPORTANCE_DEFAULT),
					)
					nm.createNotificationChannel(
						NotificationChannel(ChestNotifyPlugin.CH_CONNECTIONS, "Connections", NotificationManager.IMPORTANCE_DEFAULT),
					)
				}
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
					"activity", "focus", "challenges", ChestNotifyPlugin.CH_CHALLENGES -> ChestNotifyPlugin.CH_CHALLENGES
					"connection", "connections", "friend_request", ChestNotifyPlugin.CH_CONNECTIONS -> ChestNotifyPlugin.CH_CONNECTIONS
					else -> CH_READY
				}
				val builder = if (Build.VERSION.SDK_INT >= 26) {
					Notification.Builder(ctx, ch)
				} else {
					@Suppress("DEPRECATION")
					Notification.Builder(ctx)
				}
				val iconRes = resolveSmallIcon(ctx)
				val notif = builder
					.setSmallIcon(iconRes)
					.setContentTitle(title)
					.setContentText(body)
					.setStyle(Notification.BigTextStyle().bigText(body))
					.setContentIntent(pi)
					.setAutoCancel(true)
					.build()
				val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
				nm.notify(notifId, notif)
			} catch (e: Exception) {
				Log.w(TAG, "fireNow failed: ${e.javaClass.simpleName}")
			}
		}

		private fun resolveSmallIcon(ctx: Context): Int {
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
	}

	override fun onReceive(context: Context, intent: Intent?) {
		val action = intent?.action ?: return
		when (action) {
			ACTION_BOOT, Intent.ACTION_LOCKED_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> {
				rescheduleAll(context.applicationContext)
			}
			ACTION_FIRE -> {
				val id = intent.getIntExtra("id", 0)
				fireNow(
					context.applicationContext,
					id,
					intent.getStringExtra("channel") ?: "scheduled_ready",
					intent.getStringExtra("title") ?: "Scroll ready",
					intent.getStringExtra("body") ?: "A scroll is now available to open.",
					intent.getStringExtra("deep_link") ?: "chest",
				)
				removeItem(context.applicationContext, id)
			}
		}
	}
}
