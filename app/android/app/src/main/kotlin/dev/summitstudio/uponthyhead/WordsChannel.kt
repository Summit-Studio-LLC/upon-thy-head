package dev.summitstudio.uponthyhead

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Writing the words on Android, for lib/record/android_words.dart, on the channel
 * `upon_thy_head/words` (Android only; iPhone writes its words in ios/Runner/OnDeviceSpeech.swift).
 * The Dart side runs the pieces, keeps its place, and joins the words, so the paragraph rule and
 * the guards against Whisper's faults are Dart, shared and tested there; this side decodes, cuts
 * and reads.
 *
 * Methods (Dart → Android); every model method takes the model's {name, url, bytes, sha256}:
 *  - `model` → ModelStore.describe; `download`, `cancel`, `remove` → the same, after doing so
 *  - `prepare` {path, language, model} → {"seconds", "stretches": [start0, end0, …]} (unpadded
 *    stretches of speech, seconds); errors "later" (no model yet), "unavailable" (this phone cannot)
 *  - `piece` {path, start, end, language, temperature, model} → {"text", "noSpeech", "ms"}; waits
 *    first while a recording is being made, so writing never competes with one
 *  - `release`: let go of the model and the decoded audio (the queue is empty)
 * Events (Android → Dart): `model` {the describe map}, as the download moves.
 */
class WordsChannel private constructor(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        private const val TAG = "words"
        var channel: MethodChannel? = null
        @Volatile private var current: WordsChannel? = null

        @Synchronized
        fun get(context: Context): WordsChannel =
            current ?: WordsChannel(context.applicationContext).also { current = it }
    }

    private val main = Handler(Looper.getMainLooper())
    private val work = Executors.newSingleThreadExecutor { r -> Thread(r, "words") }
    private val control = Executors.newSingleThreadExecutor { r -> Thread(r, "words-control") }
    private val models = ModelStore(context) { d -> channel?.invokeMethod("model", d) }
    @Volatile private var spec: ModelStore.Spec? = null
    private val engine: SpeechEngine = WhisperEngine(context) { spec?.let { models.ready(it) } }
    private val debuggable = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

    private fun specOf(call: MethodCall): ModelStore.Spec? {
        val m = call.argument<Map<String, Any?>>("model") ?: return null
        return ModelStore.Spec(m["name"] as String, m["url"] as String, (m["bytes"] as Number).toLong(), m["sha256"] as String)
            .also { spec = it }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val s = specOf(call)
        when (call.method) {
            "model" -> if (s == null) result.error("args", "model", null) else result.success(models.describe(s))
            "download" -> if (s == null) result.error("args", "model", null) else { models.download(s); result.success(models.describe(s)) }
            "cancel" -> if (s == null) result.error("args", "model", null) else control.execute {
                models.cancel(s)
                main.post { result.success(models.describe(s)) }
            }
            "remove" -> if (s == null) result.error("args", "model", null) else control.execute {
                if (WhisperNative.problem == null) WhisperNative.abort(true)
                engine.release()
                models.remove(s)
                main.post { result.success(models.describe(s)) }
            }
            "prepare" -> {
                val path = call.argument<String>("path") ?: return result.error("args", "path", null)
                val language = call.argument<String>("language") ?: "en"
                engine.cannot(language)?.let { return result.error(it, "cannot write $language now", null) }
                work.execute {
                    engine.cannot(language)?.let { code ->
                        main.post { result.error(code, "cannot write $language now", null) }
                        return@execute
                    }
                    val r = runCatching { engine.prepare(File(path)) }
                    main.post {
                        r.fold(
                            { p -> result.success(mapOf("seconds" to p.seconds, "stretches" to p.stretches.map { it.toDouble() })) },
                            { e ->
                                val code = engine.cannot(language)
                                    ?: if (e.message == "later" || e.message == "unavailable") e.message!! else "failed"
                                if (code == "failed") Log.e(TAG, "prepare: ${e.javaClass.simpleName}")
                                result.error(code, e.toString(), null)
                            },
                        )
                    }
                }
            }
            "piece" -> {
                val path = call.argument<String>("path") ?: return result.error("args", "path", null)
                val language = call.argument<String>("language") ?: "en"
                val start = call.argument<Double>("start") ?: 0.0
                val end = call.argument<Double>("end") ?: 0.0
                val temperature = (call.argument<Double>("temperature") ?: 0.0).toFloat()
                engine.cannot(language)?.let { return result.error(it, "cannot write $language now", null) }
                work.execute {
                    // a recording is being made: wait for Amen before reading on
                    var waited = 0L
                    while (SpeechChannel.recorder?.recording == true) {
                        Thread.sleep(250)
                        waited += 250
                    }
                    if (waited > 0 && debuggable) Log.i(TAG, "waited ${waited} ms for a recording to end")
                    engine.cannot(language)?.let { code ->
                        main.post { result.error(code, "cannot write $language now", null) }
                        return@execute
                    }
                    if (WhisperNative.problem == null) WhisperNative.abort(false)
                    val r = runCatching {
                        val p = engine.prepare(File(path))
                        engine.piece(p, start, end, language, temperature)
                    }
                    main.post {
                        r.fold(
                            { p -> result.success(mapOf("text" to p.text, "noSpeech" to p.noSpeech.toDouble(), "ms" to p.ms)) },
                            { e ->
                                val code = engine.cannot(language)
                                    ?: if (e.message == "later" || e.message == "unavailable") e.message!! else "failed"
                                if (code == "failed") Log.e(TAG, "piece: ${e.javaClass.simpleName}")
                                result.error(code, e.toString(), null)
                            },
                        )
                    }
                }
            }
            "release" -> work.execute {
                engine.release()
                main.post { result.success(null) }
            }
            "resume" -> {
                // at launch: a Download tapped before the app was closed carries on
                val w = models.wanted()
                if (w != null && s != null && w.url == s.url && models.ready(s) == null) models.download(s)
                result.success(if (s == null) null else models.describe(s))
            }
            else -> result.notImplemented()
        }
    }
}
