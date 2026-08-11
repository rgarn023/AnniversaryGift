package com.charoitegames.chestoflovenotes.securestorage

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.view.KeyEvent
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.google.zxing.BarcodeFormat
import com.google.zxing.ResultPoint
import com.journeyapps.barcodescanner.BarcodeCallback
import com.journeyapps.barcodescanner.BarcodeResult
import com.journeyapps.barcodescanner.DecoratedBarcodeView
import com.journeyapps.barcodescanner.DefaultDecoderFactory

/**
 * Portrait QR scanner for My Person pairing.
 * Camera is released on pause / finish / destroy / back.
 */
class QrScanActivity : Activity() {

	companion object {
		const val EXTRA_RESULT = "coln_qr_result"
	}

	private var barcodeView: DecoratedBarcodeView? = null
	private var handled = false
	private var torchOn = false

	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)
		val root = LinearLayout(this).apply {
			orientation = LinearLayout.VERTICAL
			setBackgroundColor(0xFF0D081F.toInt())
			layoutParams = ViewGroup.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT,
				ViewGroup.LayoutParams.MATCH_PARENT,
			)
		}
		val title = TextView(this).apply {
			text = "Scan your Person's Chest of Love Notes code"
			setTextColor(0xFFF5E9FF.toInt())
			textSize = 16f
			setPadding(32, 48, 32, 16)
			gravity = Gravity.CENTER
		}
		root.addView(title)

		val frame = FrameLayout(this).apply {
			layoutParams = LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT,
				0,
				1f,
			)
		}
		val view = DecoratedBarcodeView(this)
		view.barcodeView.decoderFactory = DefaultDecoderFactory(listOf(BarcodeFormat.QR_CODE))
		view.statusView.text = "Align the code inside the frame"
		view.decodeContinuous(object : BarcodeCallback {
			override fun barcodeResult(result: BarcodeResult?) {
				val text = result?.text?.trim().orEmpty()
				if (handled || text.isEmpty()) return
				handled = true
				view.pause()
				ChestQrPlugin.deliverScanResult(text)
				val data = Intent().putExtra(EXTRA_RESULT, text)
				setResult(RESULT_OK, data)
				finish()
			}
			override fun possibleResultPoints(resultPoints: MutableList<ResultPoint>?) {}
		})
		barcodeView = view
		frame.addView(view)
		root.addView(frame)

		val actions = LinearLayout(this).apply {
			orientation = LinearLayout.HORIZONTAL
			setPadding(24, 16, 24, 32)
		}
		val torch = Button(this).apply {
			text = "Flashlight"
			setOnClickListener {
				torchOn = !torchOn
				if (torchOn) {
					barcodeView?.setTorchOn()
					text = "Flashlight Off"
				} else {
					barcodeView?.setTorchOff()
					text = "Flashlight"
				}
			}
		}
		val cancel = Button(this).apply {
			text = "Cancel"
			setOnClickListener { cancelAndFinish() }
		}
		actions.addView(torch, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
		actions.addView(cancel, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
		root.addView(actions)
		setContentView(root)
	}

	private fun releaseCamera() {
		try {
			barcodeView?.setTorchOff()
		} catch (_: Exception) {
		}
		torchOn = false
		try {
			barcodeView?.pause()
		} catch (_: Exception) {
		}
	}

	private fun cancelAndFinish() {
		if (handled) return
		handled = true
		releaseCamera()
		ChestQrPlugin.deliverScanCancelled()
		setResult(RESULT_CANCELED)
		finish()
	}

	override fun onResume() {
		super.onResume()
		if (!handled) {
			barcodeView?.resume()
		}
	}

	override fun onPause() {
		releaseCamera()
		super.onPause()
	}

	override fun onDestroy() {
		releaseCamera()
		barcodeView = null
		super.onDestroy()
	}

	@Deprecated("Deprecated in Java")
	override fun onBackPressed() {
		cancelAndFinish()
	}

	override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
		if (keyCode == KeyEvent.KEYCODE_BACK) {
			cancelAndFinish()
			return true
		}
		return barcodeView?.onKeyDown(keyCode, event) ?: super.onKeyDown(keyCode, event)
	}
}
