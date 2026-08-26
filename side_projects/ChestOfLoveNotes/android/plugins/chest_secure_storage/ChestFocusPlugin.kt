package com.charoitegames.chestoflovenotes.securestorage

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Process
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Focus Lock helper — Usage Access only to detect genuine interactive phone use.
 *
 * Must NOT interrupt for: notifications, notification-driven screen wake, background
 * sync/services, music, system services, alarms merely firing, unanswered calls,
 * lock-screen glances, or this app's own notifications/activity.
 *
 * SHOULD interrupt for: unlock + active use, opening/switching apps, tapping a
 * notification into an app, answering/placing calls.
 *
 * Does not return or store per-app usage history.
 */
class ChestFocusPlugin(godot: Godot) : GodotPlugin(godot) {

	companion object {
		private const val TAG = "ChestFocus"
		private const val PLUGIN_NAME = "ChestFocus"

		private const val TYPE_MOVE_TO_FOREGROUND = 1
		private const val TYPE_MOVE_TO_BACKGROUND = 2
		private const val TYPE_CONFIGURATION_CHANGE = 5
		private const val TYPE_USER_INTERACTION = 7
		private const val TYPE_NOTIFICATION_SEEN = 10
		private const val TYPE_STANDBY_BUCKET_CHANGED = 11
		private const val TYPE_NOTIFICATION_INTERRUPTION = 12
		private const val TYPE_SCREEN_INTERACTIVE = 15
		private const val TYPE_SCREEN_NON_INTERACTIVE = 16
		private const val TYPE_KEYGUARD_SHOWN = 17
		private const val TYPE_KEYGUARD_HIDDEN = 18
		private const val TYPE_FOREGROUND_SERVICE_START = 19
		private const val TYPE_FOREGROUND_SERVICE_STOP = 20
		private const val TYPE_ACTIVITY_RESUMED = 23
		private const val TYPE_ACTIVITY_PAUSED = 24
		private const val TYPE_ACTIVITY_STOPPED = 25
		private const val TYPE_DEVICE_SHUTDOWN = 26
		private const val TYPE_DEVICE_STARTUP = 27

		/** Shells that must never count as interactive app use by themselves. */
		private val NEVER_COUNT_PACKAGES = setOf(
			"android",
			"com.android.systemui",
			"com.android.keyguard",
		)

		/**
		 * Incoming-call / dialer UI — ringing while locked must not reset Focus.
		 * After unlock (answered / placing a call) these DO count.
		 */
		private val CALL_UI_PACKAGES = setOf(
			"com.android.phone",
			"com.android.server.telecom",
			"com.samsung.android.incallui",
			"com.google.android.dialer",
			"com.samsung.android.dialer",
		)

		/**
		 * Alarm / clock UI — merely firing (screen wake + alarm activity) must not
		 * reset Focus. Dismissing/snoozing via USER_INTERACTION still counts.
		 */
		private val ALARM_UI_PACKAGES = setOf(
			"com.android.deskclock",
			"com.google.android.deskclock",
			"com.sec.android.app.clockpackage",
			"com.samsung.android.app.clockpackage",
		)
	}

	override fun getPluginName(): String = PLUGIN_NAME

	private fun appContext(): Context {
		val ctx = godot.context ?: error("Godot context unavailable")
		return ctx.applicationContext
	}

	@UsedByGodot
	fun focus_plugin_available(): Boolean = true

	@UsedByGodot
	fun boot_elapsed_realtime(): String = SystemClock.elapsedRealtime().toString()

	@UsedByGodot
	fun has_usage_access(): Boolean {
		return try {
			val ctx = appContext()
			val appOps = ctx.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
			val mode = if (Build.VERSION.SDK_INT >= 29) {
				appOps.unsafeCheckOpNoThrow(
					AppOpsManager.OPSTR_GET_USAGE_STATS,
					Process.myUid(),
					ctx.packageName,
				)
			} else {
				@Suppress("DEPRECATION")
				appOps.checkOpNoThrow(
					AppOpsManager.OPSTR_GET_USAGE_STATS,
					Process.myUid(),
					ctx.packageName,
				)
			}
			mode == AppOpsManager.MODE_ALLOWED
		} catch (e: Exception) {
			Log.w(TAG, "has_usage_access failed: ${e.javaClass.simpleName}")
			false
		}
	}

