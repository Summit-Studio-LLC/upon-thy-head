package dev.summitstudio.uponthyhead

import android.content.Context
import android.content.pm.ApplicationInfo
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Process
import android.util.Log
import java.io.File
import java.nio.ByteOrder
import kotlin.math.ceil

/**
 * whisper.cpp, built by tool/android_whisper.sh (android/app/src/main/cpp/uth_whisper.cpp). Two
 * arm64 builds: the one measured in docs/android-plan.md 3.5 (ARMv8.2 with dot product and half
 * floats) where the processor has them, and a plain ARMv8 one otherwise; x86_64 for Chromebooks.
 */
object WhisperNative {
    private const val TAG = "whisper"

    @Volatile private var chosenLibrary: String? = null

    /** Every ARM core reports dotprod + scalar/vector fp16, so thread migration never hits SIGILL. */
    fun hasArmV82Features(cpuinfo: String): Boolean {
        val lines = cpuinfo.lineSequence()
            .map { it.trim() }
            .filter { it.startsWith("Features", ignoreCase = true) }
            .toList()
        if (lines.isEmpty()) return false
        return lines.all { line ->
            val tokens = line.substringAfter(':').trim().split(Regex("\\s+")).toSet()
            "asimddp" in tokens && "fphp" in tokens && "asimdhp" in tokens
        }
    }

    /** Null when loaded; otherwise why not (no library for this processor, e.g. a 32-bit phone). */
    val problem: String? by lazy {
        val cpuinfo = runCatching { File("/proc/cpuinfo").readText() }.getOrDefault("")
        val v82 = hasArmV82Features(cpuinfo)
        val names = if (v82) listOf("uth_whisper_v82", "uth_whisper") else listOf("uth_whisper")
        var why: String? = "no library"
        for (n in names) {
            try {
                System.loadLibrary(n)
                chosenLibrary = "lib$n.so"
                Log.i(TAG, "loaded lib$n.so")
                why = null
                break
            } catch (e: Throwable) {
                why = "lib$n.so: $e"
            }
        }
        why
    }

    val loadedLibrary: String?
        get() {
            problem
            return chosenLibrary
        }

    @JvmStatic external fun load(path: String): Long
    @JvmStatic external fun free(ctx: Long)
    @JvmStatic external fun abort(on: Boolean)
    @JvmStatic external fun resample(pcm: ShortArray, rate: Int): FloatArray?
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

    class Prepared(
        val path: String,
        val modified: Long,
        val bytes: Long,
        val samples: FloatArray,
        val stretches: FloatArray,
    ) {
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

        private tailrec fun gcd(a: Int, b: Int): Int = if (b == 0) a else gcd(b, a % b)
    }

