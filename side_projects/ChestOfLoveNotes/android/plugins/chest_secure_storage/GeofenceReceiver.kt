package com.charoitegames.chestoflovenotes.securestorage

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import org.json.JSONObject

/**
 * Handles opt-in Location Lock geofence enter/dwell transitions while the app is closed.
 */
class GeofenceReceiver : BroadcastReceiver() {

	companion object {
		private const val TAG = "ChestGeofence"
		const val ACTION_TRANSITION = "coln.geofence.TRANSITION"
		const val EXTRA_SCROLL_ID = "scroll_id"
		private const val PREFS = "coln_geofences"
		private const val KEY_FENCES = "fences_json"
		private const val CH_ID = ChestNotifyPlugin.CH_SCROLLS

		fun persistFence(ctx: Context, scrollId: String, lat: Double, lng: Double, radiusM: Float) {
			val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
			val root = try {
				JSONObject(prefs.getString(KEY_FENCES, "{}") ?: "{}")
			} catch (_: Exception) {
				JSONObject()
			}
			root.put(
				scrollId,
				JSONObject()
					.put("lat", lat)
					.put("lng", lng)
					.put("radius_m", radiusM.toDouble())
					.put("id", "coln_geo_$scrollId"),
			)
			prefs.edit().putString(KEY_FENCES, root.toString()).apply()
		}

		fun removeFence(ctx: Context, scrollId: String) {
			val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
			val root = try {
				JSONObject(prefs.getString(KEY_FENCES, "{}") ?: "{}")
			} catch (_: Exception) {
				JSONObject()
			}
			root.remove(scrollId)
			prefs.edit().putString(KEY_FENCES, root.toString()).apply()
		}

		fun clearAll(ctx: Context) {
			ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
		}

		fun allFenceIds(ctx: Context): List<String> {
			val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
			val root = try {
				JSONObject(prefs.getString(KEY_FENCES, "{}") ?: "{}")
			} catch (_: Exception) {
				return emptyList()
			}
			val out = ArrayList<String>()
			val keys = root.keys()
			while (keys.hasNext()) {
				val sid = keys.next()
				val obj = root.optJSONObject(sid) ?: continue
				out.add(obj.optString("id", "coln_geo_$sid"))
			}
			return out
		}
	}

	override fun onReceive(context: Context, intent: Intent?) {
		if (intent == null) return
		val event = GeofencingEvent.fromIntent(intent)
		if (event == null) {
			Log.w(TAG, "null geofencing event")
			return
		}
		if (event.hasError()) {
			Log.w(TAG, "geofence error=${event.errorCode}")
			return
		}
		val transition = event.geofenceTransition
		if (
			transition != Geofence.GEOFENCE_TRANSITION_ENTER &&
			transition != Geofence.GEOFENCE_TRANSITION_DWELL
		) {
			return
		}
		var scrollId = intent.getStringExtra(EXTRA_SCROLL_ID).orEmpty()
		if (scrollId.isEmpty()) {
			val triggering = event.triggeringGeofences
			val req = triggering?.firstOrNull()?.requestId.orEmpty()
			if (req.startsWith("coln_geo_")) {
				scrollId = req.removePrefix("coln_geo_")
			}
		}
		if (scrollId.isEmpty()) return
		Log.i(TAG, "enter/dwell scroll=$scrollId")
		// Persist pending completion for Godot to reconcile on resume.
		context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
			.edit()
			.putString("pending_enter_$scrollId", System.currentTimeMillis().toString())
			.apply()
		showLocalNotification(
			context,
			scrollId,
			"Location Lock complete",
			"A scroll's location requirement may be complete. Open Chest of Love Notes to check.",
			"chest:$scrollId",
		)
	}

	private fun showLocalNotification(
		ctx: Context,
		scrollId: String,
		title: String,
		body: String,
		deepLink: String,
	) {
		try {
			if (Build.VERSION.SDK_INT >= 33) {
				val granted = ctx.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
					android.content.pm.PackageManager.PERMISSION_GRANTED
				if (!granted) {
					Log.i(TAG, "geofence notify skipped: permission denied")
					return
				}
			}
			if (Build.VERSION.SDK_INT >= 26) {
				val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
				nm.createNotificationChannel(
					NotificationChannel(CH_ID, "Scrolls", NotificationManager.IMPORTANCE_DEFAULT),
				)
			}
			val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName) ?: Intent()
			launch.putExtra("coln_deeplink", deepLink)
			launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
			val notifId = 0x67000000 or (scrollId.hashCode() and 0x00FFFFFF)
			val pi = PendingIntent.getActivity(
				ctx,
				notifId,
				launch,
				PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
			)
			val builder = if (Build.VERSION.SDK_INT >= 26) {
				Notification.Builder(ctx, CH_ID)
			} else {
				@Suppress("DEPRECATION")
				Notification.Builder(ctx)
			}
			val pkg = ctx.packageName
			val res = ctx.resources
			val iconCandidates = intArrayOf(
				res.getIdentifier("ic_coln_notification", "drawable", pkg),
				res.getIdentifier("icon", "mipmap", pkg),
				ctx.applicationInfo.icon,
			)
			val iconRes = iconCandidates.firstOrNull { it != 0 } ?: android.R.drawable.stat_notify_chat
			val notif = builder
				.setSmallIcon(iconRes)
				.setContentTitle(title)
				.setContentText(body)
				.setContentIntent(pi)
				.setAutoCancel(true)
				.build()
			val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
			nm.notify(notifId, notif)
		} catch (e: Exception) {
			Log.w(TAG, "notify failed: ${e.javaClass.simpleName}")
		}
	}
}
