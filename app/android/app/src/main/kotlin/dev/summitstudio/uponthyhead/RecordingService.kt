package dev.summitstudio.uponthyhead

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.os.PowerManager
import android.os.Process
import android.util.Log

/**
 * Keeps a recording going with the screen locked or the app out of sight: a foreground service of
 * type "microphone" (docs/android-plan.md section 4). Started by Begin, while the app is on screen
 * (Android allows a microphone service to start only then); stopped by Amen and by Discard, and
 * never left running.
 *
 * Its notification is quiet (no sound, no vibration, never a pop-up): the app's small monochrome
 * icon, "Recording a blessing" and the time recorded, and nothing of the blessing itself, so it is
 * safe on a lock screen. A tap opens the recording screen. There are no buttons: a stray touch in a
 * pocket must never end a blessing. If the notification permission was refused the service runs
 * all the same; Android then lists it only in its own task manager.
 */
class RecordingService : Service() {
    companion object {
        private const val TAG = "speech"
        private const val CHANNEL = "recording"
        private const val ID = 1

        /** Tests: the service is up now. */
        @Volatile var running = false
            private set

        /** Begin. */
        fun start(context: Context) {
            context.startForegroundService(Intent(context, RecordingService::class.java))
        }

        /** Amen or Discard. */
        fun stop(context: Context) {
            context.stopService(Intent(context, RecordingService::class.java))
        }

        /** The clock in the notification, again: after a pause it carries on from the time recorded. */
        fun refresh(context: Context, paused: Boolean) {
            val m = context.getSystemService(NotificationManager::class.java)
            if (SpeechChannel.recorder?.recording != true) return
            m.notify(ID, notification(context, paused))
        }

        private fun channel(context: Context) {
            val m = context.getSystemService(NotificationManager::class.java)
            val c = NotificationChannel(CHANNEL, context.getString(R.string.recording_channel), NotificationManager.IMPORTANCE_LOW).apply {
                description = context.getString(R.string.recording_channel_about)
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            m.createNotificationChannel(c)
        }

        fun notification(context: Context, paused: Boolean): Notification {
            channel(context)
            val open = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java)
                    .setAction(Intent.ACTION_MAIN)
                    .addCategory(Intent.CATEGORY_LAUNCHER)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val recorded = SpeechChannel.recorder?.recordedMs ?: 0L
            return Notification.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(context.getString(R.string.recording_title))
                .apply {
                    if (paused) {
                        setContentText(context.getString(R.string.recording_paused))
                        setShowWhen(false)
                    } else {
                        // Android's own running clock, started where the recording is now
                        setWhen(System.currentTimeMillis() - recorded)
                        setUsesChronometer(true)
                        setShowWhen(true)
                    }
                }
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

    /** The processor stays awake while the recording is encoded and written, screen off or not. */
    private var wake: PowerManager.WakeLock? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            startForeground(ID, notification(this, false), ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            running = true
            if (wake == null) {
                wake = getSystemService(PowerManager::class.java)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "uponthyhead:recording")
                    .apply { acquire(4 * 60 * 60 * 1000L) } // a ceiling, never reached by a blessing
            }
            Log.i(TAG, "recording: service in the foreground")
        } catch (e: Exception) {
            // the recording itself goes on while the app is on screen; only the locked part is lost
            Log.e(TAG, "recording: the service could not start: $e")
            stopSelf()
        }
        // never restarted by the system after a kill: the recording is recovered at the next launch
        return START_NOT_STICKY
    }

    /**
     * Swiped away from recent apps: the same as the app being closed on iPhone. The part is closed so
     * the next launch recovers it ("recovered" sheet), and the process ends, so nothing is left
     * listening with no screen to finish it.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        if (SpeechChannel.recorder?.recording == true) {
            SpeechChannel.recorder?.abandon()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            Process.killProcess(Process.myPid())
        }
    }

    override fun onDestroy() {
        running = false
        wake?.let { if (it.isHeld) it.release() }
        wake = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        Log.i(TAG, "recording: service stopped")
        super.onDestroy()
    }
}
