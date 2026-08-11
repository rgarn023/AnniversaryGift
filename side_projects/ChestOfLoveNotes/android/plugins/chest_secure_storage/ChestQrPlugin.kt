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
import com.google.zxing.EncodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.io.ByteArrayOutputStream
import java.util.EnumMap
import java.util.concurrent.atomic.AtomicReference

/**
 * QR encode (Show My Code) + camera scan (Scan Person Code).
 * Does not request camera until scan is started from GDScript.
 * Scan results are delivered via onMainActivityResult and a pending-result flush on resume
 * (Godot does not always forward activity results reliably).
 */
class ChestQrPlugin(godot: Godot) : GodotPlugin(godot) {

	companion object {
		private const val TAG = "ChestQr"
		private const val PLUGIN = "ChestQr"
		const val SCAN_REQ = 0xC01A

		/** Cross-activity pending result (QrScanActivity → plugin). */
		private val pendingScanText = AtomicReference<String?>(null)
		private val pendingScanCancelled = AtomicReference(false)

		fun deliverScanResult(text: String) {
			pendingScanText.set(text)
			pendingScanCancelled.set(false)
		}

		fun deliverScanCancelled() {
			pendingScanText.set(null)
			pendingScanCancelled.set(true)
		}
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
		if (has_camera_permission()) return true
		val act = getActivity() ?: run {
			Log.w(TAG, "request_camera_permission: activity null")
			return false
		}
		Log.i(TAG, "permission camera requested")
		act.runOnUiThread {
			try {
				act.requestPermissions(arrayOf(Manifest.permission.CAMERA), 0xC01B)
			} catch (e: Exception) {
				Log.w(TAG, "requestPermissions failed: ${e.javaClass.simpleName}")
			}
		}
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

	/** Encode payload to PNG base64 with quiet zone. Empty if round-trip decode fails. */
	@UsedByGodot
	fun encode_qr_png_base64(payload: String, sizePx: Int): String {
		return try {
			if (payload.isBlank()) return ""
			val sz = sizePx.coerceIn(256, 1024)
			val hints = EnumMap<EncodeHintType, Any>(EncodeHintType::class.java)
			hints[EncodeHintType.ERROR_CORRECTION] = ErrorCorrectionLevel.M
			hints[EncodeHintType.MARGIN] = 2 // quiet zone
			hints[EncodeHintType.CHARACTER_SET] = "UTF-8"
			val bitMatrix = QRCodeWriter().encode(payload, BarcodeFormat.QR_CODE, sz, sz, hints)
			val bmp = Bitmap.createBitmap(sz, sz, Bitmap.Config.ARGB_8888)
			for (x in 0 until sz) {
				for (y in 0 until sz) {
					bmp.setPixel(x, y, if (bitMatrix[x, y]) Color.BLACK else Color.WHITE)
				}
			}
			// Verify decodable before returning — rendering alone is not success.
			val decoded = decodeBitmap(bmp)
			if (decoded.isBlank() || decoded != payload) {
				Log.w(TAG, "encode_qr verify failed got='${decoded.take(48)}'")
				return ""
			}
			val out = ByteArrayOutputStream()
			bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
			Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
		} catch (e: Exception) {
			Log.w(TAG, "encode_qr failed: ${e.javaClass.simpleName}")
			""
		}
	}

	/** Returns "ok|<payload>" if encode→decode roundtrip succeeds. */
	@UsedByGodot
	fun verify_qr_roundtrip(payload: String, sizePx: Int): String {
		return try {
			val b64 = encode_qr_png_base64(payload, sizePx)
			if (b64.isEmpty()) return "fail|encode_or_decode"
			"ok|$payload"
		} catch (e: Exception) {
			"fail|${e.javaClass.simpleName}"
		}
	}

	private fun decodeBitmap(bmp: Bitmap): String {
		val w = bmp.width
		val h = bmp.height
		val pixels = IntArray(w * h)
		bmp.getPixels(pixels, 0, w, 0, 0, w, h)
		val source = RGBLuminanceSource(w, h, pixels)
		val bitmap = BinaryBitmap(HybridBinarizer(source))
		val hints = mapOf(DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE))
		return MultiFormatReader().decode(bitmap, hints).text ?: ""
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
			pendingScanText.set(null)
			pendingScanCancelled.set(false)
			val intent = Intent(act, QrScanActivity::class.java)
			act.startActivityForResult(intent, SCAN_REQ)
			Log.i(TAG, "scanner started")
			true
		} catch (e: Exception) {
			Log.w(TAG, "start_qr_scan failed: ${e.javaClass.simpleName}")
			emitSignal("qr_scan_error", "start_failed")
			false
		}
	}

	override fun onMainActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
		if (requestCode != SCAN_REQ) return
		flushPendingScan(resultCode, data)
	}

	override fun onMainResume() {
		super.onMainResume()
		// Godot may miss onActivityResult — flush static pending delivery.
		val text = pendingScanText.getAndSet(null)
		val cancelled = pendingScanCancelled.getAndSet(false)
		when {
			!text.isNullOrBlank() -> {
				Log.i(TAG, "qr_scanned via pending")
				emitSignal("qr_scanned", text)
			}
			cancelled -> emitSignal("qr_scan_cancelled")
		}
	}

	private fun flushPendingScan(resultCode: Int, data: Intent?) {
		if (resultCode != Activity.RESULT_OK || data == null) {
			pendingScanCancelled.set(true)
			pendingScanText.set(null)
			emitSignal("qr_scan_cancelled")
			return
		}
		val text = data.getStringExtra(QrScanActivity.EXTRA_RESULT).orEmpty()
		if (text.isBlank()) {
			emitSignal("qr_scan_error", "empty")
		} else {
			pendingScanText.set(null)
			pendingScanCancelled.set(false)
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
