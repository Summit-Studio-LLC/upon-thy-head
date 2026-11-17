package dev.summitstudio.uponthyhead

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * The recording, for lib/record/speech.dart, on the channel `upon_thy_head/speech`: the same method
 * names, arguments and events as the iPhone's (ios/Runner/SpeechChannel.swift), so the Dart side is
 * one code path.
 *
 * Methods (Dart → Android):
 *  - `permissions` → {"microphone": s, "speech": "granted", "notifications": s, "microphoneAskAgain": b}
 *    s is "granted", "denied" or "undetermined". Android has no speech permission (ML Kit needs
 *    none), so speech is always "granted". "denied" with microphoneAskAgain true means Android will
 *    still put its question once more; false means it will not ("Don't allow" twice, or "don't ask
 *    again"), and only the app's page in Settings can turn it on.
 *  - `requestPermissions` → the same, after putting whatever question Android will still put: the
 *    microphone, then (the first time only) notifications
 *  - `requestMicrophone`, `requestNotifications` → the same, after that one question (the first run)
 *  - `requestSpeech` → the same at once (nothing to ask)
 *  - `openSettings`: this app's page in Android's Settings
 *  - `start` {path}, `stop` → path, `cancel`, `recover` {path} → {"path", "seconds"} or null,
 *    `seconds` {path}: as on iPhone (SegmentRecorder, Adts)
 *  - `engine` → null, `describe`: the words are written through `upon_thy_head/words` (WordsChannel)
 *  - `transcribe`: not used on Android; see below
 *  - `debugInterrupt` {began}, `debugFeed` {path}: tests only, as on iPhone
 *  - `debugState` → {"recording", "service"}: tests only
 * Events (Android → Dart): `paused` {bool}, while the system has the microphone (a call, ringing,
 * another app).
 */
class SpeechChannel(private val activity: () -> Activity?, private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        private const val TAG = "speech"
        private const val ASK_MICROPHONE = 7101
        private const val ASK_NOTIFICATIONS = 7102

        /** One recorder for the process: it outlives the screen (the service keeps it running). */
        var recorder: SegmentRecorder? = null
            private set

        fun recorder(context: Context): SegmentRecorder =
            recorder ?: SegmentRecorder(context.applicationContext).also { recorder = it }

        /** The channel of the engine now showing, for the `paused` event. */
        var channel: MethodChannel? = null

        private val waiting = HashMap<Int, () -> Unit>()

        /** From MainActivity.onRequestPermissionsResult. */
        fun answered(code: Int) {
            waiting.remove(code)?.invoke()
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val prefs = context.getSharedPreferences("permissions", Context.MODE_PRIVATE)

    init {
        recorder(context).onPaused = { paused ->
            channel?.invokeMethod("paused", paused)
            RecordingService.refresh(context, paused)
        }
    }

    // ---- permissions ----

    private fun granted(p: String) = context.checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED

    /** Android will still show its question for [p]: never asked, or refused once. */
    private fun canAsk(p: String): Boolean {
        if (granted(p)) return false
        val a = activity()
        return !prefs.getBoolean(p, false) || (a != null && a.shouldShowRequestPermissionRationale(p))
    }

    private fun state(p: String) = when {
        granted(p) -> "granted"
        !prefs.getBoolean(p, false) -> "undetermined"
        else -> "denied"
    }

    private fun permissions(): Map<String, Any> = mapOf(
        "microphone" to state(Manifest.permission.RECORD_AUDIO),
        "speech" to "granted",
        "notifications" to state(Manifest.permission.POST_NOTIFICATIONS),
        "microphoneAskAgain" to (!granted(Manifest.permission.RECORD_AUDIO) && prefs.getBoolean(Manifest.permission.RECORD_AUDIO, false) &&
            canAsk(Manifest.permission.RECORD_AUDIO)),
    )

    /** Android's own question for [p], then [done]; at once when it will not ask. */
    private fun ask(p: String, code: Int, done: () -> Unit) {
        val a = activity()
        if (a == null || !canAsk(p)) return done()
        prefs.edit().putBoolean(p, true).apply()
        waiting.remove(code)?.invoke()
        waiting[code] = done
        LockChannel.prompting = true
        a.requestPermissions(arrayOf(p), code)
    }

    private fun askMicrophone(done: () -> Unit) = ask(Manifest.permission.RECORD_AUDIO, ASK_MICROPHONE, done)

    private fun askNotifications(done: () -> Unit) = ask(Manifest.permission.POST_NOTIFICATIONS, ASK_NOTIFICATIONS, done)

    // ---- the channel ----

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val rec = recorder(context)
        when (call.method) {
            "permissions" -> result.success(permissions())
            "requestPermissions" -> askMicrophone {
                // notifications only the first time, beside the microphone; refusing them changes
                // nothing about recording (RecordingService)
                if (!prefs.getBoolean(Manifest.permission.POST_NOTIFICATIONS, false)) {
                    askNotifications { result.success(permissions()) }
                } else {
                    result.success(permissions())
                }
            }
            "requestMicrophone" -> askMicrophone { result.success(permissions()) }
            "requestNotifications" -> askNotifications { result.success(permissions()) }
            "requestSpeech" -> result.success(permissions())
            "openSettings" -> {
                val a = activity() ?: context
                a.startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                result.success(null)
            }
            "engine" -> result.success(null)
            "describe" -> result.success(
                mapOf("platform" to "android", "engines" to listOf("whisper"), "words" to "upon_thy_head/words",
                    "library" to (WhisperNative.problem ?: "loaded")),
            )
            "start" -> {
                if (path == null) return result.error("args", "path", null)
                if (!granted(Manifest.permission.RECORD_AUDIO)) return result.error("record", "the microphone is not allowed", null)
                try {
                    rec.start(File(path))
                    RecordingService.start(context)
                    result.success(null)
                } catch (e: Exception) {
                    Log.e(TAG, "recording: could not start: $e")
                    RecordingService.stop(context)
                    result.error("record", e.toString(), null)
                }
            }
            "stop" -> rec.stop { r ->
                RecordingService.stop(context)
                r.fold(
                    { f ->
                        Log.i(TAG, "recording: joined ${f.name}, ${"%.2f".format(Adts.seconds(f))} s")
                        result.success(f.path)
                    },
                    { e -> result.error("record", e.toString(), null) },
                )
            }
            "cancel" -> {
                rec.cancel()
                RecordingService.stop(context)
                result.success(null)
            }
            "recover" -> {
                if (path == null) return result.error("args", "path", null)
                io.execute {
                    val r = runCatching { recover(File(path)) }
                    main.post {
                        r.fold(
                            { got -> result.success(got?.let { mapOf("path" to it.first.path, "seconds" to it.second) }) },
                            { e -> result.error("record", e.toString(), null) },
                        )
                    }
                }
            }
            "seconds" -> {
                if (path == null) return result.error("args", "path", null)
                io.execute {
                    val s = Adts.seconds(File(path))
                    main.post { result.success(s) }
                }
            }
            "transcribe" -> transcribe(path, call.argument<String>("language") ?: "en", result)
            "debugInterrupt" -> {
                rec.debugInterrupt(call.argument<Boolean>("began") ?: true)
                result.success(null)
            }
            "debugFeed" -> {
                rec.feed = path?.let(::File)
                result.success(null)
            }
            "debugState" -> result.success(mapOf("recording" to rec.recording, "service" to RecordingService.running))
            else -> result.notImplemented()
        }
    }

    /**
     * Not used on Android. The words are written from the recorded `.m4a` after Amen through the
     * channel `upon_thy_head/words` (WordsChannel.kt, driven by lib/record/android_words.dart, which
     * NativeSpeech.transcribe calls on Android), a piece at a time so its place is kept. Answers
     * "unavailable" if anything still calls it, which the Dart side reads as "not on this phone".
     */
    private fun transcribe(path: String?, language: String, result: MethodChannel.Result) {
        if (path == null) return result.error("args", "path", null)
        result.error("unavailable", "Android writes the words through upon_thy_head/words ($language)", null)
    }

    /**
     * At launch: the recording that would have ended at [target], if the app was closed before Amen.
     * As on iPhone: its parts are joined into [target] and removed; with no parts but a [target]
     * that plays, that is the recording; null when nothing was recorded. On a failure everything is
     * left on disk for the next launch.
     */
    private fun recover(target: File): Pair<File, Double>? {
        val parts = SegmentRecorder.partsOnDisk(target)
        val heard = parts.filter { Adts.seconds(it) > 0 }
        if (heard.isEmpty()) {
            parts.forEach { it.delete() }
            val s = Adts.seconds(target)
            if (s > 0) return target to s
            target.delete()
            return null
        }
        target.delete()
        Adts.join(heard, target)
        parts.forEach { it.delete() }
        val s = Adts.seconds(target)
        Log.i(TAG, "recovery: joined ${heard.size} part(s) into ${target.name}, ${"%.2f".format(s)} s")
        return target to s
    }
}
