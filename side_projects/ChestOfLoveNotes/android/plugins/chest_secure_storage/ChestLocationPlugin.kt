package com.charoitegames.chestoflovenotes.securestorage

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.util.Log
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONObject

/**
 * Location Lock one-shot helper + Activity Lock foreground challenge control.
 */
class ChestLocationPlugin(godot: Godot) : GodotPlugin(godot) {

	companion object {
		private const val TAG = "ChestLocation"
		private const val PLUGIN_NAME = "ChestLocation"
	}

	override fun getPluginName(): String = PLUGIN_NAME

	private fun appContext(): Context {
		val ctx = godot.context ?: error("Godot context unavailable")
		return ctx.applicationContext
	}

	@UsedByGodot
	fun location_plugin_available(): Boolean = true

	@UsedByGodot
	fun has_location_permission(): Boolean {
		val ctx = appContext()
		val fine = ctx.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
			PackageManager.PERMISSION_GRANTED
		val coarse = ctx.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
			PackageManager.PERMISSION_GRANTED
		return fine || coarse
	}

	@UsedByGodot
	fun get_last_known_location(): String {
		return try {
			if (!has_location_permission()) {
				return "error|Location permission is required.|denied"
			}
			val lm = appContext().getSystemService(Context.LOCATION_SERVICE) as LocationManager
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && !lm.isLocationEnabled) {
				return "error|Turn on location services and try again.|disabled"
			}
			var best: Location? = null
			for (provider in lm.getProviders(true)) {
				val loc = try {
					lm.getLastKnownLocation(provider)
				} catch (_: SecurityException) {
					null
				} ?: continue
				if (best == null || loc.time > best.time) {
					best = loc
				}
			}
			if (best == null) {
				return "error|Location is temporarily unavailable.|unavailable"
			}
			val accuracy = if (best.hasAccuracy()) best.accuracy else -1f
			"ok|${best.latitude}|${best.longitude}|$accuracy"
		} catch (e: Exception) {
			Log.w(TAG, "get_last_known_location failed: ${e.javaClass.simpleName}")
			"error|Location is temporarily unavailable.|unavailable"
		}
	}

	/**
	 * Start foreground Activity Lock tracking. Requires while-in-use location permission.
	 * Does not request "Allow all the time".
	 */
	@UsedByGodot
	fun start_activity_tracking(scrollId: String, targetKm: Double, startLat: Double, startLng: Double): Boolean {
		return try {
			if (!has_location_permission()) return false
			val ctx = appContext()
			val intent = Intent(ctx, ActivityLockService::class.java).apply {
				action = ActivityLockService.ACTION_START
				putExtra(ActivityLockService.EXTRA_SCROLL_ID, scrollId)
				putExtra(ActivityLockService.EXTRA_TARGET_KM, targetKm)
				putExtra(ActivityLockService.EXTRA_START_LAT, startLat)
				putExtra(ActivityLockService.EXTRA_START_LNG, startLng)
			}
			if (Build.VERSION.SDK_INT >= 26) {
				ctx.startForegroundService(intent)
			} else {
				ctx.startService(intent)
			}
			true
		} catch (e: Exception) {
			Log.w(TAG, "start_activity_tracking failed: ${e.javaClass.simpleName}")
			false
		}
	}

	@UsedByGodot
	fun stop_activity_tracking(): Boolean {
		return try {
			val ctx = appContext()
			val intent = Intent(ctx, ActivityLockService::class.java).apply {
				action = ActivityLockService.ACTION_STOP
			}
			ctx.startService(intent)
			true
		} catch (e: Exception) {
			Log.w(TAG, "stop_activity_tracking failed: ${e.javaClass.simpleName}")
			false
		}
	}

	/** Returns JSON snapshot of native Activity Lock service state (or "{}"). */
	@UsedByGodot
	fun activity_tracking_snapshot(): String {
		return try {
			val st = ActivityLockService.readState(appContext()) ?: return "{}"
			st.toString()
		} catch (_: Exception) {
			"{}"
		}
	}

	@UsedByGodot
	fun clear_activity_tracking_state(): Boolean {
		return try {
			stop_activity_tracking()
			ActivityLockService.clearState(appContext())
			true
		} catch (_: Exception) {
			false
		}
	}
}
