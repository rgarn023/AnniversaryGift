package com.charoitegames.chestoflovenotes.securestorage

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.util.Log
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot

/**
 * One-shot last-known location for Location Lock.
 * Never polls GPS continuously. Never grants unlock on failure.
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
		// Returns "ok|lat|lng|accuracy" or "error|<message>|<code>"
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
}
