package com.charoitegames.chestoflovenotes.securestorage

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
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
		const val CH_NEW = "coln_new_scroll"
		const val CH_READY = "coln_scheduled_ready"
		const val CH_ACTIVITY = "coln_activity"
		const val CH_FOCUS = "coln_focus"
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
				nm.createNotificationChannel(NotificationChannel(CH_NEW, "New Scroll", NotificationManager.IMPORTANCE_DEFAULT))
				nm.createNotificationChannel(NotificationChannel(CH_READY, "Scroll Ready", NotificationManager.IMPORTANCE_DEFAULT))
				nm.createNotificationChannel(NotificationChannel(CH_ACTIVITY, "Activity Lock", NotificationManager.IMPORTANCE_LOW))
				nm.createNotificationChannel(NotificationChannel(CH_FOCUS, "Focus Lock", NotificationManager.IMPORTANCE_DEFAULT))
			}
			true
		} catch (e: Exception) {
			Log.w(TAG, "ensure_channels failed: ${e.javaClass.simpleName}")
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
			if (Build.VERSION.SDK_INT >= 33) {
				val act = getActivity() ?: return false
				act.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 0xC0F2)
			}
			true
		} catch (e: Exception) {
			Log.w(TAG, "request_notification_permission failed: ${e.javaClass.simpleName}")
			false
		}
	}

	@UsedByGodot
	fun show_notification(channel: String, title: String, body: String, deepLink: String, notifId: Int): Boolean {
		return try {
			ensure_channels()
			if (!has_notification_permission() && Build.VERSION.SDK_INT >= 33) {
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
				"new_scroll" -> CH_NEW
				"scheduled_ready" -> CH_READY
				"activity" -> CH_ACTIVITY
				"focus" -> CH_FOCUS
				else -> CH_NEW
			}
			val builder = if (Build.VERSION.SDK_INT >= 26) {
				Notification.Builder(ctx, ch)
			} else {
				@Suppress("DEPRECATION")
				Notification.Builder(ctx)
			}
			val notif = builder
				.setSmallIcon(android.R.drawable.ic_dialog_info)
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
}
