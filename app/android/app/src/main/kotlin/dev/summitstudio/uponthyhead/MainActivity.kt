package dev.summitstudio.uponthyhead

import android.content.Intent
import android.content.pm.ActivityInfo
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The Android app: the Flutter view, edge to edge, and the native side of every channel the Dart
 * code calls (the iPhone's are the Swift files in ios/Runner).
 *
 * Built so far: keeping the screen awake while a recording listens, the version, and opening this
 * app's page in the system Settings. Everything else is a stand-in that answers safely, so nothing
 * crashes and nothing pretends to work: see [NotYet] and "Stand-ins" in docs/android-plan.md, which
 * names the task that replaces each.
 */
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Drawn under the status and navigation bars (Android 15 and later insist; this makes 13
        // and 14 the same). Flutter reports the bars' sizes as padding, as on iPhone.
        window.setDecorFitsSystemWindows(false)
        super.onCreate(savedInstanceState)
        // Upright on phones; tablets turn freely, as the iPad does. (Android 16 ignores a fixed
        // orientation on large screens anyway.)
        if (resources.configuration.smallestScreenWidthDp < 600) {
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val m = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(m, "upon_thy_head/keep_awake").setMethodCallHandler(::keepAwake)
        MethodChannel(m, "upon_thy_head/speech").setMethodCallHandler(NotYet::speech)
        MethodChannel(m, "upon_thy_head/lock").setMethodCallHandler(::lock)
        MethodChannel(m, "upon_thy_head/location").setMethodCallHandler(NotYet::location)
        MethodChannel(m, "upon_thy_head/player").setMethodCallHandler(NotYet::player)
        MethodChannel(m, "upon_thy_head/share").setMethodCallHandler(NotYet::share)
        MethodChannel(m, "upon_thy_head/check").setMethodCallHandler(NotYet::check)
        // upon_thy_head/language_menu/<id> is never called here: on Android the Dart side draws the
        // language menu itself (lib/record/language_menu.dart).
    }

    /** lib/record/keep_awake.dart: the screen stays on while a recording listens. */
    private fun keepAwake(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "get" -> result.success(
                (window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) != 0,
            )
            "set" -> {
                if (call.arguments == true) {
                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** lib/lock/lock.dart and the first run. Only the version and Settings are real so far. */
    private fun lock(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "version" -> {
                val info = packageManager.getPackageInfo(packageName, 0)
                result.success("${info.versionName} (${info.longVersionCode})")
            }
            "openSettings" -> {
                startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                result.success(null)
            }
            else -> NotYet.lock(call, result)
        }
    }
}

/**
 * What Android cannot do yet, answered the way the Dart side's "not available" paths expect. Each
 * answer is the iPhone channel's own shape (same method names and keys) with the value that means
 * "this phone cannot", never one that means "done". Error code "unavailable" is the one the Dart
 * side already reads as "not on this phone" (lib/record/speech.dart).
 */
object NotYet {
    private fun no(result: MethodChannel.Result, what: String) =
        result.error("unavailable", "$what is not built on Android yet", null)

    /** Recording and speech: docs/android-plan.md tasks 4 to 10. */
    fun speech(call: MethodCall, result: MethodChannel.Result) {
        val none = mapOf("microphone" to "unavailable", "speech" to "unavailable")
        when (call.method) {
            "permissions", "requestPermissions", "requestMicrophone", "requestSpeech" -> result.success(none)
            "start", "stop", "transcribe" -> no(result, "Recording and speech")
            "cancel", "openSettings", "debugFeed", "debugInterrupt" -> result.success(null)
            "recover" -> result.success(null)
            "seconds" -> result.success(0.0)
            "engine" -> result.success(null)
            "describe" -> result.success(mapOf("platform" to "android", "engines" to emptyList<String>()))
            else -> result.notImplemented()
        }
    }

    /** The app lock and the recent-apps cover: task 11. "none" turns the lock off in the Dart side. */
    fun lock(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "method" -> result.success("none")
            "authenticate" -> result.success(false)
            "biometry", "askBiometrics" -> result.success(mapOf("type" to "none", "state" to "unavailable", "passcode" to false))
            "cover" -> result.success(null)
            "debugCovered" -> result.success(false)
            else -> result.notImplemented()
        }
    }

    /** Approximate location: task 12. "restricted" makes every blessing use the Salt Lake Temple. */
    fun location(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status", "request" -> result.success("restricted")
            "locate" -> result.success(null)
            else -> result.notImplemented()
        }
    }

    /** Listening back on the review page: task 18 (and the plain player before it). */
    fun player(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "load" -> no(result, "Playback")
            "play" -> result.success(false)
            "pause", "seek", "unload" -> result.success(null)
            "position" -> result.success(mapOf("position" to 0.0, "duration" to 0.0, "playing" to false))
            else -> result.notImplemented()
        }
    }

    /** Sharing and receiving blessings: tasks 13 and 14. */
    fun share(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "text", "pdf", "file" -> no(result, "Sharing")
            "receiving" -> result.success(emptyList<Any>())
            "dismiss", "clean" -> result.success(null)
            "debugShowing" -> result.success(false)
            "debugPaper" -> result.success("")
            "debugItems", "debugReceivedLeft" -> result.success(emptyList<Any>())
            else -> result.notImplemented()
        }
    }

    /** The phone check page (test builds only): an Android version is its own task. */
    fun check(call: MethodCall, result: MethodChannel.Result) = no(result, "The phone check")
}
