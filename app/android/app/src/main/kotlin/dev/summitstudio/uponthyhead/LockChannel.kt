package dev.summitstudio.uponthyhead

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricManager.Authenticators.BIOMETRIC_STRONG
import android.hardware.biometrics.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import android.hardware.biometrics.BiometricPrompt
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import android.view.View
import android.view.ViewGroup
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The app lock and the recent-apps cover, for lib/lock/lock.dart, on `upon_thy_head/lock` (the
 * iPhone's is ios/Runner/Privacy.swift, `LockChannel`; the Dart side and its rules are shared).
 *
 * Methods (Dart → Android):
 *  - `method` → "fingerprint" when a strong (class 3) biometric is enrolled and the phone has a
 *    fingerprint reader, "passcode" when only the screen lock (PIN, pattern or password) can open
 *    it, "none" when the phone has no screen lock at all, so the app cannot lock.
 *  - `authenticate` {reason} → true when the person proved it is them. One system prompt allows a
 *    strong biometric or the screen lock (`BIOMETRIC_STRONG | DEVICE_CREDENTIAL`). Cancelled or
 *    failed: false. Too many wrong fingerprints is Android's own (it falls back to the screen lock).
 *  - `biometry` → {type: "fingerprint" | "none", state: "ok" | "noPasscode", passcode: bool}
 *  - `cover` {on}: recent apps never shows the app ([Activity.setRecentsScreenshotEnabled] false),
 *    and the plain ground colour is laid over the app as it leaves, lifted on its return once Dart
 *    has answered `active` (so a lock decided there is drawn before anything shows again).
 *  - `version`, `openSettings` (this app's page), `openSecurity` (the phone's own screen-lock settings)
 *  - `debugCovered` → whether the cover is wanted
 * Events (Android → Dart): `active` {away, background}: the app is in front again after [away]
 * seconds out of sight. Not sent for the moment the unlock prompt itself took the screen.
 *
 * The platform's own BiometricPrompt (android.hardware.biometrics, Android 9+, with
 * `setAllowedAuthenticators` from 11) does everything AndroidX's does at Android 13, needs no
 * dependency, and works from a plain FlutterActivity (AndroidX's needs a FragmentActivity).
 */
class LockChannel(private val activity: () -> Activity?, private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        private const val TAG = "lock"
        var channel: MethodChannel? = null
        /** The cover is wanted (the lock is on). */
        var coverOn = false
        /** The unlock prompt or one of Android's permission questions is up: losing the screen to it
         *  is not leaving the app, and it is never covered. */
        var prompting = false
        /** The unlock prompt itself is up (set only by [authenticate]). */
        private var promptUp = false

        /**
         * An unlock asked for while one of Android's questions (or the share sheet) was up: held back,
         * so two system dialogs are never up at once, and opened as soon as the question is answered
         * and the app has the screen again ([questionGone]). The locked return asks automatically,
         * so without this the person had to tap Unlock after answering the question.
         */
        private var heldBack: (() -> Unit)? = null

        /** The question is gone and the window has focus: open a held-back unlock prompt. */
        fun questionGone(a: Activity) {
            Handler(Looper.getMainLooper()).post {
                if (prompting || !a.hasWindowFocus()) return@post
                val p = heldBack ?: return@post
                heldBack = null
                p()
            }
        }

        /** Covered on losing focus (recent apps, the notification shade), not yet out of sight. */
        private var blurred = false
        /** When the app went out of sight (elapsed realtime), or null. */
        private var leftAt: Long? = null
        private var cover: View? = null
        private const val GROUND = 0xFF0B0907.toInt()

        /**
         * MainActivity.onStop: the activity is truly off the screen. Always counted as leaving, even
         * with a permission question or the unlock prompt up (those only pause the activity or take
         * its focus; they never stop it, so [prompting] is not consulted here). Otherwise Home pressed
         * over Android's location question left the app open, uncovered, for as long as it was away.
         */
        fun left(a: Activity) {
            leftAt = SystemClock.elapsedRealtime()
            place(a)
        }

        /** MainActivity.onStart: tell Dart, and lift the cover once it answers. */
        fun came(a: Activity) {
            blurred = false
            val at = leftAt ?: return lift()
            leftAt = null
            debugSlow = slowActive(a)
            tell((SystemClock.elapsedRealtime() - at) / 1000.0, true)
        }

        /**
         * MainActivity.onWindowFocusChanged, the iPhone's "will deactivate": the Pixel's recent apps
         * shows the app itself, live, as it opens (no snapshot is taken, so
         * [Activity.setRecentsScreenshotEnabled] alone does not hide it), and the window only loses
         * focus. With the lock on the ground covers it then; on focus coming back without the app
         * having left the screen, Dart is told (away 0, not background) and the cover lifted.
         */
        fun focus(a: Activity, has: Boolean) {
            if (!has) {
                if (prompting || !coverOn) return
                blurred = true
                place(a)
                return
            }
            questionGone(a)
            if (!blurred) return
            blurred = false
            if (leftAt == null) tell(0.0, false)
        }

        /**
         * Away for less than this, a return can never lock: half of `lockAfter` (60 s,
         * lib/lock/lock.dart), so that a clock read a little early or late here, or a rule that
         * changes there, can never turn a return that should lock into one that lifts without asking.
         */
        const val SURELY_UNLOCKED_S = 30.0

        /** Debug builds only: how long to hold back `active` (the file files/slow_active holds the
         *  milliseconds; put there by tool/android_lock.py to stand for a busy Dart side). */
        private var debugSlow = 0L

        private fun slowActive(a: Activity): Long {
            if ((a.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) == 0) return 0
            return try { java.io.File(a.filesDir, "slow_active").readText().trim().toLong() } catch (e: Exception) { 0 }
        }

        /** Which answer to Dart's `active` was the last asked; an older one never lifts a newer cover. */
        private var asked = 0

        /**
         * The number of a return that may lock (from the background, away [SURELY_UNLOCKED_S] or
         * more) that Dart has not yet answered with success, or 0. Sticky: a later call (the shade
         * pulled down and closed while Dart is busy sends `tell(0, false)`) never clears it, so it can
         * never lift the cover without an answer. Cleared only by a success for that call or a later
         * one: Dart handles the channel's calls in order, so a later success means it was handled.
         */
        private var mayLockUnanswered = 0

        /**
         * Tell Dart the app is back, and lift the cover. It fails closed: lifted on Dart's answer
         * (however late), and without one (an error, no handler, or 1.5 s gone) only when this return
         * cannot be one that locks: not from the background, or away under [SURELY_UNLOCKED_S], and
         * no earlier return that may lock still waiting for its answer ([mayLockUnanswered]).
         */
        private fun tell(away: Double, background: Boolean) {
            val c = channel
            val mayLock = background && away >= SURELY_UNLOCKED_S
            if (c == null) {
                if (!mayLock && mayLockUnanswered == 0) lift()
                return
            }
            val n = ++asked
            if (mayLock) mayLockUnanswered = n
            var answered = false
            val unanswered = { if (!answered && n == asked && mayLockUnanswered == 0) lift() }
            val send = {
                c.invokeMethod("active", mapOf("away" to away, "background" to background), object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        answered = true
                        if (mayLockUnanswered != 0 && n >= mayLockUnanswered) mayLockUnanswered = 0
                        if (n == asked) lift()
                    }
                    override fun error(code: String, message: String?, details: Any?) = unanswered()
                    override fun notImplemented() = unanswered()
                })
            }
            val main = Handler(Looper.getMainLooper())
            if (debugSlow > 0) main.postDelayed({ send() }, debugSlow) else send()
            main.postDelayed({ unanswered() }, 1500)
        }

        /** The plain ground over everything, invisible to accessibility. */
        private fun place(a: Activity) {
            if (!coverOn || cover != null) return
            val v = View(a).apply {
                setBackgroundColor(GROUND)
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
                isClickable = true
            }
            a.addContentView(v, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
            cover = v
        }

        private fun lift() {
            val v = cover ?: return
            (v.parent as? ViewGroup)?.removeView(v)
            cover = null
        }

        /** Applied again to each new activity (MainActivity.onCreate). */
        fun apply(a: Activity) = a.setRecentsScreenshotEnabled(!coverOn)
    }

    private val keyguard = context.getSystemService(KeyguardManager::class.java)
    private val biometrics = context.getSystemService(BiometricManager::class.java)

    private fun secure() = keyguard?.isDeviceSecure == true

    private fun strongFingerprint() =
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT) &&
            biometrics?.canAuthenticate(BIOMETRIC_STRONG) == BiometricManager.BIOMETRIC_SUCCESS

    private fun method() = when {
        !secure() -> "none"
        strongFingerprint() -> "fingerprint"
        else -> "passcode"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "method" -> result.success(method())
            "biometry" -> result.success(
                mapOf(
                    "type" to if (strongFingerprint()) "fingerprint" else "none",
                    "state" to if (secure()) "ok" else "noPasscode",
                    "passcode" to secure(),
                ),
            )
            "authenticate" -> authenticate(call.argument<String>("reason") ?: "Unlock", result)
            "cover" -> {
                coverOn = call.argument<Boolean>("on") ?: false
                activity()?.let(::apply)
                if (!coverOn) lift()
                result.success(null)
            }
            "debugCovered" -> result.success(coverOn)
            "version" -> {
                val info = context.packageManager.getPackageInfo(context.packageName, 0)
                result.success("${info.versionName} (${info.longVersionCode})")
            }
            "openSettings" -> {
                context.startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.fromParts("package", context.packageName, null))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                result.success(null)
            }
            "openSecurity" -> {
                context.startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(null)
            }
            // the iPhone's Face ID question; Android has none (the first run proves the lock with one unlock)
            "askBiometrics" -> onMethodCall(MethodCall("biometry", null), result)
            else -> result.notImplemented()
        }
    }

    private fun authenticate(reason: String, result: MethodChannel.Result) {
        val a = activity()
        if (a == null || !secure() || promptUp) return result.success(false)
        if (prompting) {
            // a permission question is up: ask once it is answered, never over it
            heldBack?.let { result.success(false) } ?: run {
                heldBack = { authenticate(reason, result) }
            }
            return
        }
        var answered = false
        val answer = { ok: Boolean ->
            if (!answered) {
                answered = true
                prompting = false
                promptUp = false
                result.success(ok)
            }
        }
        val prompt = BiometricPrompt.Builder(a)
            .setTitle(reason)
            .setAllowedAuthenticators(BIOMETRIC_STRONG or DEVICE_CREDENTIAL)
            .build()
        prompting = true
        promptUp = true
        try {
            prompt.authenticate(CancellationSignal(), a.mainExecutor, object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) = answer(true)
                override fun onAuthenticationError(code: Int, message: CharSequence) {
                    Log.i(TAG, "prompt ended: $code $message")
                    answer(false)
                }
                // a wrong fingerprint: the prompt stays up and Android counts; nothing to do here
                override fun onAuthenticationFailed() { Log.i(TAG, "not recognised") }
            })
        } catch (e: Exception) {
            Log.w(TAG, "prompt: $e")
            answer(false)
        }
    }
}
