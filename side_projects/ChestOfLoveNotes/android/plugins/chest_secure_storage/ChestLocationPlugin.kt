package com.charoitegames.chestoflovenotes.securestorage

import android.Manifest
import android.annotation.SuppressLint
import android.app.PendingIntent
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
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/**
 * Fused + network/GPS current location for Compose "Use Current Location".
 * Fully async — never blocks the Godot/UI thread with a blocking Task wait (that hung Galaxy requests).
 *
 * Success = valid lat/lng. Reverse geocode is GDScript display polish only.
 */
class ChestLocationPlugin(godot: Godot) : GodotPlugin(godot) {

	companion object {
		private const val TAG = "ChestLocation"
		private const val PLUGIN_NAME = "ChestLocation"
		private const val FRESH_TIMEOUT_MS = 45_000L
		private const val ACCEPTABLE_CACHED_AGE_MS = 180_000L
		private const val GEOFENCE_REQ = 0xC0FE
	}

	private val freshFix = AtomicReference<Location?>(null)
	private val fixAccepted = AtomicBoolean(false)
	private val requestGen = AtomicInteger(0)
	private var activeRequestId = 0
	private var freshListening = false
	private var providerInitialized = false
	private var fusedCallback: LocationCallback? = null
	private var lmListeners: MutableList<Pair<LocationManager, LocationListener>> = mutableListOf()
	private var currentLocationCts: CancellationTokenSource? = null
	private val mainHandler = Handler(Looper.getMainLooper())
	private var timeoutRunnable: Runnable? = null

	override fun getPluginName(): String = PLUGIN_NAME

	private fun appContext(): Context {
		val ctx = godot.context ?: error("Godot context unavailable")
		return ctx.applicationContext
	}