	@UsedByGodot
	fun open_usage_access_settings(): Boolean {
		return try {
			val act = getActivity() ?: return false
			val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
			intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
			act.startActivity(intent)
			true
		} catch (e: Exception) {
			Log.w(TAG, "open_usage_access_settings failed: ${e.javaClass.simpleName}")
			false
		}
	}

	/**
	 * Returns true only for genuine user-initiated interactive phone use after sinceEpochMs.
	 * Does not expose which apps were used.
	 */
	@UsedByGodot
	fun had_interactive_usage_since(sinceEpochMs: Long): Boolean {
		if (!has_usage_access()) return true
		return try {
			val usm = appContext().getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
			val end = System.currentTimeMillis()
			val begin = sinceEpochMs.coerceAtMost(end)
			val events = usm.queryEvents(begin, end)
			val event = UsageEvents.Event()
			val records = ArrayList<Triple<Int, String, Long>>()
			while (events.hasNextEvent()) {
				events.getNextEvent(event)
				records.add(Triple(event.eventType, event.packageName ?: "", event.timeStamp))
			}
			classifyInteractiveUsage(records, appContext().packageName)
		} catch (e: Exception) {
			Log.w(TAG, "had_interactive_usage_since failed: ${e.javaClass.simpleName}")
			true
		}
	}

	/**
	 * Pure classifier — mirrored in FocusLockHelper for headless tests.
	 * records: (eventType, packageName, timestampMs)
	 */
	internal fun classifyInteractiveUsage(
		records: List<Triple<Int, String, Long>>,
		selfPackage: String,
	): Boolean {
		var sawKeyguardShown = false
		var unlocked = false

		for ((type, pkg, _) in records) {
			// Chest of Love Notes must never sabotage its own Focus Lock.
			if (pkg.isNotEmpty() && pkg == selfPackage) {
				continue
			}

			when (type) {
				TYPE_KEYGUARD_SHOWN -> {
					sawKeyguardShown = true
					unlocked = false
				}
				TYPE_KEYGUARD_HIDDEN -> {
					unlocked = true
				}
				TYPE_USER_INTERACTION -> {
					// Lock-screen glance/time check: interaction while still locked → ignore.
					if (unlocked || !sawKeyguardShown) {
						return true
					}
				}
				TYPE_ACTIVITY_RESUMED, TYPE_MOVE_TO_FOREGROUND -> {
					if (pkg.isEmpty() || NEVER_COUNT_PACKAGES.contains(pkg)) {
						continue
					}
					// Alarm merely firing must not count as interactive app use.
					if (ALARM_UI_PACKAGES.contains(pkg)) {
						continue
					}
					// Unanswered incoming call UI while locked.
					if (CALL_UI_PACKAGES.contains(pkg) && !unlocked) {
						continue
					}
					// Unlock then use / answer/place call / open app.
					if (unlocked) {
						return true
					}
					// Already unlocked (no keyguard shown in window): app switch = real use.
					if (!sawKeyguardShown) {
						return true
					}
					// Keyguard still showing: shade / notif / lock UI — ignore.
				}
				TYPE_NOTIFICATION_INTERRUPTION,
				TYPE_NOTIFICATION_SEEN,
				TYPE_SCREEN_INTERACTIVE,
				TYPE_SCREEN_NON_INTERACTIVE,
				TYPE_FOREGROUND_SERVICE_START,
				TYPE_FOREGROUND_SERVICE_STOP,
				TYPE_STANDBY_BUCKET_CHANGED,
				TYPE_CONFIGURATION_CHANGE,
				TYPE_DEVICE_SHUTDOWN,
				TYPE_DEVICE_STARTUP,
				TYPE_ACTIVITY_PAUSED,
				TYPE_ACTIVITY_STOPPED,
				TYPE_MOVE_TO_BACKGROUND,
				-> {
					// Passively ignored.
				}
				else -> {
					// Unknown event types are not treated as interactive.
				}
			}
		}
		return false
	}
}
