package com.charoitegames.chestoflovenotes.securestorage

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import org.json.JSONObject
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Foreground location tracking for an explicitly started Activity Lock challenge.
 * Only runs while a challenge is active. Persists cumulative distance (not a route trail).
 */
class ActivityLockService : Service(), LocationListener {

	companion object {
		private const val TAG = "ChestActivitySvc"
		const val ACTION_START = "coln.activity.START"
		const val ACTION_STOP = "coln.activity.STOP"
		const val EXTRA_SCROLL_ID = "scroll_id"
		const val EXTRA_TARGET_KM = "target_km"
		const val EXTRA_START_LAT = "start_lat"
		const val EXTRA_START_LNG = "start_lng"
		const val PREFS = "coln_activity_lock"
		const val KEY_STATE = "state_json"
		const val NOTIF_ID = 2201
		const val CH_ID = "coln_activity"
		private const val MIN_SEGMENT_M = 12.0
		private const val MAX_ACCURACY_M = 50.0
		private const val MAX_SPEED_M_S = 55.0
		private const val NOTIF_UPDATE_MS = 15_000L

		fun isRunning(ctx: Context): Boolean {
			val st = readState(ctx) ?: return false
			return st.optBoolean("started", false) && !st.optBoolean("completed", false) &&
				st.optBoolean("service_active", false)
		}

		fun readState(ctx: Context): JSONObject? {
			return try {
				val raw = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_STATE, null)
				if (raw.isNullOrBlank()) null else JSONObject(raw)
			} catch (_: Exception) {
				null
			}
		}

		fun writeState(ctx: Context, state: JSONObject) {
			ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
				.edit()
				.putString(KEY_STATE, state.toString())
				.apply()
		}

