package dev.summitstudio.uponthyhead

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Plays a blessing's recording on the review page (lib/review/player.dart), on the channel
 * `upon_thy_head/player`, with the iPhone's methods (ios/Runner/Playback.swift):
 *
 *  - `load` {path} → duration in seconds; `play` → true if it started; `pause`; `seek` {seconds};
 *    `position` → {"position", "duration", "playing"}; `unload`
 *  - event `stopped` {position}: at the end, when the system takes the sound (a call), or when
 *    headphones come unplugged
 *
 * Playing asks Android for the sound as speech, pausing other apps' audio as any player does, and
 * gives it back at pause. A call or another app taking the sound pauses it; during a call Android
 * refuses, and `play` answers false. It does not start again on its own.
 *
 * With the screen locked, [PlaybackService] keeps it going. The notification names no blessing.
 * Headphones coming out pause it at once, so a blessing never continues over the room's speaker.
 */
class PlayerChannel private constructor(context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        private const val TAG = "player"
        /** One player for the process: the engine outlives the screen (MainActivity). */
        @Volatile var current: PlayerChannel? = null
            private set

        @Synchronized
        fun get(context: Context): PlayerChannel =
            current ?: PlayerChannel(context.applicationContext).also { current = it }
    }

    private val appContext = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    var channel: MethodChannel? = null
    private val audio = appContext.getSystemService(AudioManager::class.java)
    private var player: MediaPlayer? = null
    private var duration = 0.0
    private var noisyRegistered = false

    val isPlaying: Boolean
        get() = runCatching { player?.isPlaying == true }.getOrDefault(false)

    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    private val focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
        .setAudioAttributes(attributes)
        .setWillPauseWhenDucked(true)
        .setOnAudioFocusChangeListener({ change ->
            if (change == AudioManager.AUDIOFOCUS_LOSS ||
                change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT ||
                change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK
            ) {
                stopped()
            }
        }, main)
        .build()

    /** A cord pulled out, or earbuds disconnecting: pause before the speaker takes over. */
    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, i: Intent?) {
            if (i?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) stopped()
        }
    }

    private fun position(): Double = runCatching { (player?.currentPosition ?: 0) / 1000.0 }.getOrDefault(0.0)

    private fun listenForUnplug() {
        if (noisyRegistered) return
        // ACTION_AUDIO_BECOMING_NOISY is an OS protected broadcast; RECEIVER_EXPORTED prevents OEM
        // Bluetooth-UID deliveries from being dropped by RECEIVER_NOT_EXPORTED filtering.
        appContext.registerReceiver(
            noisyReceiver,
            IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY),
            Context.RECEIVER_EXPORTED,
        )
        noisyRegistered = true
    }

    private fun stopServiceAndReceiver() {
        if (noisyRegistered) {
            runCatching { appContext.unregisterReceiver(noisyReceiver) }
            noisyRegistered = false
        }
        PlaybackService.stop(appContext)
    }

    /** Paused by the system, by headphones coming out, or by the app being swiped away. */
    private fun stopped() {
        val p = player ?: return
        if (!isPlaying) return
        runCatching { p.pause() }
        audio.abandonAudioFocusRequest(focus)
        stopServiceAndReceiver()
        channel?.invokeMethod("stopped", mapOf("position" to position()))
    }

    /** The app was swiped away while listening (PlaybackService.onTaskRemoved / onTimeout). */
    fun stopFromSystem() = stopped()

    fun release() {
        stopServiceAndReceiver()
        runCatching { player?.release() }
        player = null
        audio.abandonAudioFocusRequest(focus)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "load" -> {
                val path = call.argument<String>("path") ?: return result.error("args", "path", null)
                release()
                val p = MediaPlayer()
                try {
                    p.setAudioAttributes(attributes)
                    p.setDataSource(path)
                    p.prepare()
                    p.setOnCompletionListener {
                        audio.abandonAudioFocusRequest(focus)
                        stopServiceAndReceiver()
                        channel?.invokeMethod("stopped", mapOf("position" to duration))
                    }
                    p.setOnErrorListener { _, what, extra ->
                        Log.w(TAG, "playback error: $what ($extra)")
                        audio.abandonAudioFocusRequest(focus)
                        stopServiceAndReceiver()
                        channel?.invokeMethod("stopped", mapOf("position" to position()))
                        true
                    }
                    player = p
                    duration = p.duration / 1000.0
                    result.success(duration)
                } catch (e: Exception) {
                    runCatching { p.release() }
                    Log.e(TAG, "could not load: ${e.javaClass.simpleName}")
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
                listenForUnplug()
                PlaybackService.start(appContext)
                result.success(true)
            }
            "pause" -> {
                player?.let { if (it.isPlaying) it.pause() }
                audio.abandonAudioFocusRequest(focus)
                stopServiceAndReceiver()
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
