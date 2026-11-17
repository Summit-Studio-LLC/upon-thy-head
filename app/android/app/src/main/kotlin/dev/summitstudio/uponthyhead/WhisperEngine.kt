package dev.summitstudio.uponthyhead

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Process
import android.util.Log
import java.io.File
import java.nio.ByteOrder

/**
 * whisper.cpp, built by tool/android_whisper.sh (android/app/src/main/cpp/uth_whisper.cpp). Two
 * arm64 builds: the one measured in docs/android-plan.md 3.5 (ARMv8.2 with dot product and half
 * floats) where the processor has them, and a plain ARMv8 one otherwise; x86_64 for Chromebooks.
 */
object WhisperNative {
    private const val TAG = "whisper"

    /** Null when loaded; otherwise why not (no library for this processor, e.g. a 32-bit phone). */
    val problem: String? by lazy {
        val features = runCatching { File("/proc/cpuinfo").readText() }.getOrDefault("")
        val v82 = Regex("""\basimddp\b""").containsMatchIn(features) && Regex("""\bfphp\b""").containsMatchIn(features)
        val names = if (v82) listOf("uth_whisper_v82", "uth_whisper") else listOf("uth_whisper")
        var why: String? = "no library"
        for (n in names) {
            try {
                System.loadLibrary(n)
                Log.i(TAG, "loaded lib$n.so")
                why = null
                break
            } catch (e: Throwable) {
                why = "lib$n.so: $e"
            }
        }
        why
    }

    @JvmStatic external fun load(path: String): Long
    @JvmStatic external fun free(ctx: Long)
    @JvmStatic external fun abort(on: Boolean)
    @JvmStatic external fun resample(pcm: ShortArray, rate: Int): FloatArray
    @JvmStatic external fun speech(vadModel: String, pcm: FloatArray, threads: Int): FloatArray?
    @JvmStatic external fun transcribe(ctx: Long, pcm: FloatArray, language: String, threads: Int, temperature: Float, noSpeech: FloatArray): ByteArray?
    @JvmStatic external fun info(): String
}

/**
 * One engine that writes words from a stretch of recorded speech. Whisper is the only one today;
 * another (ML Kit, once a real phone can prove it) would answer the same three questions.
 */
interface SpeechEngine {
    /** Null when this phone can write [language] now; otherwise "later" (the model is still to be
     *  downloaded) or "unavailable" (this phone cannot run the engine at all). */
    fun cannot(language: String): String?

    /** The recording at [path] as 16 kHz samples, with its stretches of speech. */
    fun prepare(path: File): Prepared

    /** The words of one stretch, alone, with nothing carried over from any other. */
    fun piece(prepared: Prepared, start: Double, end: Double, language: String, temperature: Float): Piece

    /** Let go of the model and the decoded audio. */
    fun release()

    class Prepared(val path: String, val samples: FloatArray, val stretches: FloatArray) {
        val seconds get() = samples.size / 16000.0
    }

    class Piece(val text: String, val noSpeech: Float, val ms: Long)
}

/**
 * Whisper base on the phone (docs/android-plan.md 3.5): the recording decoded here, brought to
 * 16 kHz, cut at its silences by the Silero model, each stretch read alone.
 */
class WhisperEngine(private val context: Context, private val model: () -> File?) : SpeechEngine {
    companion object {
        private const val TAG = "whisper"
        private const val VAD_ASSET = "whisper/ggml-silero-v5.1.2.bin"

        /** Whisper's threads: four, as measured (3.5), fewer on a phone with fewer cores. */
        val threads = Runtime.getRuntime().availableProcessors().coerceIn(1, 4)
    }

    private var ctx = 0L
    private var loadedFrom: String? = null
    private var cached: SpeechEngine.Prepared? = null

    override fun cannot(language: String): String? = when {
        WhisperNative.problem != null -> "unavailable"
        language != "en" && language != "es" -> "unavailable"
        model() == null -> "later"
        else -> null
    }

    /** The Silero model, from the APK's assets into the app's own no-backup folder. */
    private fun vadModel(): File {
        val f = File(context.noBackupFilesDir, VAD_ASSET)
        if (f.exists()) return f
        f.parentFile?.mkdirs()
        val tmp = File(f.path + ".tmp")
        context.assets.open(VAD_ASSET).use { i -> tmp.outputStream().use { o -> i.copyTo(o) } }
        tmp.renameTo(f)
        return f
    }

