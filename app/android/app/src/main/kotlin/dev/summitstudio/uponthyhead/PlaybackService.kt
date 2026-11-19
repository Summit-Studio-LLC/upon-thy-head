package dev.summitstudio.uponthyhead

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.os.PowerManager
import android.util.Log

/**
 * Keeps review playback going with the screen locked or the app out of sight: a foreground service
 * of type "media playback" (docs/android-plan.md task 18). Started when play begins, stopped at
 * pause, at the end, when the sound is taken, and when headphones come out.
 *
 * Its notification is quiet and says only "Listening to a recording": no title, name, date, length
 * or words of the blessing, and no media session, so a lock screen learns nothing about it. A tap
 * opens the app where the review page still is. If the notification permission was refused the
 * service runs all the same.
 */
class PlaybackService : Service() {
    companion object {
        private const val TAG = "player"
        private const val CHANNEL = "playback"
        private const val ID = 2

        @Volatile var running = false
            private set

        @Volatile private var wantStop = false

        fun start(context: Context): Boolean {
            wantStop = false
            return try {
                context.startForegroundService(Intent(context, PlaybackService::class.java))
                true
            } catch (e: Exception) {
                Log.w(TAG, "playback: could not start service: $e")
                false
            }
        }

        fun stop(context: Context) {
            wantStop = true
            if (running) {
                runCatching { context.stopService(Intent(context, PlaybackService::class.java)) }
            }
        }

        private fun channel(context: Context) {
            val m = context.getSystemService(NotificationManager::class.java)
            val c = NotificationChannel(CHANNEL, context.getString(R.string.playback_channel), NotificationManager.IMPORTANCE_LOW).apply {
                description = context.getString(R.string.playback_channel_about)
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            m.createNotificationChannel(c)
        }

        fun notification(context: Context): Notification {
            channel(context)
            val open = PendingIntent.getActivity(
                context,
                2,
                Intent(context, MainActivity::class.java)
                    .setAction(Intent.ACTION_MAIN)
                    .addCategory(Intent.CATEGORY_LAUNCHER)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            return Notification.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(context.getString(R.string.playback_title))
                .setContentIntent(open)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setCategory(Notification.CATEGORY_SERVICE)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
                .setColor(0xFFC9A55B.toInt())
                .build()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /** The processor stays awake so playback is not suspended with the screen off. */
    private var wake: PowerManager.WakeLock? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            // Always satisfy Android's 5-second foreground contract first, even if stop() already raced in.
            startForeground(ID, notification(this), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } catch (e: Exception) {
            // on-screen playback goes on; only the locked part is lost
            Log.e(TAG, "playback: the service could not start: $e")
            running = false
            stopSelf()
            return START_NOT_STICKY
        }
        if (wantStop || PlayerChannel.current?.isPlaying != true) {
            running = false
            wake?.let { if (it.isHeld) it.release() }
            wake = null
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        running = true
        if (wake?.isHeld != true) {
            wake = (wake ?: getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "uponthyhead:playback"))
                .apply { acquire(2 * 60 * 60 * 1000L) } // a ceiling, longer than a blessing
        }
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            Log.i(TAG, "playback: service in the foreground")
        }
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int) = onTimeout(startId, 0)

    override fun onTimeout(startId: Int, fgsType: Int) {
        Log.w(TAG, "playback: foreground service timed out")
        PlayerChannel.current?.stopFromSystem()
        running = false
        wake?.let { if (it.isHeld) it.release() }
        wake = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /** Swiped away from recent apps: stop the sound. Nothing of the blessing is left playing. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        PlayerChannel.current?.stopFromSystem()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        running = false
        wake?.let { if (it.isHeld) it.release() }
        wake = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            Log.i(TAG, "playback: service stopped")
        }
        super.onDestroy()
    }
}