		fun clearState(ctx: Context) {
			ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY_STATE).apply()
		}

		fun haversineM(lat1: Double, lng1: Double, lat2: Double, lng2: Double): Double {
			val r = 6371000.0
			val p1 = Math.toRadians(lat1)
			val p2 = Math.toRadians(lat2)
			val dp = Math.toRadians(lat2 - lat1)
			val dl = Math.toRadians(lng2 - lng1)
			val a = sin(dp / 2) * sin(dp / 2) +
				cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
			return r * 2 * atan2(sqrt(a), sqrt((1 - a).coerceAtLeast(0.0)))
		}
	}

	private var lm: LocationManager? = null
	private val handler = Handler(Looper.getMainLooper())
	private var lastNotifMs = 0L

	override fun onBind(intent: Intent?): IBinder? = null

	override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
		when (intent?.action) {
			ACTION_STOP -> {
				stopTracking(completed = false)
				return START_NOT_STICKY
			}
			ACTION_START -> {
				val scrollId = intent.getStringExtra(EXTRA_SCROLL_ID) ?: ""
				val target = intent.getDoubleExtra(EXTRA_TARGET_KM, 5.0)
				val lat = intent.getDoubleExtra(EXTRA_START_LAT, Double.NaN)
				val lng = intent.getDoubleExtra(EXTRA_START_LNG, Double.NaN)
				begin(scrollId, target, lat, lng)
			}
			else -> {
				val existing = readState(this)
				if (existing != null && existing.optBoolean("started", false) &&
					!existing.optBoolean("completed", false)
				) {
					existing.put("service_active", true)
					writeState(this, existing)
					startFg(existing)
					startLocationUpdates()
				} else {
					stopSelf()
				}
			}
		}
		return START_STICKY
	}

	private fun begin(scrollId: String, targetKm: Double, lat: Double, lng: Double) {
		val now = System.currentTimeMillis() / 1000L
		val state = JSONObject()
			.put("scroll_id", scrollId)
			.put("started", true)
			.put("completed", false)
			.put("service_active", true)
			.put("target_km", targetKm.coerceIn(1.0, 100.0))
			.put("distance_km", 0.0)
			.put("last_lat", if (lat.isFinite()) lat else JSONObject.NULL)
			.put("last_lng", if (lng.isFinite()) lng else JSONObject.NULL)
			.put("last_unix", now)
			.put("started_unix", now)
		writeState(this, state)
		startFg(state)
		startLocationUpdates()
	}

	private fun startFg(state: JSONObject) {
		ensureChannel()
		val notif = buildProgressNotif(state)
		if (Build.VERSION.SDK_INT >= 29) {
			startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
		} else {
			startForeground(NOTIF_ID, notif)
		}
	}

	private fun ensureChannel() {
		if (Build.VERSION.SDK_INT >= 26) {
			val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
			nm.createNotificationChannel(
				NotificationChannel(CH_ID, "Activity Lock", NotificationManager.IMPORTANCE_LOW),
			)
		}
	}

	private fun buildProgressNotif(state: JSONObject): Notification {
		val cur = state.optDouble("distance_km", 0.0)
		val target = state.optDouble("target_km", 5.0)
		val launch = packageManager.getLaunchIntentForPackage(packageName) ?: Intent()
		launch.putExtra("coln_deeplink", "activity:${state.optString("scroll_id", "")}")
		launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
		val pi = PendingIntent.getActivity(
			this,
			NOTIF_ID,
			launch,
			PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
		)
		val builder = if (Build.VERSION.SDK_INT >= 26) {
			Notification.Builder(this, CH_ID)
		} else {
			@Suppress("DEPRECATION")
			Notification.Builder(this)
		}
		return builder
			.setSmallIcon(android.R.drawable.ic_menu_mylocation)
			.setContentTitle("Activity Lock in progress")
			.setContentText(String.format("%.1f / %.1f km", cur, target))
			.setOngoing(true)
			.setOnlyAlertOnce(true)
			.setContentIntent(pi)
			.build()
	}

	private fun startLocationUpdates() {
		if (checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) !=
			PackageManager.PERMISSION_GRANTED &&
			checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION) !=
			PackageManager.PERMISSION_GRANTED
		) {
			Log.w(TAG, "location permission missing — stopping service")
			stopTracking(completed = false)
			return
		}
		lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
		try {
			val providers = lm?.getProviders(true) ?: emptyList()
			for (p in providers) {
				lm?.requestLocationUpdates(p, 4000L, 8f, this, Looper.getMainLooper())
			}
		} catch (e: SecurityException) {
			Log.w(TAG, "requestLocationUpdates denied")
			stopTracking(completed = false)
		}
	}

	override fun onLocationChanged(location: Location) {
		val state = readState(this) ?: return
		if (!state.optBoolean("started", false) || state.optBoolean("completed", false)) {
			stopTracking(completed = state.optBoolean("completed", false))
			return
		}
		val accuracy = if (location.hasAccuracy()) location.accuracy.toDouble() else -1.0
		if (accuracy > MAX_ACCURACY_M && accuracy > 0) return
		val lat = location.latitude
		val lng = location.longitude
		val now = System.currentTimeMillis() / 1000L
		if (!state.isNull("last_lat") && !state.isNull("last_lng")) {
			val lastLat = state.getDouble("last_lat")
			val lastLng = state.getDouble("last_lng")
			val seg = haversineM(lastLat, lastLng, lat, lng)
			val dt = (now - state.optLong("last_unix", now)).coerceAtLeast(1)
			val speed = seg / dt.toDouble()
			if (seg >= MIN_SEGMENT_M && speed <= MAX_SPEED_M_S) {
				state.put("distance_km", state.optDouble("distance_km", 0.0) + seg / 1000.0)
			}
		}
		state.put("last_lat", lat)
		state.put("last_lng", lng)
		state.put("last_unix", now)
		val target = state.optDouble("target_km", 5.0)
		if (state.optDouble("distance_km", 0.0) + 1e-6 >= target) {
			state.put("distance_km", target)
			state.put("completed", true)
			state.put("completed_unix", now)
			state.put("service_active", false)
			writeState(this, state)
			notifyComplete(state)
			stopTracking(completed = true)
			return
		}
		writeState(this, state)
		val t = System.currentTimeMillis()
		if (t - lastNotifMs >= NOTIF_UPDATE_MS) {
			lastNotifMs = t
			val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
			nm.notify(NOTIF_ID, buildProgressNotif(state))
		}
	}

	@Deprecated("Deprecated in Java")
	override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
	override fun onProviderEnabled(provider: String) {}
	override fun onProviderDisabled(provider: String) {}

	private fun notifyComplete(state: JSONObject) {
		ensureChannel()
		val launch = packageManager.getLaunchIntentForPackage(packageName) ?: Intent()
		launch.putExtra("coln_deeplink", "chest:${state.optString("scroll_id", "")}")
		val pi = PendingIntent.getActivity(
			this,
			NOTIF_ID + 1,
			launch,
			PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
		)
		val builder = if (Build.VERSION.SDK_INT >= 26) {
			Notification.Builder(this, CH_ID)
		} else {
			@Suppress("DEPRECATION")
			Notification.Builder(this)
		}
		val notif = builder
			.setSmallIcon(android.R.drawable.ic_dialog_info)
			.setContentTitle("Activity Lock complete")
			.setContentText("Activity Lock complete.")
			.setAutoCancel(true)
			.setContentIntent(pi)
			.build()
		val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
		nm.cancel(NOTIF_ID)
		nm.notify(NOTIF_ID + 1, notif)
	}

	private fun stopTracking(completed: Boolean) {
		try {
			lm?.removeUpdates(this)
		} catch (_: Exception) {
		}
		lm = null
		val state = readState(this)
		if (state != null) {
			state.put("service_active", false)
			if (completed) state.put("completed", true)
			writeState(this, state)
		}
		stopForeground(STOP_FOREGROUND_REMOVE)
		stopSelf()
	}

	override fun onDestroy() {
		try {
			lm?.removeUpdates(this)
		} catch (_: Exception) {
		}
		val state = readState(this)
		if (state != null) {
			state.put("service_active", false)
			writeState(this, state)
		}
		super.onDestroy()
	}
}
