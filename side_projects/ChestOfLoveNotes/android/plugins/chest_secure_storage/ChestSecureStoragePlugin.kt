package com.charoitegames.chestoflovenotes.securestorage

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Godot Android plugin: ChestSecureStorage
 *
 * AES-256-GCM encryption using a non-exportable Android Keystore key.
 * Only ciphertext, IV, and non-sensitive metadata are stored in private prefs.
 * Key material is never exposed to GDScript, logs, or SharedPreferences.
 */
class ChestSecureStoragePlugin(godot: Godot) : GodotPlugin(godot) {

	companion object {
		private const val TAG = "ChestSecureStorage"
		private const val PLUGIN_NAME = "ChestSecureStorage"
		private const val STORAGE_VERSION = 1
		private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
		private const val KEY_ALIAS = "ChestOfLoveNotesSessionKey"
		private const val PREFS_NAME = "coln_chest_secure_session_prefs"
		private const val PREF_CIPHERTEXT = "session_ciphertext_b64"
		private const val PREF_IV = "session_iv_b64"
		private const val PREF_VERSION = "storage_version"
		private const val PREF_OAUTH_CIPHERTEXT = "oauth_state_ciphertext_b64"
		private const val PREF_OAUTH_IV = "oauth_state_iv_b64"
		private const val GCM_TAG_BITS = 128
		private const val TRANSFORMATION = "AES/GCM/NoPadding"
	}

	override fun getPluginName(): String = PLUGIN_NAME

	private fun appContext(): Context {
		val ctx = godot.context ?: error("Godot context unavailable")
		return ctx.applicationContext
	}

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
	fun secure_storage_available(): Boolean {
		return try {
			getOrCreateKey()
			true
		} catch (e: Exception) {
			Log.w(TAG, "secure_storage_available failed: ${e.javaClass.simpleName}")
			false
		}
	}

	@UsedByGodot
	fun secure_storage_version(): Int = STORAGE_VERSION

	@UsedByGodot
	fun secure_store_session(jsonString: String): Boolean {
		if (jsonString.isEmpty()) {
			return false
		}
		return try {
			val key = getOrCreateKey()
			val cipher = Cipher.getInstance(TRANSFORMATION)
			cipher.init(Cipher.ENCRYPT_MODE, key)
			val iv = cipher.iv
			val ciphertext = cipher.doFinal(jsonString.toByteArray(Charsets.UTF_8))
			// commit() — must flush before process death after sign-in.
			val ok = prefs().edit()
				.putString(PREF_CIPHERTEXT, Base64.encodeToString(ciphertext, Base64.NO_WRAP))
				.putString(PREF_IV, Base64.encodeToString(iv, Base64.NO_WRAP))
				.putInt(PREF_VERSION, STORAGE_VERSION)
				.commit()
			if (!ok) {
				Log.w(TAG, "secure_store_session commit returned false")
			}
			ok
		} catch (e: Exception) {
			Log.w(TAG, "secure_store_session failed: ${e.javaClass.simpleName}")
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
			val cipher = Cipher.getInstance(TRANSFORMATION)
			val iv = Base64.decode(ivB64, Base64.NO_WRAP)
			cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, iv))
			val plain = cipher.doFinal(Base64.decode(ctB64, Base64.NO_WRAP))
			String(plain, Charsets.UTF_8)
		} catch (e: Exception) {
			// Missing Keystore key / corrupt ciphertext / device transfer → empty.
			Log.w(TAG, "secure_load_session failed: ${e.javaClass.simpleName}")
			try {
				prefs().edit()
					.remove(PREF_CIPHERTEXT)
					.remove(PREF_IV)
					.commit()
			} catch (_: Exception) {
				// ignore cleanup failures
			}
			""
		}
	}

	@UsedByGodot
	fun secure_delete_session(): Boolean {
		return try {
			prefs().edit()
				.remove(PREF_CIPHERTEXT)
				.remove(PREF_IV)
				.remove(PREF_VERSION)
				.commit()
		} catch (e: Exception) {
			Log.w(TAG, "secure_delete_session failed: ${e.javaClass.simpleName}")
			false
		}
	}

	@UsedByGodot
	fun secure_has_session(): Boolean {
		val prefs = prefs()
		return !prefs.getString(PREF_CIPHERTEXT, null).isNullOrEmpty() &&
			!prefs.getString(PREF_IV, null).isNullOrEmpty()
	}

	/**
	 * Short-lived encrypted PKCE transaction state. This is deliberately separate
	 * from the signed-in session so it survives Android process death while the
	 * browser is open without changing Keep Me Signed In semantics.
	 */
	@UsedByGodot
	fun secure_store_oauth_state(jsonString: String): Boolean {
		if (jsonString.isEmpty()) return false
		return try {
			val key = getOrCreateKey()
			val cipher = Cipher.getInstance(TRANSFORMATION)
			cipher.init(Cipher.ENCRYPT_MODE, key)
			val iv = cipher.iv
			val ciphertext = cipher.doFinal(jsonString.toByteArray(Charsets.UTF_8))
			val ok = prefs().edit()
				.putString(PREF_OAUTH_CIPHERTEXT, Base64.encodeToString(ciphertext, Base64.NO_WRAP))
				.putString(PREF_OAUTH_IV, Base64.encodeToString(iv, Base64.NO_WRAP))
				.commit()
			if (!ok) Log.w(TAG, "secure_store_oauth_state commit returned false")
			ok
		} catch (e: Exception) {
			Log.w(TAG, "secure_store_oauth_state failed: ${e.javaClass.simpleName}")
			false
		}
	}

	@UsedByGodot
	fun secure_load_oauth_state(): String {
		return try {
			val prefs = prefs()
			val ctB64 = prefs.getString(PREF_OAUTH_CIPHERTEXT, null) ?: return ""
			val ivB64 = prefs.getString(PREF_OAUTH_IV, null) ?: return ""
			val key = getOrCreateKey()
			val cipher = Cipher.getInstance(TRANSFORMATION)
			val iv = Base64.decode(ivB64, Base64.NO_WRAP)
			cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, iv))
			val plain = cipher.doFinal(Base64.decode(ctB64, Base64.NO_WRAP))
			String(plain, Charsets.UTF_8)
		} catch (e: Exception) {
			Log.w(TAG, "secure_load_oauth_state failed: ${e.javaClass.simpleName}")
			try {
				prefs().edit()
					.remove(PREF_OAUTH_CIPHERTEXT)
					.remove(PREF_OAUTH_IV)
					.commit()
			} catch (_: Exception) {
				// ignore cleanup failures
			}
			""
		}
	}

	@UsedByGodot
	fun secure_delete_oauth_state(): Boolean {
		return try {
			prefs().edit()
				.remove(PREF_OAUTH_CIPHERTEXT)
				.remove(PREF_OAUTH_IV)
				.commit()
		} catch (e: Exception) {
			Log.w(TAG, "secure_delete_oauth_state failed: ${e.javaClass.simpleName}")
			false
		}
	}

	@UsedByGodot
	fun secure_has_oauth_state(): Boolean {
		val prefs = prefs()
		return !prefs.getString(PREF_OAUTH_CIPHERTEXT, null).isNullOrEmpty() &&
			!prefs.getString(PREF_OAUTH_IV, null).isNullOrEmpty()
	}

	/** Intentionally never exposes Keystore key material to GDScript. */
	@UsedByGodot
	fun secure_export_keystore_key(): String = ""
}
