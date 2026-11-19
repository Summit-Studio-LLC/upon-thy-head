package dev.summitstudio.uponthyhead

import android.app.ActivityManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteOrder
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.ln

/**
 * The phone check's native half (lib/check/), on `upon_thy_head/check`.
 *
 * Registered only when the apk holds `phone_check/en.m4a`, which the build copies in only for
 * `--dart-define=PHONE_CHECK=true`. A normal build has no folder, so [NotYet.check] answers instead.
 *
 * Methods (Dart → Android): `audio`, `arguments`, `device`, `askMicrophone`, `inspect`,
 * `partSeconds`, `backupExcluded`, `log`. The words themselves are written through
 * `upon_thy_head/words`, the same path a blessing uses.
 */
class PhoneCheck(
    private val activity: () -> MainActivity?,
    private val context: Context,
) : MethodChannel.MethodCallHandler {
    companion object {
        private const val ASK = 7103
        private val pending = ArrayList<(Boolean, Boolean) -> Unit>()
        private val work = Executors.newSingleThreadExecutor { r -> Thread(r, "phone-check") }

        fun answered(code: Int, permissions: Array<out String>, grants: IntArray) {
            if (code != ASK) return
            val asked = permissions.isNotEmpty()
            val ok = asked && grants.isNotEmpty() && grants[0] == PackageManager.PERMISSION_GRANTED
            val all = pending.toList()
            pending.clear()
            all.forEach { it(asked, ok) }
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private val prefs = context.getSharedPreferences("permissions", Context.MODE_PRIVATE)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        when (call.method) {
            "arguments" -> result.success(activity()?.intent?.getStringArrayListExtra("check_args") ?: emptyList<String>())
            "audio" -> bg(result) { audio() }
            "device" -> result.success(device())
            "askMicrophone" -> askMicrophone(result)
            "inspect" -> {
                if (path == null) return result.success(null)
                bg(result) { inspect(path) }
            }
            "partSeconds" -> {
                if (path == null) return result.success(null)
                bg(result) { partSeconds(path) }
            }
            "backupExcluded" -> {
                if (path == null) return result.success(null)
                result.success(backupExcluded(path))
            }
            "log" -> {
                val lines = call.argument<List<*>>("lines") ?: emptyList<Any?>()
                for (line in lines) Log.i("phone_check", line.toString())
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun bg(result: MethodChannel.Result, block: () -> Any?) {
        work.execute {
            val r = runCatching { block() }
            main.post {
                r.fold(
                    { result.success(it) },
                    { e -> result.error("failed", e.toString(), null) },
                )
            }
        }
    }

    private fun audio(): Map<String, String> {
        val dir = File(context.cacheDir, "phone_check").also { it.mkdirs() }
        fun copy(name: String): String {
            val out = File(dir, name)
            context.assets.open("phone_check/$name").use { input -> out.outputStream().use { input.copyTo(it) } }
            return out.path
        }
        return mapOf("en" to copy("en.m4a"), "es" to copy("es.m4a"))
    }

    private fun device(): Map<String, Any> {
        val am = context.getSystemService(ActivityManager::class.java)
        val mem = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        val stat = StatFs(context.filesDir.path)
        val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown"
        val loaded = WhisperNative.loadedLibrary
        val whisperLib = when {
            loaded == "libuth_whisper_v82.so" -> "libuth_whisper_v82.so (Armv8.2 dotprod+fp16)"
            loaded == "libuth_whisper.so" && abi.startsWith("arm64") -> "libuth_whisper.so (Armv8-a baseline)"
            loaded != null -> "$loaded ($abi)"
            else -> WhisperNative.problem ?: "unavailable"
        }
        val emu = isEmulator()
        return mapOf(
            "machine" to "${Build.MANUFACTURER} ${Build.MODEL}",
            "simulated" to if (emu) "emulator" else "",
            "simulatorName" to Build.PRODUCT,
            "name" to Build.MODEL,
            "system" to "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
            "fps" to (activity()?.display?.refreshRate ?: 60f).toInt(),
            "free" to stat.availableBytes,
            "total" to stat.totalBytes,
            "memory" to mem.totalMem,
            "abi" to abi,
            "whisperLib" to whisperLib,
        )
    }

    private fun isEmulator(): Boolean {
        val fp = Build.FINGERPRINT
        return fp.startsWith("generic") || fp.startsWith("unknown") ||
            Build.MODEL.contains("google_sdk") || Build.MODEL.contains("Emulator") ||
            Build.MODEL.contains("Android SDK built for") ||
            Build.MANUFACTURER.contains("Genymotion") ||
            (Build.BRAND.startsWith("generic") && Build.DEVICE.startsWith("generic")) ||
            Build.PRODUCT == "google_sdk" ||
            Build.HARDWARE.contains("goldfish") || Build.HARDWARE.contains("ranchu")
    }

    private fun askMicrophone(result: MethodChannel.Result) {
        val granted = context.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        if (granted) return result.success("granted")
        val a = activity() ?: return result.success("denied")
        val first = pending.isEmpty()
        pending.add { asked, ok ->
            if (asked) prefs.edit().putBoolean(android.Manifest.permission.RECORD_AUDIO, true).apply()
            result.success(if (ok) "granted" else "denied")
        }
        if (first) {
            LockChannel.promptStart("perm:$ASK")
            try {
                a.requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO), ASK)
            } catch (_: Exception) {
                val all = pending.toList()
                pending.clear()
                LockChannel.promptEnd("perm:$ASK", a)
                all.forEach { it(false, false) }
            }
        }
    }

    /** Format, rate, channels, length and the loudest sample, decoded a buffer at a time. */
    private fun inspect(path: String): Map<String, Any> {
        val file = File(path)
        val out = HashMap<String, Any>()
        out["bytes"] = file.length()
        if (!file.exists()) {
            out["error"] = "the file would not open"
            return out
        }
        val ex = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            ex.setDataSource(file.absolutePath)
            val track = (0 until ex.trackCount).firstOrNull {
                ex.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            }
            if (track == null) {
                out["error"] = "the file would not open"
                return out
            }
            ex.selectTrack(track)
            val format = ex.getTrackFormat(track)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
            out["format"] = if (mime.contains("mp4a") || mime.contains("aac")) "AAC" else mime
            var rate = if (format.containsKey(MediaFormat.KEY_SAMPLE_RATE)) format.getInteger(MediaFormat.KEY_SAMPLE_RATE) else 0
            var channels = if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) else 1
            if (channels <= 0 || rate <= 0) {
                out["error"] = "the file would not open"
                return out
            }
            val durationUs = if (format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION) else 0L
            out["seconds"] = durationUs / 1e6
            val c = MediaCodec.createDecoderByType(mime)
            codec = c
            c.configure(format, null, null, 0)
            c.start()
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var idleSpins = 0
            var peak = 0
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
                    if (inputDone && ++idleSpins >= 500) break
                } else if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    idleSpins = 0
                    val f = c.outputFormat
                    if (f.containsKey(MediaFormat.KEY_SAMPLE_RATE)) rate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    if (f.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                        channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT).coerceAtLeast(1)
                    }
                } else if (o >= 0) {
                    idleSpins = 0
                    val buf = c.getOutputBuffer(o)!!.order(ByteOrder.LITTLE_ENDIAN)
                    buf.position(info.offset)
                    buf.limit(info.offset + info.size)
                    val shorts = buf.asShortBuffer()
                    val n = shorts.remaining()
                    // a buffer at a time, never the whole file
                    var i = 0
                    while (i < n) {
                        val s = abs(shorts.get(i).toInt())
                        if (s > peak) peak = s
                        i++
                    }
                    c.releaseOutputBuffer(o, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
            out["sampleRate"] = rate
            out["channels"] = channels
            out["peak"] = if (peak <= 0) -120.0 else 20.0 * ln(peak / 32768.0) / ln(10.0)
        } catch (_: Exception) {
            out["error"] = "the file would not open"
        } finally {
            runCatching { codec?.stop() }
            runCatching { codec?.release() }
            runCatching { ex.release() }
        }
        return out
    }

    private fun partSeconds(path: String): Map<String, Any> {
        val part = SegmentRecorder.partFile(File(path), 1)
        return mapOf(
            "seconds" to Adts.seconds(part),
            "bytes" to if (part.exists()) part.length() else 0L,
            "exists" to part.exists(),
        )
    }

    /** True when the app allows no backup and [path] is inside the no-backup folder. */
    private fun backupExcluded(path: String): Boolean {
        val off = context.applicationInfo.flags and ApplicationInfo.FLAG_ALLOW_BACKUP == 0
        if (!off) return false
        return try {
            val target = File(path).canonicalFile.path
            val noBackup = context.noBackupFilesDir.canonicalFile.path
            target == noBackup || target.startsWith(noBackup + File.separator)
        } catch (_: Exception) {
            false
        }
    }
}
