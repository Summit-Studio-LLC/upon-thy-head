package dev.summitstudio.uponthyhead

import android.content.Context
import android.util.Base64
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
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
 * is kept in this app's private preferences (never backed up: res/xml/backup_rules.xml).
 * Nothing here logs a challenge, token or pass.
 *
 *  - `prove` {challenge, project} → {platform: "android", token}, or null
 *  - `passGet` → the kept pass or null; `passPut` {value} keeps it (null forgets it)
 */
class ProofChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    private val prefs get() = context.getSharedPreferences("proof", Context.MODE_PRIVATE)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prove" -> prove(call.argument<String>("challenge"), call.argument<String>("project"), result)
            "passGet" -> result.success(prefs.getString("pass", null))
            "passPut" -> {
                val value = call.argument<String>("value")
                prefs.edit().apply { if (value == null) remove("pass") else putString("pass", value) }.apply()
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
        try {
            IntegrityManagerFactory.createStandard(context.applicationContext)
                .prepareIntegrityToken(PrepareIntegrityTokenRequest.builder().setCloudProjectNumber(number).build())
                .addOnSuccessListener { provider ->
                    provider.request(StandardIntegrityTokenRequest.builder().setRequestHash(hash).build())
                        .addOnSuccessListener { token -> answer(mapOf("platform" to "android", "token" to token.token())) }
                        .addOnFailureListener { answer(null) }
                }
                .addOnFailureListener { answer(null) }
        } catch (e: Exception) {
            answer(null)
        }
    }
}
