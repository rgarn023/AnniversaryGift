package com.charoitegames.chestoflovenotes.securestorage

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.provider.Settings
import android.util.Base64
import android.util.Log
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeWriter
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.io.ByteArrayOutputStream

/**
 * QR encode (Show My Code) + camera scan (Scan Person Code).
 * Does not request camera until scan is started from GDScript.
 */
class ChestQrPlugin(godot: Godot) : GodotPlugin(godot) {

	companion object {
		private const val TAG = "ChestQr"
		private const val PLUGIN = "ChestQr"
		const val SCAN_REQ = 0xC01A
	}

	override fun getPluginName(): String = PLUGIN

	override fun getPluginSignals(): Set<SignalInfo> = setOf(
		SignalInfo("qr_scanned", String::class.java),
		SignalInfo("qr_scan_cancelled"),
		SignalInfo("qr_scan_error", String::class.java),
	)

	@UsedByGodot
	fun qr_plugin_available(): Boolean = true

	@UsedByGodot
	fun has_camera_permission(): Boolean {
		val ctx = getActivity() ?: return false
		return ctx.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
	}

	@UsedByGodot
	fun request_camera_permission(): Boolean {
		val act = getActivity() ?: return false
		if (has_camera_permission()) return true
		act.requestPermissions(arrayOf(Manifest.permission.CAMERA), 0xC01B)
		return false
	}

	@UsedByGodot
	fun open_app_settings(): Boolean {
		return try {
			val act = getActivity() ?: return false
			val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
				data = Uri.fromParts("package", act.packageName, null)
				addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
			}
			act.startActivity(intent)
			true
		} catch (e: Exception) {
			Log.w(TAG, "open_app_settings failed: ${e.javaClass.simpleName}")
			false
		}
	}

	/** Encode payload to PNG base64 (no camera needed). */
	@UsedByGodot
	fun encode_qr_png_base64(payload: String, sizePx: Int): String {
		return try {
			val sz = sizePx.coerceIn(128, 1024)
			val bitMatrix = QRCodeWriter().encode(payload, BarcodeFormat.QR_CODE, sz, sz)
			val bmp = Bitmap.createBitmap(sz, sz, Bitmap.Config.ARGB_8888)
			for (x in 0 until sz) {
				for (y in 0 until sz) {
					bmp.setPixel(x, y, if (bitMatrix[x, y]) Color.BLACK else Color.WHITE)
				}
			}
			val out = ByteArrayOutputStream()
			bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
			Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
		} catch (e: Exception) {
			Log.w(TAG, "encode_qr failed: ${e.javaClass.simpleName}")
			""
		}
	}

	/** Launch dedicated scanner activity. */
	@UsedByGodot
	fun start_qr_scan(): Boolean {
		return try {
			val act = getActivity() ?: return false
			if (!has_camera_permission()) {
				emitSignal("qr_scan_error", "camera_permission")
				return false
			}
			val intent = Intent(act, QrScanActivity::class.java)
			act.startActivityForResult(intent, SCAN_REQ)
			true
		} catch (e: Exception) {
			Log.w(TAG, "start_qr_scan failed: ${e.javaClass.simpleName}")
			emitSignal("qr_scan_error", "start_failed")
			false
		}
	}

	override fun onMainActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
		if (requestCode != SCAN_REQ) return
		if (resultCode != Activity.RESULT_OK || data == null) {
			emitSignal("qr_scan_cancelled")
			return
		}
		val text = data.getStringExtra(QrScanActivity.EXTRA_RESULT).orEmpty()
		if (text.isBlank()) {
			emitSignal("qr_scan_error", "empty")
		} else {
			emitSignal("qr_scanned", text)
		}
	}

	/** Decode a still image RGBA buffer (optional helper). */
	@UsedByGodot
	fun decode_qr_from_rgba(width: Int, height: Int, rgba: ByteArray): String {
		return try {
			val pixels = IntArray(width * height)
			var i = 0
			var p = 0
			while (i + 3 < rgba.size && p < pixels.size) {
				val r = rgba[i].toInt() and 0xff
				val g = rgba[i + 1].toInt() and 0xff
				val b = rgba[i + 2].toInt() and 0xff
				pixels[p] = (0xff shl 24) or (r shl 16) or (g shl 8) or b
				i += 4
				p++
			}
			val source = RGBLuminanceSource(width, height, pixels)
			val bitmap = BinaryBitmap(HybridBinarizer(source))
			val hints = mapOf(DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE))
			val result = MultiFormatReader().decode(bitmap, hints)
			result.text ?: ""
		} catch (_: Exception) {
			""
		}
	}
}
