package dev.summitstudio.uponthyhead

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer

/**
 * AAC in ADTS form: each frame carries a 7-byte header (sample rate, channels, its own length), so
 * a file can be read frame by frame with no index, and one cut off mid-frame is read up to its last
 * whole frame. This is what the recording parts are (SegmentRecorder), and what the iPhone writes.
 */
object Adts {
    private val RATES = intArrayOf(96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350)

    /** A function that puts the ADTS header (AAC-LC, no CRC) before one raw AAC frame. */
    fun header(rate: Int, channels: Int): (ByteArray) -> ByteArray {
        val sf = RATES.indexOf(rate).also { require(it >= 0) { "no ADTS rate $rate" } }
        val profile = 1 // AAC-LC is object type 2, written as type - 1
        return { frame ->
            val len = frame.size + 7
            require(len <= 0x1FFF) { "ADTS frame too large: $len" }
            val h = byteArrayOf(
                0xFF.toByte(),
                0xF1.toByte(), // MPEG-4, layer 0, no CRC
                ((profile shl 6) or (sf shl 2) or (channels shr 2)).toByte(),
                (((channels and 3) shl 6) or (len shr 11)).toByte(),
                ((len shr 3) and 0xFF).toByte(),
                (((len and 7) shl 5) or 0x1F).toByte(),
                0xFC.toByte(),
            )
            h + frame
        }
    }

    /** One file's frames: the raw AAC of each whole frame, and the stream's format. */
    class Frames(val rate: Int, val channels: Int, val objectType: Int, val frames: List<ByteArray>) {
        val seconds get() = frames.size * 1024.0 / rate
    }

    /** Every whole frame in [f], stopping at the first damaged or cut-off one. Null when none. */
    fun read(f: File): Frames? {
        val b = try { f.readBytes() } catch (_: Exception) { return null }
        var at = 0
        var rate = 0; var channels = 0; var type = 0
        val out = ArrayList<ByteArray>()
        while (at + 7 <= b.size) {
            val b0 = b[at].toInt() and 0xFF
            val b1 = b[at + 1].toInt() and 0xFF
            if (b0 != 0xFF || (b1 and 0xF0) != 0xF0) break
            val noCrc = b1 and 1 == 1
            val b2 = b[at + 2].toInt() and 0xFF
            val b3 = b[at + 3].toInt() and 0xFF
            val b4 = b[at + 4].toInt() and 0xFF
            val b5 = b[at + 5].toInt() and 0xFF
            val sf = (b2 shr 2) and 0xF
            if (sf >= RATES.size) break
            val ch = ((b2 and 1) shl 2) or (b3 shr 6)
            val len = ((b3 and 3) shl 11) or (b4 shl 3) or (b5 shr 5)
            val head = if (noCrc) 7 else 9
            if (len <= head || len > 0x1FFF || ch == 0 || at + len > b.size) break // cut off or corrupt: frames before it stand
            if (out.isEmpty()) { rate = RATES[sf]; channels = ch; type = (b2 shr 6) + 1 }
            out.add(b.copyOfRange(at + head, at + len))
            at += len
        }
        return if (out.isEmpty()) null else Frames(rate, channels, type, out)
    }

    /** The length in seconds of an ADTS part or of a joined `.m4a`; 0 when it does not read. */
    fun seconds(f: File): Double {
        if (!f.exists()) return 0.0
        if (f.extension == "aac") return read(f)?.seconds ?: 0.0
        val x = MediaExtractor()
        return try {
            x.setDataSource(f.path)
            (0 until x.trackCount).map { x.getTrackFormat(it) }
                .firstOrNull { it.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true }
                ?.takeIf { it.containsKey(MediaFormat.KEY_DURATION) }
                ?.getLong(MediaFormat.KEY_DURATION)?.let { it / 1e6 } ?: 0.0
        } catch (_: Exception) {
            0.0
        } finally {
            runCatching { x.release() }
        }
    }

    /**
     * The parts one after another in a single `.m4a` at [out]. The AAC frames are copied as they
     * are, not encoded again, so this is quick and loses nothing. Throws when nothing could be read;
     * the parts are then left on disk.
     */
    fun join(parts: List<File>, out: File) {
        val read = parts.mapNotNull { read(it) }
        require(read.isNotEmpty()) { "no audio in ${parts.size} part(s)" }
        val first = read.first()
        val f = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, first.rate, first.channels)
        // the AudioSpecificConfig the frames need: object type, rate index, channels
        val sf = RATES.indexOf(first.rate)
        val asc = (first.objectType shl 11) or (sf shl 7) or (first.channels shl 3)
        f.setByteBuffer("csd-0", ByteBuffer.wrap(byteArrayOf((asc shr 8).toByte(), asc.toByte())))
        out.parentFile?.mkdirs()
        val tmp = File(out.parentFile, out.name + ".tmp")
        tmp.delete()
        var muxer: MediaMuxer? = null
        var started = false
        var ok = false
        try {
            val m = MediaMuxer(tmp.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = m
            val track = m.addTrack(f)
            m.start()
            started = true
            val info = MediaCodec.BufferInfo()
            var n = 0L
            for (p in read) {
                if (p.rate != first.rate || p.channels != first.channels) continue // never written so
                for (frame in p.frames) {
                    info.set(0, frame.size, n * 1024 * 1_000_000L / first.rate, MediaCodec.BUFFER_FLAG_KEY_FRAME)
                    m.writeSampleData(track, ByteBuffer.wrap(frame), info)
                    n++
                }
            }
            m.stop()
            started = false
            m.release()
            muxer = null
            // whole or not at all
            if (!tmp.renameTo(out)) {
                if (out.exists()) out.delete()
                if (!tmp.renameTo(out)) throw IllegalStateException("could not put the joined file in place")
            }
            ok = true
        } finally {
            if (started) runCatching { muxer?.stop() }
            runCatching { muxer?.release() }
            if (!ok) tmp.delete()
        }
    }
}