    @Synchronized
    override fun prepare(path: File): SpeechEngine.Prepared {
        cached?.let { if (it.path == path.path) return it }
        cached = null
        Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
        val t0 = System.currentTimeMillis()
        val (pcm, rate) = decode(path)
        val samples = WhisperNative.resample(pcm, rate)
        val t1 = System.currentTimeMillis()
        val stretches = WhisperNative.speech(vadModel().path, samples, threads) ?: throw IllegalStateException("the silence model failed")
        val t2 = System.currentTimeMillis()
        Log.i(TAG, "prepared ${path.name}: ${"%.1f".format(samples.size / 16000.0)} s, ${stretches.size / 2} stretches; decoded in ${t1 - t0} ms, cut in ${t2 - t1} ms")
        return SpeechEngine.Prepared(path.path, samples, stretches).also { cached = it }
    }

    @Synchronized
    override fun piece(prepared: SpeechEngine.Prepared, start: Double, end: Double, language: String, temperature: Float): SpeechEngine.Piece {
        Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
        val m = model() ?: throw IllegalStateException("later")
        if (ctx == 0L || loadedFrom != m.path) {
            if (ctx != 0L) WhisperNative.free(ctx)
            ctx = 0L
            val t = System.currentTimeMillis()
            ctx = WhisperNative.load(m.path)
            if (ctx == 0L) throw IllegalStateException("the model could not be loaded")
            loadedFrom = m.path
            Log.i(TAG, "model loaded in ${System.currentTimeMillis() - t} ms; ${WhisperNative.info()}")
        }
        val a = (start * 16000).toInt().coerceIn(0, prepared.samples.size)
        val b = (end * 16000).toInt().coerceIn(a, prepared.samples.size)
        val slice = prepared.samples.copyOfRange(a, b)
        val ns = FloatArray(1)
        val t = System.currentTimeMillis()
        val bytes = WhisperNative.transcribe(ctx, slice, language, threads, temperature, ns) ?: throw IllegalStateException("whisper failed")
        return SpeechEngine.Piece(String(bytes, Charsets.UTF_8), ns[0], System.currentTimeMillis() - t)
    }

    @Synchronized
    override fun release() {
        if (ctx != 0L) WhisperNative.free(ctx)
        ctx = 0L
        loadedFrom = null
        cached = null
    }

    /** The whole recording as 16-bit mono samples and their rate (the app's .m4a: AAC, 32 kHz). */
    private fun decode(file: File): Pair<ShortArray, Int> {
        val ex = MediaExtractor()
        ex.setDataSource(file.path)
        val track = (0 until ex.trackCount).firstOrNull { ex.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true }
            ?: throw IllegalStateException("no audio in ${file.name}")
        ex.selectTrack(track)
        val format = ex.getTrackFormat(track)
        var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
        codec.configure(format, null, null, 0)
        codec.start()
        var out = ShortArray(1 shl 20)
        var n = 0
        val info = MediaCodec.BufferInfo()
        var inputDone = false
        try {
            while (true) {
                if (!inputDone) {
                    val i = codec.dequeueInputBuffer(10_000)
                    if (i >= 0) {
                        val buf = codec.getInputBuffer(i)!!
                        val size = ex.readSampleData(buf, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(i, 0, size, ex.sampleTime, 0)
                            ex.advance()
                        }
                    }
                }
                val o = codec.dequeueOutputBuffer(info, 10_000)
                if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    rate = codec.outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = codec.outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                } else if (o >= 0) {
                    val buf = codec.getOutputBuffer(o)!!.order(ByteOrder.LITTLE_ENDIAN)
                    buf.position(info.offset)
                    buf.limit(info.offset + info.size)
                    val s = buf.asShortBuffer()
                    val frames = s.remaining() / channels
                    if (n + frames > out.size) out = out.copyOf(maxOf(out.size * 2, n + frames))
                    for (f in 0 until frames) {
                        var acc = 0
                        for (c in 0 until channels) acc += s.get(f * channels + c)
                        out[n++] = (acc / channels).toShort()
                    }
                    codec.releaseOutputBuffer(o, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
        } finally {
            codec.stop()
            codec.release()
            ex.release()
        }
        return out.copyOf(n) to rate
    }
}
