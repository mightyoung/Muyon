package com.mightyoung.muyon

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val preferences = getSharedPreferences("model_secrets", MODE_PRIVATE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.mightyoung.muyon/secrets")
            .setMethodCallHandler { call, result ->
                val reference = call.argument<String>("reference")
                if (reference == null || !reference.matches(Regex("[A-Za-z0-9_.-]{1,128}"))) {
                    result.error("invalid_reference", "Invalid credential reference", null)
                    return@setMethodCallHandler
                }
                try {
                    val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                    val alias = "muyon-model-secrets"
                    val key = if (keyStore.containsAlias(alias)) keyStore.getKey(alias, null) as SecretKey else {
                        KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
                            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
                        }.generateKey()
                    }
                    when (call.method) {
                        "read" -> {
                            val encoded = preferences.getString(reference, null)
                            if (encoded == null) result.success(null) else {
                                val parts = encoded.split(":")
                                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                                cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)))
                                cipher.updateAAD(reference.toByteArray(Charsets.UTF_8))
                                result.success(String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8))
                            }
                        }
                        "write" -> {
                            val value = call.argument<String>("value") ?: throw IllegalArgumentException()
                            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                            cipher.init(Cipher.ENCRYPT_MODE, key)
                            cipher.updateAAD(reference.toByteArray(Charsets.UTF_8))
                            val ciphertext = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
                            val encoded = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" + Base64.encodeToString(ciphertext, Base64.NO_WRAP)
                            if (!preferences.edit().putString(reference, encoded).commit()) throw IllegalStateException()
                            result.success(null)
                        }
                        "remove" -> {
                            if (!preferences.edit().remove(reference).commit()) throw IllegalStateException()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) { result.error("secret_store_failed", "System credential store unavailable", null) }
            }
    }
}
