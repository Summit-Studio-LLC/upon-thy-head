package dev.summitstudio.uponthyhead

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.InvalidKeyException
import java.security.KeyStore
import java.security.SecureRandom
import java.security.UnrecoverableKeyException
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Encrypts small secrets at rest in SharedPreferences using an AES-256-GCM key in AndroidKeyStore.
 * Recovers cleanly if the Keystore entry was invalidated or corrupted, and returns null when older
 * plaintext or damaged bytes do not authenticate.
 */
internal class KeystoreSecrets(private val alias: String) {
    @Synchronized
    private fun key(recreate: Boolean = false): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (recreate) {
            runCatching { ks.deleteEntry(alias) }
        } else {
            try {
                (ks.getKey(alias, null) as? SecretKey)?.let { return it }
            } catch (_: UnrecoverableKeyException) {
                runCatching { ks.deleteEntry(alias) }
            } catch (_: KeyPermanentlyInvalidatedException) {
                runCatching { ks.deleteEntry(alias) }
            }
        }
        val g = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        g.init(
            KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return g.generateKey()
    }

    fun wrap(value: ByteArray): String {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        try {
            c.init(Cipher.ENCRYPT_MODE, key())
        } catch (e: Exception) {
            if (e is UnrecoverableKeyException || e is KeyPermanentlyInvalidatedException || e is InvalidKeyException) {
                c.init(Cipher.ENCRYPT_MODE, key(recreate = true))
            } else {
                throw e
            }
        }
        return Base64.encodeToString(c.iv + c.doFinal(value), Base64.NO_WRAP)
    }

    fun unwrap(kept: String): ByteArray? = try {
        val all = Base64.decode(kept, Base64.NO_WRAP)
        if (all.size < 12 + 16) {
            null
        } else {
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, all.copyOfRange(0, 12)))
            c.doFinal(all, 12, all.size - 12)
        }
    } catch (_: UnrecoverableKeyException) {
        runCatching { key(recreate = true) }
        null
    } catch (_: KeyPermanentlyInvalidatedException) {
        runCatching { key(recreate = true) }
        null
    } catch (_: Exception) {
        null
    }
}

/**
 * Locking and opening a blessing for a link, and keeping each link's stop token, for
 * lib/share/link_crypto.dart on `upon_thy_head/link` (the iPhone's is ios/Runner/Link.swift).
 * The cipher is javax.crypto's AES/GCM/NoPadding exactly as website/PROTOCOL.md §3 says; nothing here
 * implements a cipher, and nothing here logs a key, a plaintext or a token.
 *
 * Stop tokens: each is locked with an AES key that lives in the Android Keystore (it never leaves
 * it) and the locked token is kept in this app's private preferences. The app's data is never
 * backed up (allowBackup="false"), and the Keystore key cannot be restored anywhere else.
 */
class LinkChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    private val random = SecureRandom()
    private val prefs by lazy { context.getSharedPreferences("links", Context.MODE_PRIVATE) }
    private val secrets = KeystoreSecrets(ALIAS)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "random" -> {
                    val n = call.argument<Int>("count") ?: 0
                    if (n !in 1..64) return result.error("random", "count", null)
                    result.success(ByteArray(n).also(random::nextBytes))
                }
                "seal" -> {
                    val plain = call.argument<ByteArray>("plain")
                    val key = call.argument<ByteArray>("key")
                    val nonce = call.argument<ByteArray>("nonce")
                    if (plain == null || key?.size != 32 || nonce?.size != 12) return result.error("seal", "bad arguments", null)
                    result.success(seal(plain, key, nonce))
                }
                "open" -> {
                    val locked = call.argument<ByteArray>("locked")
                    val key = call.argument<ByteArray>("key")
                    if (locked == null || key?.size != 32) return result.error("open", "bad arguments", null)
                    val plain = open(locked, key)
                    if (plain == null) result.error("locked", null, null) else result.success(plain)
                }
                "secretPut" -> {
                    val name = call.argument<String>("name") ?: return result.error("secret", "bad arguments", null)
                    val value = call.argument<String>("value") ?: return result.error("secret", "bad arguments", null)
                    prefs.edit().putString(name, secrets.wrap(value.toByteArray(Charsets.UTF_8))).commit()
                    result.success(null)
                }
                "secretGet" -> {
                    val kept = prefs.getString(call.argument<String>("name") ?: "", null)
                    result.success(kept?.let { secrets.unwrap(it)?.toString(Charsets.UTF_8) })
                }
                "secretDelete" -> {
                    prefs.edit().remove(call.argument<String>("name") ?: "").commit()
                    result.success(null)
                }
                "secretNames" -> result.success(prefs.all.keys.sorted())
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error(call.method, e.javaClass.simpleName, null)
        }
    }

    companion object {
        const val VERSION: Byte = 1
        private const val ALIAS = "upon_thy_head.links"

        /** 0x01 ‖ nonce ‖ ciphertext ‖ tag, with the byte 0x01 as additional data. */
        fun seal(plain: ByteArray, key: ByteArray, nonce: ByteArray): ByteArray {
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
            c.updateAAD(byteArrayOf(VERSION))
            return byteArrayOf(VERSION) + nonce + c.doFinal(plain)
        }

        /** The plaintext, or null when it does not authenticate. */
        fun open(locked: ByteArray, key: ByteArray): ByteArray? {
            if (locked.size < 1 + 12 + 16) return null
            return try {
                val c = Cipher.getInstance("AES/GCM/NoPadding")
                c.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, locked.copyOfRange(1, 13)))
                c.updateAAD(byteArrayOf(locked[0]))
                c.doFinal(locked, 13, locked.size - 13)
            } catch (_: AEADBadTagException) {
                null
            } catch (_: Exception) {
                null
            }
        }
    }
}
