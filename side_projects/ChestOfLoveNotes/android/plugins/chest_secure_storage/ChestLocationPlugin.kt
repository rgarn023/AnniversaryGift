package com.charoitegames.chestoflovenotes.securestorage

import android.Manifest
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import java.util.concurrent.atomic.AtomicReference

/**
 * Fused location for "Use Current Location" + Activity Lock + optional Location Lock geofences.
 * Prefer Play Services fused provider (GPS + Wi‑Fi/network) over raw GPS-only listens.
 */
class ChestLocationPlugin(godot: Godot) : GodotPlugin(godot) {

	companion object {
		private const val TAG = "ChestLocation"
		private const val PLUGIN_NAME = "ChestLocation"
		private const val FRESH_TIMEOUT_MS = 20_000L
		private const val ACCEPTABLE_CACHED_AGE_MS = 45_000L
		private const val GEOFENCE_REQ = 0xC0FE
	}

	private val freshFix = AtomicReference<Location?>(null)
	private var freshListening = false
	private var fusedCallback: LocationCallback? = null
	private val mainHandler = Handler(Looper.getMainLooper())
	private var timeoutRunnable: Runnable? = null

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
	fun has_background_location_permission(): Boolean {
		if (Build.VERSION.SDK_INT < 29) {
			return has_location_permission()
		}
		return appContext().checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION) ==
			PackageManager.PERMISSION_GRANTED
	}

	@UsedByGodot
	fun request_location_permission(): Boolean {
		return try {
			val act = getActivity() ?: return false
			if (has_location_permission()) return true
			act.requestPermissions(
				arrayOf(
					Manifest.permission.ACCESS_FINE_LOCATION,
					Manifest.permission.ACCESS_COARSE_LOCATION,
				),
				0xC011,
			)
			false
		} catch (e: Exception) {
			Log.w(TAG, "request_location_permission failed: ${e.javaClass.simpleName}")
			false
		}
	}

	@UsedByGodot
	fun request_background_location_permission(): Boolean {
		return try {
			if (Build.VERSION.SDK_INT < 29) return has_location_permission()
			val act = getActivity() ?: return false
			if (has_background_location_permission()) return true
			if (!has_location_permission()) {
				request_location_permission()
				return false
			}
			act.requestPermissions(
				arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
				0xC012,
			)
			false
		} catch (e: Exception) {
			Log.w(TAG, "request_background_location_permission failed: ${e.javaClass.simpleName}")
			false
		}
	}

	@UsedByGodot
	fun is_location_enabled(): Boolean {
		return try {
			val lm = appContext().getSystemService(Context.LOCATION_SERVICE) as LocationManager
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
				lm.isLocationEnabled
			} else {
				@Suppress("DEPRECATION")
				lm.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
					lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
			}
		} catch (_: Exception) {
			false
		}
	}

	private fun encodeLocation(loc: Location, source: String): String {
		val accuracy = if (loc.hasAccuracy()) loc.accuracy else -1f
		val ageMs = (System.currentTimeMillis() - loc.time).coerceAtLeast(0L)
		Log.i(
			TAG,
			"fix source=$source lat=${loc.latitude} lng=${loc.longitude} acc=$accuracy ageMs=$ageMs provider=${loc.provider}",
		)
		return "ok|${loc.latitude}|${loc.longitude}|$accuracy|$ageMs|$source"
	}

	@UsedByGodot
	fun location_diagnostics(): String {
		return try {
			val perm = has_location_permission()
			val enabled = is_location_enabled()
			val lm = appContext().getSystemService(Context.LOCATION_SERVICE) as LocationManager
			val providers = try {
				lm.getProviders(true).joinToString(",")
			} catch (_: Exception) {
				""
			}
			val last = peekBestLastKnown()
			val age = last?.let { (System.currentTimeMillis() - it.time).coerceAtLeast(0L) } ?: -1L
			val acc = last?.let { if (it.hasAccuracy()) it.accuracy else -1f } ?: -1f
			Log.i(
				TAG,
				"diag perm=$perm enabled=$enabled providers=$providers lastAge=$age lastAcc=$acc listening=$freshListening",
			)
			"perm=$perm|enabled=$enabled|providers=$providers|lastAgeMs=$age|lastAcc=$acc|listening=$freshListening"
		} catch (e: Exception) {
			"error|${e.javaClass.simpleName}"
		}
	}

	@SuppressLint("MissingPermission")
	private fun peekBestLastKnown(): Location? {
		if (!has_location_permission()) return null
		var best: Location? = null
		try {
			val fused = LocationServices.getFusedLocationProviderClient(appContext())
			// getLastLocation is async; also probe LocationManager synchronically for diagnostics/fallback.
		} catch (_: Exception) {
		}
		try {
			val lm = appContext().getSystemService(Context.LOCATION_SERVICE) as LocationManager
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
		} catch (_: Exception) {
		}
		return best
	}

	@UsedByGodot
	fun get_last_known_location(): String {
		return try {
			if (!has_location_permission()) {
				Log.i(TAG, "get_last_known denied")
				return "error|Allow Location permission to use your current location.|denied"
			}
			if (!is_location_enabled()) {
				Log.i(TAG, "get_last_known services disabled")
				return "error|Turn on Location Services to use your current location.|disabled"
			}
			val best = peekBestLastKnown()
			if (best == null) {
				Log.i(TAG, "get_last_known unavailable")
				return "error|We couldn't determine your location. Try again.|unavailable"
			}
			encodeLocation(best, "last_known")
		} catch (e: Exception) {
			Log.w(TAG, "get_last_known_location failed: ${e.javaClass.simpleName}")
			"error|We couldn't determine your location. Try again.|unavailable"
		}
	}

	/** Begin fused high-accuracy listen for Compose "Use Current Location". */
	@SuppressLint("MissingPermission")
	@UsedByGodot
	fun begin_fresh_location(): Boolean {
		return try {
			Log.i(TAG, "begin_fresh_location perm=${has_location_permission()} enabled=${is_location_enabled()}")
			if (!has_location_permission()) return false
			if (!is_location_enabled()) return false
			stopFreshListen()
			freshFix.set(null)
			freshListening = true
			val client = LocationServices.getFusedLocationProviderClient(appContext())

			// Prefer a recent fused last-location immediately when fresh enough.
			client.lastLocation
				.addOnSuccessListener { loc ->
					if (loc == null) return@addOnSuccessListener
					val age = System.currentTimeMillis() - loc.time
					Log.i(TAG, "fused lastLocation ageMs=$age acc=${if (loc.hasAccuracy()) loc.accuracy else -1f}")
					if (age in 0..ACCEPTABLE_CACHED_AGE_MS) {
						freshFix.compareAndSet(null, loc)
					}
				}
				.addOnFailureListener { e ->
					Log.w(TAG, "fused lastLocation failed: ${e.javaClass.simpleName}")
				}

			val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 1000L)
				.setMinUpdateIntervalMillis(500L)
				.setMaxUpdates(8)
				.setWaitForAccurateLocation(false)
				.build()
			val callback = object : LocationCallback() {
				override fun onLocationResult(result: LocationResult) {
					val location = result.lastLocation ?: return
					val prev = freshFix.get()
					if (
						prev == null ||
						(location.hasAccuracy() && prev.hasAccuracy() && location.accuracy < prev.accuracy) ||
						location.time >= prev.time
					) {
						freshFix.set(location)
						Log.i(TAG, "fused callback acc=${if (location.hasAccuracy()) location.accuracy else -1f}")
					}
				}
			}
			fusedCallback = callback
			client.requestLocationUpdates(request, callback, Looper.getMainLooper())
			val timeout = Runnable {
				Log.i(TAG, "fresh location timeout")
				stopFreshListen()
			}
			timeoutRunnable = timeout
			mainHandler.postDelayed(timeout, FRESH_TIMEOUT_MS)
			true
		} catch (e: Exception) {
			Log.w(TAG, "begin_fresh_location failed: ${e.javaClass.simpleName}: ${e.message}")
			freshListening = false
			false
		}
	}

	@UsedByGodot
	fun poll_fresh_location(): String {
		val loc = freshFix.get()
		if (loc != null) {
			stopFreshListen()
			return encodeLocation(loc, "fused")
		}
		if (!freshListening) {
			Log.i(TAG, "poll_fresh timeout/no fix")
			return "error|We couldn't determine your location. Try again.|timeout"
		}
		return "error|Still getting location…|pending"
	}

	@UsedByGodot
	fun cancel_fresh_location(): Boolean {
		stopFreshListen()
		return true
	}

	@UsedByGodot
	fun request_fresh_location(): String {
		return try {
			if (!begin_fresh_location()) {
				return when {
					!has_location_permission() ->
						"error|Allow Location permission to use your current location.|denied"
					!is_location_enabled() ->
						"error|Turn on Location Services to use your current location.|disabled"
					else -> "error|We couldn't determine your location. Try again.|unavailable"
				}
			}
			val deadline = System.currentTimeMillis() + FRESH_TIMEOUT_MS
			while (System.currentTimeMillis() < deadline) {
				val loc = freshFix.get()
				if (loc != null) {
					stopFreshListen()
					return encodeLocation(loc, "fused")
				}
				try {
					Thread.sleep(200L)
				} catch (_: InterruptedException) {
					break
				}
			}
			stopFreshListen()
			val last = get_last_known_location()
			if (last.startsWith("ok|")) {
				val parts = last.split("|")
				val age = if (parts.size >= 5) parts[4].toLongOrNull() ?: Long.MAX_VALUE else Long.MAX_VALUE
				if (age <= ACCEPTABLE_CACHED_AGE_MS) last
				else "error|We couldn't determine your location. Try again.|timeout"
			} else {
				"error|We couldn't determine your location. Try again.|timeout"
			}
		} catch (e: Exception) {
			Log.w(TAG, "request_fresh_location failed: ${e.javaClass.simpleName}")
			"error|We couldn't determine your location. Try again.|unavailable"
		}
	}

	private fun stopFreshListen() {
		freshListening = false
		timeoutRunnable?.let { mainHandler.removeCallbacks(it) }
		timeoutRunnable = null
		val callback = fusedCallback
		fusedCallback = null
		if (callback != null) {
			try {
				LocationServices.getFusedLocationProviderClient(appContext())
					.removeLocationUpdates(callback)
			} catch (_: Exception) {
			}
		}
	}

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

	/** Opt-in geofence for "Notify me when I'm close enough". */
	@SuppressLint("MissingPermission")
	@UsedByGodot
	fun register_scroll_geofence(scrollId: String, lat: Double, lng: Double, radiusM: Float): Boolean {
		return try {
			if (scrollId.isBlank() || radiusM <= 0f) return false
			if (!has_location_permission()) return false
			if (Build.VERSION.SDK_INT >= 29 && !has_background_location_permission()) {
				Log.i(TAG, "register_scroll_geofence needs background location")
				return false
			}
			val ctx = appContext()
			val client: GeofencingClient = LocationServices.getGeofencingClient(ctx)
			val id = "coln_geo_$scrollId"
			val fence = Geofence.Builder()
				.setRequestId(id)
				.setCircularRegion(lat, lng, radiusM.coerceIn(25f, 10000f))
				.setExpirationDuration(Geofence.NEVER_EXPIRE)
				.setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_DWELL)
				.setLoiteringDelay(30_000)
				.build()
			val request = GeofencingRequest.Builder()
				.setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER or GeofencingRequest.INITIAL_TRIGGER_DWELL)
				.addGeofence(fence)
				.build()
			val intent = Intent(ctx, GeofenceReceiver::class.java).apply {
				action = GeofenceReceiver.ACTION_TRANSITION
				putExtra(GeofenceReceiver.EXTRA_SCROLL_ID, scrollId)
			}
			val pi = PendingIntent.getBroadcast(
				ctx,
				GEOFENCE_REQ xor scrollId.hashCode(),
				intent,
				PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
			)
			client.addGeofences(request, pi)
			GeofenceReceiver.persistFence(ctx, scrollId, lat, lng, radiusM)
			Log.i(TAG, "geofence registered scroll=$scrollId r=$radiusM")
			true
		} catch (e: Exception) {
			Log.w(TAG, "register_scroll_geofence failed: ${e.javaClass.simpleName}: ${e.message}")
			false
		}
	}

	@UsedByGodot
	fun remove_scroll_geofence(scrollId: String): Boolean {
		return try {
			if (scrollId.isBlank()) return false
			val ctx = appContext()
			val client = LocationServices.getGeofencingClient(ctx)
			val id = "coln_geo_$scrollId"
			client.removeGeofences(listOf(id))
			GeofenceReceiver.removeFence(ctx, scrollId)
			Log.i(TAG, "geofence removed scroll=$scrollId")
			true
		} catch (e: Exception) {
			Log.w(TAG, "remove_scroll_geofence failed: ${e.javaClass.simpleName}")
			false
		}
	}

	@UsedByGodot
	fun clear_all_geofences(): Boolean {
		return try {
			val ctx = appContext()
			val ids = GeofenceReceiver.allFenceIds(ctx)
			if (ids.isNotEmpty()) {
				LocationServices.getGeofencingClient(ctx).removeGeofences(ids)
			}
			GeofenceReceiver.clearAll(ctx)
			true
		} catch (_: Exception) {
			false
		}
	}
}
