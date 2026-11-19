package dev.summitstudio.uponthyhead

import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.ApplicationInfo
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioRecordingConfiguration
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.Executors
import kotlin.math.log10
import kotlin.math.sqrt

/**
 * Records the microphone to AAC in ADTS parts, the Android twin of the iPhone's `SegmentRecorder`
 * (ios/Runner/SpeechChannel.swift). Same files, same names, same rules:
 *
 *  - Each part is `<id>.partN.aac`: ADTS AAC, a stream of self-contained frames with no index, so a
 *    part the app was killed in the middle of is still readable up to its last whole frame.
 *  - When the system silences the recording (a phone call, ringing, another app taking the
 *    microphone) the part is closed and [onPaused] says so; when the sound comes back a new part
 *    starts. Nothing silent is written in between.
 *  - [stop] joins the parts, without encoding again, into the one `.m4a` (see [Adts.join]).
 *
 * Why `AudioRecord` with `MediaCodec` and not `MediaRecorder` (which can write ADTS itself):
 *  - The silence of a call is reported only for a recording that is still running
 *    (`AudioRecordingConfiguration.isClientSilenced`). Here the microphone stays open through a
 *    call and the silent samples are simply not encoded, so the app hears the moment the sound
 *    comes back. A `MediaRecorder` would have to be stopped at the call and could not hear that.
 *  - Each AAC frame is written to the part by the app with one `write`, as soon as it is encoded,
 *    so a kill loses only what is still inside the encoder (a fraction of a second), whatever
 *    `MediaRecorder`'s own writer would have buffered.
 *
 * The microphone used is the phone's own (`TYPE_BUILTIN_MIC`, preferred), so a Bluetooth headset or
 * a wired one connecting or dropping mid-blessing changes nothing (docs/android-plan.md section 4).
 */
class SegmentRecorder(private val context: Context) {
    companion object {
        private const val TAG = "speech"

        /** AAC-LC at 32 kHz mono, 24 kbit/s: about 11 MB an hour, as on iPhone. */
        const val RATE = 32_000
        const val BITRATE = 24_000

        /** Samples read from the microphone at a time: 20 ms; loudness sent every three (60 ms). */
        private const val CHUNK = RATE / 50
        private const val LEVEL_SAMPLES = CHUNK * 3

        fun partFile(target: File, n: Int): File = File(target.parentFile, "${target.nameWithoutExtension}.part$n.aac")

        /** The parts of the recording that would end at [target], in order. */
        fun partsOnDisk(target: File): List<File> {
            val id = target.nameWithoutExtension
            val re = Regex("^" + Regex.escape(id) + "\\.part(\\d+)\\.aac$")
            return (target.parentFile?.listFiles() ?: emptyArray())
                .mapNotNull { f -> re.find(f.name)?.groupValues?.get(1)?.toIntOrNull()?.let { it to f } }
                .sortedBy { it.first }
                .map { it.second }
        }
    }

    /** True while the system has the microphone; false when it gives it back. Main thread. */
    var onPaused: ((Boolean) -> Unit)? = null

    /** Microphone loudness in dBFS while on screen and listening, about 16 times a second. Main thread. */
    var onLevel: ((Double) -> Unit)? = null

    /** Repeated disk write failure on the recording thread. Main thread. */
    var onError: ((Exception) -> Unit)? = null

    /** Tests: at [stop], the finished file is replaced by a copy of this one. */
    var feed: File? = null

    private val debuggable = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

    /**
     * Tests, in a debuggable build only: when `files/debug_mic.pcm` (32 kHz mono 16-bit, little
     * endian) is there at Begin, the samples the microphone delivers are replaced by the file's, one
     * for one, so the microphone still sets the pace and a call still silences it, but what is
     * recorded is known (tool/android_record.py; the emulator's own way of feeding its microphone
     * crashes it). The file is read on from where it was, in real time, paused or not, as a voice
     * in the room goes on through a call; past its end, silence.
     */
    private fun debugSource(): java.io.InputStream? {
        val f = File(context.filesDir, "debug_mic.pcm")
        if (!debuggable || !f.exists()) return null
        Log.i(TAG, "recording: the microphone's samples come from ${f.name} (tests)")
        return java.io.BufferedInputStream(f.inputStream(), 1 shl 16)
    }

    /**
     * Tests, in a debuggable build only: when `files/debug_feed.m4a` is there at Amen, the finished
     * recording is replaced by a copy of it, as [feed] does for the integration tests. The scripted
     * runs use it to give the app a long recording the app itself made earlier, without recording
     * it again in real time (tool/android_words.py). Release builds never look for it.
     */
    private fun debugFed(): File? {
        val f = File(context.filesDir, "debug_feed.m4a")
        return if (debuggable && f.exists()) f.also { Log.i(TAG, "recording: replaced at Amen by ${it.name} (tests)") } else null
    }