    private val debuggable = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
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
        if (f.isFile && f.length() > 0L) return f
        f.parentFile?.mkdirs()
        val tmp = File(f.path + ".tmp")
        tmp.delete()
        context.assets.open(VAD_ASSET).use { i -> tmp.outputStream().use { o -> i.copyTo(o) } }
        if (tmp.length() <= 0L) {
            tmp.delete()
            throw IllegalStateException("the silence model asset is empty")
        }
        f.delete()
        if (!tmp.renameTo(f) || !f.isFile || f.length() <= 0L) {
            tmp.delete()
            throw IllegalStateException("could not place the silence model")
        }
        return f
    }

    @Synchronized
    override fun prepare(path: File): SpeechEngine.Prepared {
        val mod = path.lastModified()
        val len = path.length()
        cached?.let { if (it.path == path.path && it.modified == mod && it.bytes == len) return it }
        cached = null
        Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
        val t0 = System.currentTimeMillis()
        val samples = decodeAndResample(path)
        val t1 = System.currentTimeMillis()
        val stretches = WhisperNative.speech(vadModel().path, samples, threads) ?: throw IllegalStateException("the silence model failed")
        val t2 = System.currentTimeMillis()
        if (debuggable) {
            Log.i(TAG, "prepared ${path.name}: ${"%.1f".format(samples.size / 16000.0)} s, ${stretches.size / 2} stretches; decoded in ${t1 - t0} ms, cut in ${t2 - t1} ms")
        }
        return SpeechEngine.Prepared(path.path, mod, len, samples, stretches).also { cached = it }
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
            if (debuggable) Log.i(TAG, "model loaded in ${System.currentTimeMillis() - t} ms; ${WhisperNative.info()}")
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

    /**
     * Decodes [file] and resamples to 16 kHz floats in ~10-second chunks with an exact-phase halo on
     * each side, keeping temporary PCM/JNI buffers under ~2 MB even for an hour-long blessing.
     */
    private fun decodeAndResample(file: File): FloatArray {
        val ex = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            ex.setDataSource(file.path)
            val track = (0 until ex.trackCount).firstOrNull {
                ex.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: throw IllegalStateException("no audio in ${file.name}")
            ex.selectTrack(track)
            val format = ex.getTrackFormat(track)
            var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            if (rate <= 0 || channels <= 0) throw IllegalStateException("invalid audio format: $rate Hz, $channels ch")
            val durationUs = if (format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION) else 0L
            val estSamples = if (durationUs > 0L) {
                ((durationUs * 16_000L) / 1_000_000L + 16_000L).coerceIn(16_000L, 64_000_000L).toInt()
            } else {
                16_000 * 60
            }
            var out = FloatArray(estSamples)
            var outCount = 0

            fun appendFloats(src: FloatArray, srcOff: Int, len: Int) {
                if (len <= 0) return
                if (outCount + len > out.size) {
                    var next = out.size
                    while (next < outCount + len) {
                        next = (next.toLong() * 3 / 2 + 16_000L).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
                    }
                    out = out.copyOf(next)
                }
                System.arraycopy(src, srcOff, out, outCount, len)
                outCount += len
            }

            var chunkIn = 0
            var chunkOut = 0
            var haloIn = 0
            var haloOut = 0
            var pcmBuf = ShortArray(0)
            var bufLen = 0
            var hasLeftHalo = false

            fun initChunking(r: Int) {
                val g = gcd(r, 16_000)
                val unitIn = r / g
                val unitOut = 16_000 / g
                val reach = ceil(16.0 * maxOf(r / 16_000.0, 1.0)).toInt()
                val haloSteps = maxOf(1, (reach * 2 + unitIn - 1) / unitIn)
                val steps = maxOf(haloSteps * 4, (r.toLong() * 10 / unitIn).toInt())
                chunkIn = steps * unitIn
                chunkOut = steps * unitOut
                haloIn = haloSteps * unitIn
                haloOut = haloSteps * unitOut
                pcmBuf = ShortArray(chunkIn + haloIn * 2 + 32_768)
                bufLen = 0
                hasLeftHalo = false
            }

            fun flushReadyChunks(r: Int) {
                while (true) {
                    val leftIn = if (hasLeftHalo) haloIn else 0
                    val leftOut = if (hasLeftHalo) haloOut else 0
                    val needed = leftIn + chunkIn + haloIn
                    if (bufLen < needed) break
                    val win = pcmBuf.copyOfRange(0, needed)
                    val res = WhisperNative.resample(win, r) ?: throw IllegalStateException("resample failed")
                    val take = minOf(chunkOut, (res.size - leftOut).coerceAtLeast(0))
                    appendFloats(res, leftOut, take)
                    val shiftFrom = leftIn + chunkIn - haloIn
                    val remain = bufLen - shiftFrom
                    System.arraycopy(pcmBuf, shiftFrom, pcmBuf, 0, remain)
                    bufLen = remain
                    hasLeftHalo = true
                }
            }

            fun flushTail(r: Int) {
                val leftIn = if (hasLeftHalo) haloIn else 0
                val leftOut = if (hasLeftHalo) haloOut else 0
                if (bufLen > leftIn && chunkIn > 0) {
                    val win = pcmBuf.copyOfRange(0, bufLen)
                    val res = WhisperNative.resample(win, r) ?: throw IllegalStateException("resample failed")
                    val take = (res.size - leftOut).coerceAtLeast(0)
                    appendFloats(res, leftOut, take)
                }
                bufLen = 0
                hasLeftHalo = false
            }

            val c = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec = c
            c.configure(format, null, null, 0)
            c.start()

            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var idleSpins = 0
            while (true) {
                if (!inputDone) {
                    val i = c.dequeueInputBuffer(10_000)
                    if (i >= 0) {
                        val buf = c.getInputBuffer(i)!!
                        val size = ex.readSampleData(buf, 0)
                        if (size < 0) {
                            c.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            c.queueInputBuffer(i, 0, size, ex.sampleTime, 0)
                            ex.advance()
                        }
                    }
                }
                val o = c.dequeueOutputBuffer(info, 10_000)
                if (o == MediaCodec.INFO_TRY_AGAIN_LATER) {
                    if (inputDone && ++idleSpins >= 500) {
                        Log.w(TAG, "decoder stalled at end of stream")
                        break
                    }
                } else if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    idleSpins = 0
                    val newRate = c.outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    val newChannels = c.outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    if (newRate <= 0 || newChannels <= 0) {
                        throw IllegalStateException("invalid decoder output format: $newRate Hz, $newChannels ch")
                    }
                    if (newRate != rate && bufLen > 0) {
                        flushTail(rate)
                        pcmBuf = ShortArray(0)
                    }
                    rate = newRate
                    channels = newChannels
                } else if (o >= 0) {
                    idleSpins = 0
                    if (pcmBuf.isEmpty()) initChunking(rate)
                    val buf = c.getOutputBuffer(o)!!.order(ByteOrder.LITTLE_ENDIAN)
                    buf.position(info.offset)
                    buf.limit(info.offset + info.size)
                    val s = buf.asShortBuffer()
                    val frames = s.remaining() / channels
                    if (frames > 0) {
                        if (bufLen + frames > pcmBuf.size) {
                            pcmBuf = pcmBuf.copyOf(maxOf(pcmBuf.size * 2, bufLen + frames))
                        }
                        if (channels == 1) {
                            s.get(pcmBuf, bufLen, frames)
                            bufLen += frames
                        } else {
                            for (f in 0 until frames) {
                                var acc = 0
                                for (ch in 0 until channels) acc += s.get(f * channels + ch)
                                pcmBuf[bufLen++] = (acc / channels).toShort()
                            }
                        }
                        flushReadyChunks(rate)
                    }
                    c.releaseOutputBuffer(o, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
            flushTail(rate)
            return if (outCount == out.size) out else out.copyOf(outCount)
        } finally {
            runCatching { codec?.stop() }
            runCatching { codec?.release() }
            runCatching { ex.release() }
        }
    }
}
