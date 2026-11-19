package dev.summitstudio.uponthyhead

import android.content.Context
import android.util.Base64
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenProvider
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

/**
 * Proof that a request to make a link comes from this app, for lib/share/proof.dart, on
 * `upon_thy_head/proof` (website/PROTOCOL.md §4, "Proof of the app"). Google's Play Integrity,
 * standard request, bound to the service's challenge by requestHash = SHA-256(challenge) as
 * base64url without padding. The Cloud project number comes from the service with the challenge;
 * with none (Play Integrity not set up yet) no proof is asked for. The pass the service gives back
 * is locked with an Android Keystore key and kept in this app's private preferences (never backed
 * up: res/xml/backup_rules.xml). Nothing here logs a challenge, token or pass.
 *
 *  - `prove` {challenge, project} → {platform: "android", token}, or null
 *  - `passGet` → the kept pass or null; `passPut` {value} keeps it (null forgets it)
 */
class ProofChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        private const val ALIAS = "upon_thy_head.proof"
        private val providers = HashMap<Long, StandardIntegrityTokenProvider>()

        @Synchronized
        private fun cachedProvider(number: Long): StandardIntegrityTokenProvider? = providers[number]

        @Synchronized
        private fun putProvider(number: Long, provider: StandardIntegrityTokenProvider) {
            providers[number] = provider
        }

        @Synchronized
        private fun clearProvider(number: Long, failed: StandardIntegrityTokenProvider) {
            if (providers[number] === failed) providers.remove(number)
        }
    }

    private val prefs get() = context.getSharedPreferences("proof", Context.MODE_PRIVATE)
    private val secrets = KeystoreSecrets(ALIAS)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prove" -> prove(call.argument<String>("challenge"), call.argument<String>("project"), result)
            "passGet" -> {
                val kept = prefs.getString("pass", null)
                if (kept == null) {
                    result.success(null)
                } else {
                    val opened = secrets.unwrap(kept)?.toString(Charsets.UTF_8)
                    if (opened == null) prefs.edit().remove("pass").apply()
                    result.success(opened)
                }
            }
            "passPut" -> {
                val value = call.argument<String>("value")
                if (value == null) {
                    prefs.edit().remove("pass").apply()
                } else {
                    val wrapped = runCatching { secrets.wrap(value.toByteArray(Charsets.UTF_8)) }.getOrNull()
                    if (wrapped != null) prefs.edit().putString("pass", wrapped).apply()
                    else prefs.edit().remove("pass").apply()
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun prove(challenge: String?, project: String?, result: MethodChannel.Result) {
        val number = project?.toLongOrNull()
        if (challenge == null || number == null) return result.success(null)
        val hash = Base64.encodeToString(
            MessageDigest.getInstance("SHA-256").digest(challenge.toByteArray(Charsets.UTF_8)),
            Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP,
        )
        var answered = false
        fun answer(value: Map<String, String>?) {
            if (answered) return
            answered = true
            result.success(value)
        }
        val req = StandardIntegrityTokenRequest.builder().setRequestHash(hash).build()
        fun prepareAndRequest() {
            IntegrityManagerFactory.createStandard(context.applicationContext)
                .prepareIntegrityToken(PrepareIntegrityTokenRequest.builder().setCloudProjectNumber(number).build())
                .addOnSuccessListener { provider ->
                    putProvider(number, provider)
                    provider.request(req)
                        .addOnSuccessListener { token -> answer(mapOf("platform" to "android", "token" to token.token())) }
                        .addOnFailureListener { clearProvider(number, provider); answer(null) }
                        .addOnCanceledListener { answer(null) }
                }
                .addOnFailureListener { answer(null) }
                .addOnCanceledListener { answer(null) }
        }
        try {
            val cached = cachedProvider(number)
            if (cached != null) {
                cached.request(req)
                    .addOnSuccessListener { token -> answer(mapOf("platform" to "android", "token" to token.token())) }
                    .addOnFailureListener {
                        clearProvider(number, cached)
                        try {
                            prepareAndRequest()
                        } catch (_: Exception) {
                            answer(null)
                        }
                    }
                    .addOnCanceledListener { answer(null) }
            } else {
                prepareAndRequest()
            }
        } catch (_: Exception) {
            answer(null)
        }
    }
}