	private fun logStage(msg: String) {
		Log.i(TAG, msg)
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
	fun has_fine_location_permission(): Boolean {
		return appContext().checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
			PackageManager.PERMISSION_GRANTED
	}

	@UsedByGodot
	fun has_coarse_location_permission(): Boolean {
		return appContext().checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
			PackageManager.PERMISSION_GRANTED
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
			if (has_location_permission()) return true
			val act = getActivity() ?: run {
				Log.w(TAG, "request_location_permission: activity null")
				return false
			}
			act.runOnUiThread {
				try {
					act.requestPermissions(
						arrayOf(
							Manifest.permission.ACCESS_FINE_LOCATION,
							Manifest.permission.ACCESS_COARSE_LOCATION,
						),
						0xC011,
					)
				} catch (e: Exception) {
					Log.w(TAG, "requestPermissions failed: ${e.javaClass.simpleName}")
				}
			}
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
		return "ok|${loc.latitude}|${loc.longitude}|$accuracy|$ageMs|$source|${activeRequestId}"
	}

	private fun considerFix(loc: Location?, source: String, requestId: Int): Boolean {
		if (requestId != activeRequestId) {
			logStage("rejection_reason=stale_request id=$requestId active=$activeRequestId")
			return false
		}
		if (loc == null) {
			logStage("callback_received source=$source null")
			return false
		}
		logStage("callback_received source=$source")
		val latOk = loc.latitude.isFinite() && loc.latitude != 0.0
		val lngOk = loc.longitude.isFinite() && loc.longitude != 0.0
		logStage("latitude=${if (latOk) "valid" else "invalid"}")
		logStage("longitude=${if (lngOk) "valid" else "invalid"}")
		val accuracy = if (loc.hasAccuracy()) loc.accuracy else -1f
		val ageSec = ((System.currentTimeMillis() - loc.time).coerceAtLeast(0L) / 1000.0)
		logStage("accuracy=$accuracy")
		logStage("location_age=$ageSec")
		if (!latOk || !lngOk) {
			logStage("accepted=false")
			logStage("rejection_reason=invalid_coordinates")
			return false
		}
		if (loc.latitude == 0.0 && loc.longitude == 0.0) {
			logStage("accepted=false")
			logStage("rejection_reason=zero_coordinates")
			return false
		}
		val prev = freshFix.get()
		val better = prev == null ||
			(loc.hasAccuracy() && prev.hasAccuracy() && loc.accuracy < prev.accuracy - 1f) ||
			loc.time > prev.time
		if (!better) {
			logStage("accepted=false")
			logStage("rejection_reason=weaker_than_current")
			return false
		}
		freshFix.set(loc)
		fixAccepted.set(true)
		logStage("accepted=true")
		logStage("rejection_reason=")
		// Cancel timeout immediately so it cannot overwrite success later.
		timeoutRunnable?.let { mainHandler.removeCallbacks(it) }
		timeoutRunnable = null
		return true
	}

	@UsedByGodot
	fun location_diagnostics(): String {
		return try {
			val fine = has_fine_location_permission()
			val coarse = has_coarse_location_permission()
			val enabled = is_location_enabled()
			val lm = appContext().getSystemService(Context.LOCATION_SERVICE) as LocationManager
			val providers = try {
				lm.getProviders(true).joinToString(",")
			} catch (_: Exception) {
				""
			}
			"perm_fine=$fine|perm_coarse=$coarse|enabled=$enabled|providers=$providers|init=$providerInitialized|listening=$freshListening|accepted=${fixAccepted.get()}|req=$activeRequestId"
		} catch (e: Exception) {
			"error|${e.javaClass.simpleName}"
		}
	}

	@SuppressLint("MissingPermission")
	private fun peekBestLastKnownSync(): Location? {
		if (!has_location_permission()) return null
		var best: Location? = null
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
				return "error|Allow Location permission to use your current location.|denied"
			}
			if (!is_location_enabled()) {
				return "error|Turn on Location Services to use your current location.|disabled"
			}
			val best = peekBestLastKnownSync()
			if (best == null) {
				return "error|We couldn't determine your location. Try again.|unavailable"
			}
			encodeLocation(best, "last_known")
		} catch (e: Exception) {
			Log.w(TAG, "get_last_known_location failed: ${e.javaClass.simpleName}")
			"error|We couldn't determine your location. Try again.|unavailable"
		}
	}

	/** Begin fused + network/GPS listen. Fully non-blocking. */
	@SuppressLint("MissingPermission")
	@UsedByGodot
	fun begin_fresh_location(): Boolean {
		return try {
			logStage("current_location_requested")
			logStage("permission_fine=${has_fine_location_permission()}")
			logStage("permission_coarse=${has_coarse_location_permission()}")
			logStage("location_services=${is_location_enabled()}")
			if (!has_location_permission()) {
				logStage("provider_initialized=false")
				logStage("rejection_reason=permission_denied")
				return false
			}
			if (!is_location_enabled()) {
				logStage("provider_initialized=false")
				logStage("rejection_reason=location_services_off")
				return false
			}

			stopFreshListen(clearFix = true)
			freshFix.set(null)
			fixAccepted.set(false)
			activeRequestId = requestGen.incrementAndGet()
			val requestId = activeRequestId
			freshListening = true

			val client = LocationServices.getFusedLocationProviderClient(appContext())
			providerInitialized = true
			logStage("provider_initialized=true")
			logStage("provider_type=fused+network+gps")

			// 1) Async fused last location (never block on Task — that blocked Galaxy before request start).
			client.lastLocation
				.addOnSuccessListener { loc ->
					if (loc == null) return@addOnSuccessListener
					val age = System.currentTimeMillis() - loc.time
					if (age in 0..ACCEPTABLE_CACHED_AGE_MS) {
						considerFix(loc, "fused_last", requestId)
					} else {
						logStage("rejection_reason=fused_last_too_old age_ms=$age")
					}
				}
				.addOnFailureListener { e ->
					logStage("fused_last_failed=${e.javaClass.simpleName}")
				}

			// 2) One-shot fused current location (Wi‑Fi/network/GPS).
			val cts = CancellationTokenSource()
			currentLocationCts = cts
			client.getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY, cts.token)
				.addOnSuccessListener { loc ->
					considerFix(loc, "fused_current", requestId)
				}
				.addOnFailureListener { e ->
					logStage("fused_current_failed=${e.javaClass.simpleName}")
				}

			// 3) Streaming high-accuracy fused updates.
			val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 1000L)
				.setMinUpdateIntervalMillis(500L)
				.setMaxUpdates(16)
				.setWaitForAccurateLocation(false)
				.setDurationMillis(FRESH_TIMEOUT_MS)
				.build()
			val callback = object : LocationCallback() {
				override fun onLocationResult(result: LocationResult) {
					considerFix(result.lastLocation, "fused_update", requestId)
				}
			}
			fusedCallback = callback
			client.requestLocationUpdates(request, callback, Looper.getMainLooper())

			// 4) Platform LocationManager network/GPS as parallel fallback (no Play Services wait).
			startLocationManagerFallback(requestId)

			logStage("location_request_started")

			val timeout = Runnable {
				if (requestId != activeRequestId) {
					logStage("timeout_fired stale ignored id=$requestId")
					return@Runnable
				}
				if (fixAccepted.get()) {
					logStage("timeout_fired after success — ignored")
					stopFreshListen(clearFix = false)
					return@Runnable
				}
				logStage("timeout_fired")
				stopFreshListen(clearFix = false)
			}
			timeoutRunnable = timeout
			mainHandler.postDelayed(timeout, FRESH_TIMEOUT_MS)
			true
		} catch (e: Exception) {
			Log.w(TAG, "begin_fresh_location failed: ${e.javaClass.simpleName}: ${e.message}")
			logStage("provider_initialized=false")
			logStage("rejection_reason=begin_exception_${e.javaClass.simpleName}")
			freshListening = false
			false
		}
	}

	@SuppressLint("MissingPermission")
	private fun startLocationManagerFallback(requestId: Int) {
		try {
			val lm = appContext().getSystemService(Context.LOCATION_SERVICE) as LocationManager
			val providers = listOf(
				LocationManager.NETWORK_PROVIDER,
				LocationManager.GPS_PROVIDER,
			)
			for (provider in providers) {
				if (!lm.isProviderEnabled(provider)) continue
				// Seed from last-known immediately (sync, no await).
				try {
					val last = lm.getLastKnownLocation(provider)
					if (last != null) {
						val age = System.currentTimeMillis() - last.time
						if (age in 0..ACCEPTABLE_CACHED_AGE_MS) {
							considerFix(last, "lm_last_$provider", requestId)
						}
					}
				} catch (_: SecurityException) {
				}
				val listener = object : LocationListener {
					override fun onLocationChanged(location: Location) {
						considerFix(location, "lm_$provider", requestId)
					}
					@Deprecated("Deprecated in Java")
					override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
					override fun onProviderEnabled(provider: String) {}
					override fun onProviderDisabled(provider: String) {}
				}
				try {
					lm.requestLocationUpdates(provider, 500L, 0f, listener, Looper.getMainLooper())
					lmListeners.add(lm to listener)
				} catch (e: Exception) {
					logStage("lm_request_failed provider=$provider err=${e.javaClass.simpleName}")
				}
			}
		} catch (e: Exception) {
			logStage("lm_fallback_failed=${e.javaClass.simpleName}")
		}
	}

	@UsedByGodot
	fun poll_fresh_location(): String {
		val loc = freshFix.get()
		if (loc != null && fixAccepted.get()) {
			stopFreshListen(clearFix = false)
			return encodeLocation(loc, "fused")
		}
		if (!freshListening) {
			val last = peekBestLastKnownSync()
			if (last != null) {
				val age = System.currentTimeMillis() - last.time
				if (age in 0..ACCEPTABLE_CACHED_AGE_MS) {
					return encodeLocation(last, "last_known")
				}
			}
			return "error|We couldn't determine your location. Try again.|timeout"
		}
		return "error|Still getting location…|pending"
	}

	@UsedByGodot
	fun cancel_fresh_location(): Boolean {
		stopFreshListen(clearFix = true)
		return true
	}

	@UsedByGodot
	fun active_request_id(): Int = activeRequestId

	@UsedByGodot
	fun request_fresh_location(): String {
		// Prefer async begin/poll from GDScript. Blocking path kept as last resort.
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
			if (loc != null && fixAccepted.get()) {
				stopFreshListen(clearFix = false)
				return encodeLocation(loc, "fused")
			}
			try {
				Thread.sleep(200L)
			} catch (_: InterruptedException) {
				break
			}
		}
		stopFreshListen(clearFix = false)
		val settled = freshFix.get()
		if (settled != null) return encodeLocation(settled, "fused")
		val last = get_last_known_location()
		return if (last.startsWith("ok|")) last
		else "error|We couldn't determine your location. Try again.|timeout"
	}

	private fun stopFreshListen(clearFix: Boolean = false) {
		freshListening = false
		timeoutRunnable?.let { mainHandler.removeCallbacks(it) }
		timeoutRunnable = null
		currentLocationCts?.cancel()
		currentLocationCts = null
		val callback = fusedCallback
		fusedCallback = null
		if (callback != null) {
			try {
				LocationServices.getFusedLocationProviderClient(appContext())
					.removeLocationUpdates(callback)
			} catch (_: Exception) {
			}
		}
		for ((lm, listener) in lmListeners) {
			try {
				lm.removeUpdates(listener)
			} catch (_: Exception) {
			}
		}
		lmListeners.clear()
		if (clearFix) {
			freshFix.set(null)
			fixAccepted.set(false)
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

	@SuppressLint("MissingPermission")
	@UsedByGodot
	fun register_scroll_geofence(scrollId: String, lat: Double, lng: Double, radiusM: Float): Boolean {
		return try {
			if (scrollId.isBlank() || radiusM <= 0f) return false
			if (!has_location_permission()) return false
			if (Build.VERSION.SDK_INT >= 29 && !has_background_location_permission()) {
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
