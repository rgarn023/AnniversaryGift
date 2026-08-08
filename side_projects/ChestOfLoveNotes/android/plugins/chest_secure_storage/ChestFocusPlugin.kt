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
 * Focus Lock helper — Usage Access only to detect interactive usage since a timestamp.
 * Does not return or store per-app usage history.
 */
class ChestFocusPlugin(godot: Godot) : GodotPlugin(godot) {

	companion object {
		private const val TAG = "ChestFocus"
		private const val PLUGIN_NAME = "ChestFocus"
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
	 * Returns true if qualifying interactive usage occurred after sinceEpochMs.
	 * Does not expose which apps were used.
	 */
	@UsedByGodot
	fun had_interactive_usage_since(sinceEpochMs: Long): Boolean {
		// Fail closed when access missing — caller should check has_usage_access first.
		if (!has_usage_access()) return true
		return try {
			val usm = appContext().getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
			val end = System.currentTimeMillis()
			val begin = sinceEpochMs.coerceAtMost(end)
			val events = usm.queryEvents(begin, end)
			val event = UsageEvents.Event()
			var saw = false
			while (events.hasNextEvent()) {
				events.getNextEvent(event)
				val type = event.eventType
				val interactive = type == UsageEvents.Event.ACTIVITY_RESUMED ||
					type == 1 // MOVE_TO_FOREGROUND legacy constant
				if (interactive && event.packageName != appContext().packageName) {
					saw = true
					break
				}
			}
			saw
		} catch (e: Exception) {
			Log.w(TAG, "had_interactive_usage_since failed: ${e.javaClass.simpleName}")
			true
		}
	}
}
