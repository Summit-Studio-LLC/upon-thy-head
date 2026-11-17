package dev.summitstudio.uponthyhead

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Plays a blessing's recording on the review page (lib/review/player.dart), on the channel
 * `upon_thy_head/player`, with the iPhone's methods (ios/Runner/Playback.swift):
 *
 *  - `load` {path} → duration in seconds; `play` → true if it started; `pause`; `seek` {seconds};
 *    `position` → {"position", "duration", "playing"}; `unload`
 *  - event `stopped` {position}: at the end, or when the system takes the sound (a call)
 *
 * Playing asks Android for the sound as speech, pausing other apps' audio as any player does, and
 * gives it back at pause. A call or another app taking the sound pauses it; during a call Android
 * refuses, and `play` answers false.
 *
 * In the foreground only, for now: leaving the app pauses it ([pauseForBackground], from
 * MainActivity). Listening with the phone locked needs a media-playback service and its
 * notification (docs/android-plan.md task 18).
 */
class PlayerChannel private constructor(context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        private const val TAG = "player"
        /** One player for the process: the engine outlives the screen (MainActivity). */
        var current: PlayerChannel? = null
            private set

        fun get(context: Context): PlayerChannel =
            current ?: PlayerChannel(context.applicationContext).also { current = it }
    }

    var channel: MethodChannel? = null
    private val audio = context.getSystemService(AudioManager::class.java)
    private var player: MediaPlayer? = null
    private var duration = 0.0

    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    private val focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
        .setAudioAttributes(attributes)
        .setOnAudioFocusChangeListener { change ->
            if (change == AudioManager.AUDIOFOCUS_LOSS || change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) stopped()
        }
        .build()

    private fun position(): Double = (player?.currentPosition ?: 0) / 1000.0

    /** Paused by the system or by leaving the app: Dart is told where. */
    private fun stopped() {
        val p = player ?: return
        if (!p.isPlaying) return
        p.pause()
        audio.abandonAudioFocusRequest(focus)
        channel?.invokeMethod("stopped", mapOf("position" to position()))
    }

    fun pauseForBackground() = stopped()

    fun release() {
        player?.release()
        player = null
        audio.abandonAudioFocusRequest(focus)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "load" -> {
                val path = call.argument<String>("path") ?: return result.error("args", "path", null)
                release()
                try {
                    val p = MediaPlayer()
                    p.setAudioAttributes(attributes)
                    p.setDataSource(path)
                    p.prepare()
                    p.setOnCompletionListener {
                        audio.abandonAudioFocusRequest(focus)
                        channel?.invokeMethod("stopped", mapOf("position" to duration))
                    }
                    player = p
                    duration = p.duration / 1000.0
                    result.success(duration)
                } catch (e: Exception) {
                    Log.e(TAG, "could not load: $e")
                    result.error("load", e.toString(), null)
                }
            }
            "play" -> {
                val p = player ?: return result.success(false)
                if (audio.requestAudioFocus(focus) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                    Log.i(TAG, "the system kept the sound")
                    return result.success(false)
                }
                if (p.currentPosition >= p.duration - 50) p.seekTo(0)
                p.start()
                result.success(true)
            }
            "pause" -> {
                player?.pause()
                audio.abandonAudioFocusRequest(focus)
                result.success(null)
            }
            "seek" -> {
                val s = call.argument<Double>("seconds") ?: 0.0
                player?.let { it.seekTo((s.coerceIn(0.0, duration) * 1000).toLong(), MediaPlayer.SEEK_CLOSEST) }
                result.success(null)
            }
            "position" -> {
                val p = player ?: return result.success(null)
                result.success(mapOf("position" to position(), "duration" to duration, "playing" to p.isPlaying))
            }
            "unload" -> {
                release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