    private val main = Handler(Looper.getMainLooper())
    private val audio = context.getSystemService(AudioManager::class.java)
    private val io = Executors.newSingleThreadExecutor { r -> Thread(r, "segment-join") }

    @Volatile private var target: File? = null
    @Volatile private var running = false
    private var thread: Thread? = null
    @Volatile private var record: AudioRecord? = null

    /** Why the recording is silenced now; paused while any is true. */
    @Volatile private var silenced = false
    @Volatile private var inCall = false
    @Volatile private var forced = false
    @Volatile private var paused = false

    /** Parts made so far (1-based count), and the one being written; touched only by the thread. */
    private var partCount = 0
    private var out: FileOutputStream? = null

    val recording get() = target != null

    /** Milliseconds recorded, not counting time paused (for the notification's clock). */
    @Volatile var recordedMs = 0L
        private set

    @SuppressLint("MissingPermission") // asked for before Begin is possible (SpeechChannel)
    fun start(file: File) {
        cancel()
        file.parentFile?.mkdirs()
        val min = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val r = AudioRecord.Builder()
            .setAudioSource(MediaRecorder.AudioSource.MIC)
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(RATE)
                    .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                    .build(),
            )
            // half a second of room, so a slow moment on the phone loses nothing
            .setBufferSizeInBytes(maxOf(min * 2, RATE))
            .build()
        if (r.state != AudioRecord.STATE_INITIALIZED) {
            r.release()
            throw IllegalStateException("the microphone could not be opened")
        }
        builtInMic()?.let { r.preferredDevice = it }
        val encoder = try {
            newEncoder()
        } catch (e: Exception) {
            r.release()
            throw e
        }
        try {
            r.startRecording()
        } catch (e: Exception) {
            r.release(); encoder.release()
            throw e
        }
        if (r.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
            r.release(); encoder.release()
            throw IllegalStateException("the microphone would not start")
        }
        record = r
        target = file
        partCount = 0
        recordedMs = 0
        silenced = false
        inCall = isCallMode(audio.mode)
        forced = false
        paused = inCall
        running = true
        watch(true)
        if (debuggable) Log.i(TAG, "recording: started at ${System.currentTimeMillis()} into ${file.name}")
        val source = debugSource()
        thread = Thread({ loop(r, encoder, file, source) }, "recording").apply {
            priority = Thread.MAX_PRIORITY
            start()
        }
        if (paused) main.post { onPaused?.invoke(true) }
    }

    private fun newEncoder(): MediaCodec {
        val f = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, RATE, 1).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, BITRATE)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, CHUNK * 2 * 4)
        }
        val c = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        try {
            c.configure(f, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            c.start()
            return c
        } catch (e: Exception) {
            runCatching { c.release() }
            throw e
        }
    }

    private fun builtInMic(): AudioDeviceInfo? =
        audio.getDevices(AudioManager.GET_DEVICES_INPUTS).firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }

    /** The recording thread: microphone → encoder → the part being written. */
    private fun loop(r: AudioRecord, encoder: MediaCodec, file: File, source: java.io.InputStream? = null) {
        val pcm = ShortArray(CHUNK)
        val raw = ByteArray(CHUNK * 2)
        val info = MediaCodec.BufferInfo()
        var fed = 0L // samples given to the encoder: its clock, which skips the time paused
        var wasPaused = false
        var levelSq = 0.0
        var levelCount = 0
        var writeFailures = 0
        // frames that came out of the encoder while no part was open (just after a pause)
        val waiting = ArrayList<ByteArray>()
        val adtsHeader = Adts.header(RATE, 1)
        fun write(frame: ByteArray) {
            val o = out ?: run {
                if (paused) { waiting.add(frame); return }
                partCount += 1
                FileOutputStream(partFile(file, partCount)).also {
                    out = it
                    if (debuggable) Log.i(TAG, "recording: part $partCount")
                    for (w in waiting) it.write(adtsHeader(w))
                    waiting.clear()
                }
            }
            o.write(adtsHeader(frame))
        }
        fun drain(untilEnd: Boolean) {
            val limit = SystemClock.elapsedRealtime() + 2000
            while (true) {
                val i = encoder.dequeueOutputBuffer(info, if (untilEnd) 10_000 else 0)
                if (i >= 0) {
                    val config = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                    if (!config && info.size > 0) {
                        val b = encoder.getOutputBuffer(i)!!
                        b.position(info.offset); b.limit(info.offset + info.size)
                        val frame = ByteArray(info.size).also { b.get(it) }
                        try {
                            write(frame)
                            writeFailures = 0
                        } catch (e: IOException) {
                            writeFailures++
                            out?.let { runCatching { it.close() } }
                            out = null
                            Log.e(TAG, "recording: could not write ($writeFailures): ${e.javaClass.simpleName}")
                            if (writeFailures >= 5) {
                                encoder.releaseOutputBuffer(i, false)
                                running = false
                                main.post { onError?.invoke(e) }
                                return
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "recording: could not write: ${e.javaClass.simpleName}")
                        }
                    }
                    encoder.releaseOutputBuffer(i, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                } else if (!untilEnd || SystemClock.elapsedRealtime() > limit) {
                    if (i != MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) return
                }
            }
        }
        try {
            while (running) {
                val n = r.read(pcm, 0, pcm.size)
                if (n < 0) {
                    if (running) Log.e(TAG, "recording: the microphone failed ($n)")
                    break
                }
                if (!running) break
                if (source != null && n > 0) {
                    var got = 0
                    while (got < n * 2) { val k = source.read(raw, got, n * 2 - got); if (k <= 0) break; got += k }
                    java.util.Arrays.fill(raw, got, n * 2, 0)
                    for (s in 0 until n) pcm[s] = ((raw[2 * s].toInt() and 0xFF) or (raw[2 * s + 1].toInt() shl 8)).toShort()
                }
                val nowPaused = paused
                if (nowPaused != wasPaused) {
                    wasPaused = nowPaused
                    if (nowPaused) {
                        // the part so far is complete on disk, whatever happens next
                        out?.let { try { it.close() } catch (_: Exception) {} }
                        out = null
                        levelSq = 0.0
                        levelCount = 0
                        main.post { onLevel?.invoke(-160.0) }
                        if (debuggable) Log.i(TAG, "recording: paused; $partCount part(s) kept")
                    } else {
                        if (debuggable) Log.i(TAG, "recording: listening again")
                    }
                }
                if (nowPaused || n == 0) { drain(false); continue }
                if (MainActivity.visible) {
                    var sq = 0.0
                    for (k in 0 until n) {
                        val s = pcm[k].toDouble()
                        sq += s * s
                    }
                    levelSq += sq
                    levelCount += n
                    if (levelCount >= LEVEL_SAMPLES) {
                        val rms = sqrt(levelSq / levelCount) / 32768.0
                        val db = if (rms > 1e-8) 20.0 * log10(rms) else -160.0
                        levelSq = 0.0
                        levelCount = 0
                        main.post { onLevel?.invoke(db) }
                    }
                } else {
                    levelSq = 0.0
                    levelCount = 0
                }
                var off = 0
                val inputLimit = SystemClock.elapsedRealtime() + 2000
                while (off < n && running) {
                    val i = encoder.dequeueInputBuffer(10_000)
                    if (i < 0) {
                        drain(false)
                        if (SystemClock.elapsedRealtime() > inputLimit) {
                            Log.w(TAG, "recording: encoder input stalled")
                            break
                        }
                        continue
                    }
                    val buf = encoder.getInputBuffer(i)!!
                    buf.clear()
                    val count = minOf(n - off, buf.capacity() / 2)
                    buf.asShortBuffer().put(pcm, off, count)
                    encoder.queueInputBuffer(i, 0, count * 2, fed * 1_000_000L / RATE, 0)
                    fed += count
                    off += count
                }
                recordedMs = fed * 1000 / RATE
                drain(false)
            }
            // the end: what is still inside the encoder goes into the last part
            val eos = encoder.dequeueInputBuffer(100_000)
            if (eos >= 0) encoder.queueInputBuffer(eos, 0, 0, fed * 1_000_000L / RATE, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            drain(true)
            if (waiting.isNotEmpty()) {
                try {
                    val o = out ?: run {
                        partCount += 1
                        FileOutputStream(partFile(file, partCount)).also {
                            out = it
                            if (debuggable) Log.i(TAG, "recording: part $partCount")
                        }
                    }
                    for (w in waiting) o.write(adtsHeader(w))
                    waiting.clear()
                } catch (e: Exception) {
                    Log.e(TAG, "recording: could not flush waiting frames: ${e.javaClass.simpleName}")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "recording: ${e.javaClass.simpleName}")
        } finally {
            out?.let { try { it.close() } catch (_: Exception) {} }
            out = null
            try { encoder.stop() } catch (_: Exception) {}
            runCatching { encoder.release() }
            try { r.stop() } catch (_: Exception) {}
            runCatching { r.release() }
            try { source?.close() } catch (_: Exception) {}
        }
    }

    // ---- the system taking the microphone ----

    private val recordingCallback = object : AudioManager.AudioRecordingCallback() {
        override fun onRecordingConfigChanged(configs: MutableList<AudioRecordingConfiguration>) {
            val session = record?.audioSessionId ?: return
            val mine = configs.firstOrNull { it.clientAudioSessionId == session } ?: return
            if (mine.isClientSilenced != silenced) {
                silenced = mine.isClientSilenced
                if (debuggable) Log.i(TAG, "recording: silenced by the system: $silenced")
                update()
            }
        }
    }

    private val modeListener = AudioManager.OnModeChangedListener { mode ->
        val call = isCallMode(mode)
        if (call != inCall) {
            inCall = call
            if (debuggable) Log.i(TAG, "recording: phone mode $mode")
            update()
        }
    }

    private val deviceCallback = object : AudioDeviceCallback() {
        // a headset coming or going: the phone's own microphone stays the one recording
        override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) = keepBuiltIn("added", added)
        override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) = keepBuiltIn("removed", removed)
        private fun keepBuiltIn(what: String, d: Array<out AudioDeviceInfo>) {
            if (d.none { it.isSource }) return
            if (debuggable) Log.i(TAG, "recording: input $what (${d.filter { it.isSource }.joinToString { "${it.type}" }})")
            builtInMic()?.let { record?.preferredDevice = it }
        }
    }

    private fun isCallMode(mode: Int) = mode == AudioManager.MODE_RINGTONE || mode == AudioManager.MODE_IN_CALL ||
        mode == AudioManager.MODE_IN_COMMUNICATION || mode == AudioManager.MODE_CALL_SCREENING ||
        mode == AudioManager.MODE_CALL_REDIRECT || mode == AudioManager.MODE_COMMUNICATION_REDIRECT

    private var watching = false
    private fun watch(on: Boolean) {
        if (on == watching) return
        watching = on
        if (on) {
            audio.registerAudioRecordingCallback(recordingCallback, main)
            audio.addOnModeChangedListener(context.mainExecutor, modeListener)
            audio.registerAudioDeviceCallback(deviceCallback, main)
        } else {
            runCatching { audio.unregisterAudioRecordingCallback(recordingCallback) }
            runCatching { audio.removeOnModeChangedListener(modeListener) }
            runCatching { audio.unregisterAudioDeviceCallback(deviceCallback) }
        }
    }

    private fun update() {
        if (target == null) return
        val now = silenced || inCall || forced
        if (now == paused) return
        paused = now
        onPaused?.invoke(now)
    }

    /** Tests: behave as if the system took the microphone, or gave it back. */
    fun debugInterrupt(began: Boolean) {
        forced = began
        update()
    }

    // ---- the end ----

    /** Stop listening and close the part being written; the parts stay on disk. */
    private fun halt(): File? {
        val t = target ?: return null
        running = false
        watch(false)
        // Stop AudioRecord before joining so a blocked read() returns immediately instead of stalling UI.
        runCatching { record?.stop() }
        thread?.join(3000)
        thread = null
        record = null
        target = null
        paused = false
        return t
    }

    /** Amen: the parts joined into the one file. [done] runs on the main thread. */
    fun stop(done: (Result<File>) -> Unit) {
        val t = halt() ?: return done(Result.failure(IllegalStateException("not recording")))
        if (debuggable) Log.i(TAG, "recording: stopped at ${System.currentTimeMillis()}")
        val fed = feed ?: debugFed()
        io.execute {
            val r = runCatching {
                val parts = partsOnDisk(t).filter { it.length() > 0 }
                Adts.join(parts, t)
                partsOnDisk(t).forEach { it.delete() }
                // tests: the words they expect, in place of the room's
                if (fed != null) fed.copyTo(t, overwrite = true)
                if (debuggable) {
                    Log.i(TAG, "recording: joined ${t.name}, ${"%.2f".format(Adts.seconds(t))} s")
                }
                t
            }
            main.post { done(r) }
        }
    }

    /** Stop and delete everything recorded. */
    fun cancel() {
        val t = halt() ?: return
        partsOnDisk(t).forEach { it.delete() }
        t.delete()
    }

    /** The app is going away (swiped from recent apps): close the part; recovery finds it. */
    fun abandon() {
        halt()?.let {
            if (debuggable) Log.i(TAG, "recording: abandoned; recovery will join ${partsOnDisk(it).size} part(s)")
        }
    }
}
