package com.charoitegames.chestoflovenotes.securestorage

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicReference

/**
 * Location Lock one-shot / fresh-fix helper + Activity Lock foreground challenge control.
 */
class ChestLocationPlugin(godot: Godot) : GodotPlugin(godot) {

	companion object {
		private const val TAG = "ChestLocation"
		private const val PLUGIN_NAME = "ChestLocation"
	}

	private val freshFix = AtomicReference<Location?>(null)
	private var freshListening = false
	private var freshListener: LocationListener? = null
	private val mainHandler = Handler(Looper.getMainLooper())

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

	private fun encodeLocation(loc: Location): String {
		val accuracy = if (loc.hasAccuracy()) loc.accuracy else -1f
		return "ok|${loc.latitude}|${loc.longitude}|$accuracy"
	}

	@UsedByGodot
	fun get_last_known_location(): String {
		return try {
			if (!has_location_permission()) {
				return "error|Location permission is required.|denied"
			}
			val lm = appContext().getSystemService(Context.LOCATION_SERVICE) as LocationManager
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && !lm.isLocationEnabled) {
				return "error|Turn on Location Services to use your current location.|disabled"
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
				return "error|We couldn't determine your location. Try again.|unavailable"
			}
			encodeLocation(best)
		} catch (e: Exception) {
			Log.w(TAG, "get_last_known_location failed: ${e.javaClass.simpleName}")
			"error|We couldn't determine your location. Try again.|unavailable"
		}
	}

	/** Begin a short while-in-use location listen for Compose "Use Current Location". */
	@UsedByGodot
	fun begin_fresh_location(): Boolean {
		return try {
			if (!has_location_permission()) return false
			val lm = appContext().getSystemService(Context.LOCATION_SERVICE) as LocationManager
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && !lm.isLocationEnabled) {
				return false
			}
			stopFreshListen()
			freshFix.set(null)
			freshListening = true
			val listener = object : LocationListener {
				override fun onLocationChanged(location: Location) {
					val prev = freshFix.get()
					if (prev == null || location.accuracy <= prev.accuracy || location.time >= prev.time) {
						freshFix.set(location)
					}
				}
				@Deprecated("Deprecated in Java")
				override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
				override fun onProviderEnabled(provider: String) {}
				override fun onProviderDisabled(provider: String) {}
			}
			freshListener = listener
			for (provider in lm.getProviders(true)) {
				try {
					lm.requestLocationUpdates(provider, 500L, 0f, listener, Looper.getMainLooper())
				} catch (_: SecurityException) {
				}
			}
			mainHandler.postDelayed({ stopFreshListen() }, 12_000L)
			true
		} catch (e: Exception) {
			Log.w(TAG, "begin_fresh_location failed: ${e.javaClass.simpleName}")
			false
		}
	}

	/** Poll during begin_fresh_location window. */
	@UsedByGodot
	fun poll_fresh_location(): String {
		val loc = freshFix.get()
		if (loc != null) {
			stopFreshListen()
			return encodeLocation(loc)
		}
		if (!freshListening) {
			return get_last_known_location()
		}
		return "error|Still getting location…|pending"
	}

	@UsedByGodot
	fun cancel_fresh_location(): Boolean {
		stopFreshListen()
		return true
	}

	/** Blocking convenience used by older callers — prefer begin/poll from Godot. */
	@UsedByGodot
	fun request_fresh_location(): String {
		return try {
			if (!begin_fresh_location()) {
				return get_last_known_location().let {
					if (it.startsWith("ok|")) it
					else "error|Turn on Location Services to use your current location.|disabled"
				}
			}
			val deadline = System.currentTimeMillis() + 8_000L
			while (System.currentTimeMillis() < deadline) {
				val loc = freshFix.get()
				if (loc != null) {
					stopFreshListen()
					return encodeLocation(loc)
				}
				try {
					Thread.sleep(200L)
				} catch (_: InterruptedException) {
					break
				}
			}
			stopFreshListen()
			val last = get_last_known_location()
			if (last.startsWith("ok|")) last else "error|We couldn't determine your location. Try again.|timeout"
		} catch (e: Exception) {
			Log.w(TAG, "request_fresh_location failed: ${e.javaClass.simpleName}")
			"error|We couldn't determine your location. Try again.|unavailable"
		}
	}

	private fun stopFreshListen() {
		freshListening = false
		val listener = freshListener ?: return
		freshListener = null
		try {
			val lm = appContext().getSystemService(Context.LOCATION_SERVICE) as LocationManager
			lm.removeUpdates(listener)
		} catch (_: Exception) {
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
