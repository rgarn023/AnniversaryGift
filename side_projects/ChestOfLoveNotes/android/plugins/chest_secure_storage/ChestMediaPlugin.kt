package com.charoitegames.chestoflovenotes.securestorage

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.io.File
import java.io.FileOutputStream

/**
 * Android Photo Picker / image-only gallery selection for scroll attachments.
 * Prefer system Photo Picker (API 33+); fallback to ACTION_GET_CONTENT for images.
 */
class ChestMediaPlugin(godot: Godot) : GodotPlugin(godot) {

	companion object {
		private const val TAG = "ChestMedia"
		private const val PLUGIN_NAME = "ChestMedia"
		private const val REQ_PICK_IMAGES = 0xC0F1
	}

	override fun getPluginName(): String = PLUGIN_NAME

	override fun getPluginSignals(): Set<SignalInfo> {
		return setOf(
			SignalInfo("images_picked", String::class.java),
			SignalInfo("images_pick_cancelled"),
		)
	}

	@UsedByGodot
	fun media_plugin_available(): Boolean = true

	@UsedByGodot
	fun pick_images(maxCount: Int): Boolean {
		val act = getActivity() ?: return false
		val limit = maxCount.coerceIn(1, 5)
		return try {
			val intent = if (Build.VERSION.SDK_INT >= 33) {
				Intent(MediaStore.ACTION_PICK_IMAGES).apply {
					type = "image/*"
					if (limit > 1) {
						putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, limit)
					}
				}
			} else {
				Intent(Intent.ACTION_GET_CONTENT).apply {
					type = "image/*"
					addCategory(Intent.CATEGORY_OPENABLE)
					putExtra(Intent.EXTRA_ALLOW_MULTIPLE, limit > 1)
					putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/jpeg", "image/png", "image/webp"))
				}
			}
			act.startActivityForResult(intent, REQ_PICK_IMAGES)
			true
		} catch (e: Exception) {
			Log.w(TAG, "pick_images failed: ${e.javaClass.simpleName}")
			false
		}
	}

	override fun onMainActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
		if (requestCode != REQ_PICK_IMAGES) return
		if (resultCode != Activity.RESULT_OK || data == null) {
			emitSignal("images_pick_cancelled")
			return
		}
		val uris = ArrayList<Uri>()
		val clip = data.clipData
		if (clip != null) {
			for (i in 0 until clip.itemCount) {
				uris.add(clip.getItemAt(i).uri)
			}
		} else {
			data.data?.let { uris.add(it) }
		}
		if (uris.isEmpty()) {
			emitSignal("images_pick_cancelled")
			return
		}
		val paths = ArrayList<String>()
		for (uri in uris) {
			val path = copyUriToCache(uri) ?: continue
			paths.add(path)
		}
		if (paths.isEmpty()) {
			emitSignal("images_pick_cancelled")
			return
		}
		emitSignal("images_picked", paths.joinToString("\n"))
	}

	private fun copyUriToCache(uri: Uri): String? {
		val act = getActivity() ?: return null
		return try {
			val resolver = act.contentResolver
			val mime = resolver.getType(uri) ?: "image/jpeg"
			if (!mime.startsWith("image/")) {
				return null
			}
			val ext = when {
				mime.contains("png") -> "png"
				mime.contains("webp") -> "webp"
				else -> "jpg"
			}
			val dir = File(act.cacheDir, "coln_photo_pick")
			if (!dir.exists()) dir.mkdirs()
			val out = File(dir, "pick_${System.currentTimeMillis()}_${(Math.random() * 100000).toInt()}.$ext")
			resolver.openInputStream(uri)?.use { input ->
				FileOutputStream(out).use { output -> input.copyTo(output) }
			} ?: return null
			out.absolutePath
		} catch (e: Exception) {
			Log.w(TAG, "copyUriToCache failed: ${e.javaClass.simpleName}")
			null
		}
	}
}
