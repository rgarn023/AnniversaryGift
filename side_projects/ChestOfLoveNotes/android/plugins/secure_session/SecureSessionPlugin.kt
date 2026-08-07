package com.charoitegames.chestoflovenotes

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import java.nio.ByteBuffer
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Android Keystore-backed secure session storage for Chest of Love Notes.
 *
 * - AES-256-GCM key is generated in Android Keystore and marked non-exportable.
 * - Only ciphertext + IV are stored in private SharedPreferences.
 * - The Keystore key material is never exposed to GDScript.
 */
class SecureSessionPlugin(godot: Godot) : GodotPlugin(godot) {

	companion object {
		private const val PLUGIN_NAME = "SecureSession"
		private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
		private const val KEY_ALIAS = "coln_secure_session_aes"
		private const val PREFS_NAME = "coln_secure_session_prefs"
		private const val PREF_CIPHERTEXT = "session_ciphertext_b64"
		private const val PREF_IV = "session_iv_b64"
		private const val GCM_TAG_BITS = 128
		private const val IV_BYTES = 12
	}

	override fun getPluginName(): String = PLUGIN_NAME

	private fun appContext(): Context = godot.requireContext().applicationContext

	private fun prefs(): SharedPreferences =
		appContext().getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

	private fun getOrCreateKey(): SecretKey {
		val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
		val existing = keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry
		if (existing != null) {
			return existing.secretKey
		}
		val keyGenerator = KeyGenerator.getInstance(
			KeyProperties.KEY_ALGORITHM_AES,
			KEYSTORE_PROVIDER,
		)
		val spec = KeyGenParameterSpec.Builder(
			KEY_ALIAS,
			KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
		)
			.setBlockModes(KeyProperties.BLOCK_MODE_GCM)
			.setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
			.setKeySize(256)
			.setRandomizedEncryptionRequired(true)
			.build()
		keyGenerator.init(spec)
		return keyGenerator.generateKey()
	}

	@UsedByGodot
	fun secure_store_session(jsonString: String): Boolean {
		if (jsonString.isEmpty()) {
			return false
		}
		return try {
			val key = getOrCreateKey()
			val cipher = Cipher.getInstance("AES/GCM/NoPadding")
			cipher.init(Cipher.ENCRYPT_MODE, key)
			val iv = cipher.iv
			val ciphertext = cipher.doFinal(jsonString.toByteArray(Charsets.UTF_8))
			prefs().edit()
				.putString(PREF_CIPHERTEXT, Base64.encodeToString(ciphertext, Base64.NO_WRAP))
				.putString(PREF_IV, Base64.encodeToString(iv, Base64.NO_WRAP))
				.apply()
			true
		} catch (_: Exception) {
			false
		}
	}

	@UsedByGodot
	fun secure_load_session(): String {
		return try {
			val prefs = prefs()
			val ctB64 = prefs.getString(PREF_CIPHERTEXT, null) ?: return ""
			val ivB64 = prefs.getString(PREF_IV, null) ?: return ""
			val key = getOrCreateKey()
			val cipher = Cipher.getInstance("AES/GCM/NoPadding")
			val iv = Base64.decode(ivB64, Base64.NO_WRAP)
			cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, iv))
			val plain = cipher.doFinal(Base64.decode(ctB64, Base64.NO_WRAP))
			String(plain, Charsets.UTF_8)
		} catch (_: Exception) {
			""
		}
	}

	@UsedByGodot
	fun secure_delete_session(): Boolean {
		return try {
			prefs().edit()
				.remove(PREF_CIPHERTEXT)
				.remove(PREF_IV)
				.apply()
			true
		} catch (_: Exception) {
			false
		}
	}

	@UsedByGodot
	fun secure_has_session(): Boolean {
		val prefs = prefs()
		return !prefs.getString(PREF_CIPHERTEXT, null).isNullOrEmpty() &&
			!prefs.getString(PREF_IV, null).isNullOrEmpty()
	}

	/** Intentionally does not expose Keystore key material. */
	@UsedByGodot
	fun secure_export_keystore_key(): String {
		return ""
	}
}
