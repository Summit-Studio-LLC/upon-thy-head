package dev.summitstudio.uponthyhead

import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The Android app: the Flutter view, edge to edge, and the native side of every channel the Dart
 * code calls (the iPhone's are the Swift files in ios/Runner).
 *
 * Built so far: recording (SpeechChannel, SegmentRecorder, RecordingService), writing the words on
 * the phone with a model downloaded with the person's consent (WordsChannel, WhisperEngine,
 * ModelStore), listening back on the
 * review page (PlayerChannel), keeping the screen awake while a recording listens, the link's
 * cryptography (LinkChannel), sharing and receiving blessings by link, text, PDF and file
 * (ShareChannel, BlessingFiles), the app lock and the recent-apps cover (LockChannel), approximate
 * location (LocationChannel), the version, and opening this app's page in the system Settings.
 * Listening back with the screen locked is [PlaybackService]. The phone check page (test builds
 * only) is [PhoneCheck] when that build bundled its audio, and [NotYet] otherwise.
 *
 * One Flutter engine for the whole process: the first activity makes it (with the flags it was
 * started with) and it is kept, so a new activity (Android's "Don't keep activities", or the system
 * reclaiming a hidden screen) finds the recording screen exactly as it was, still listening.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val ENGINE = "main"
        private var registered = false
        private val started = HashSet<MainActivity>()

        @Volatile var current: MainActivity? = null
            private set

        /** On screen: the recording glow follows the microphone only while someone can see it. */
        @Volatile var visible = false
            private set

        @Volatile var keepScreenOn = false
            private set

        fun liveActivity(): MainActivity? = current?.takeIf { !it.isFinishing && !it.isDestroyed }

        /** lib/record/keep_awake.dart: the screen stays on while a recording listens. */
        private fun keepAwake(call: MethodCall, result: MethodChannel.Result) {
            when (call.method) {
                "get" -> {
                    val w = liveActivity()?.window
                    val on = if (w != null) {
                        (w.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) != 0
                    } else {
                        keepScreenOn
                    }
                    result.success(on)
                }
                "set" -> {
                    val on = call.arguments == true
                    keepScreenOn = on
                    liveActivity()?.window?.let { w ->
                        if (on) {
                            w.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            w.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Android's share sheet is started for a result, to hear when it closes")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == ShareChannel.REQUEST) ShareChannel.closed(applicationContext)
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? = FlutterEngineCache.getInstance().get(ENGINE)

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        SpeechChannel.answered(requestCode, permissions)
        LocationChannel.answered(requestCode, permissions)
        PhoneCheck.answered(requestCode, permissions, grantResults)
        LockChannel.promptEnd("perm:$requestCode", this)
    }

    override fun onStart() {
        super.onStart()
        current = this
        started.add(this)
        visible = true
        LockChannel.came(this)
    }

    override fun onResume() {
        super.onResume()
        current = this
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        LockChannel.focus(this, hasFocus)
    }

    override fun onStop() {
        started.remove(this)
        visible = started.isNotEmpty()
        // playback keeps going with the screen locked (PlaybackService); a recording's service does too
        // out of sight: the time is noted for the lock, and with the lock on the plain ground covers the app
        if (!visible) LockChannel.left(this)
        super.onStop()
    }

    override fun onDestroy() {
        started.remove(this)
        visible = started.isNotEmpty()
        LockChannel.destroyed(this)
        if (current === this) current = null
        super.onDestroy()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        current = this
        // Drawn under the status and navigation bars (Android 15 and later insist; this makes 13
        // and 14 the same). Flutter reports the bars' sizes as padding, as on iPhone.
        window.setDecorFitsSystemWindows(false)
        super.onCreate(savedInstanceState)
        if (keepScreenOn) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        // with the lock on, recent apps never shows the app (a new activity is told again)
        LockChannel.apply(this)
        if (!registered) {
            ShareChannel.register(applicationContext)
            registered = true
        }
        // the link or file this activity was opened with; not again when Android recreates it (it
        // keeps the old intent) or when it is reopened from recent apps
        if (savedInstanceState == null && (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) == 0) receive(intent)
        applyOrientation(resources.configuration)
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        applyOrientation(newConfig)
    }

    /** Upright on phones; tablets and unfolded screens turn freely, as the iPad does. */
    private fun applyOrientation(config: Configuration) {
        requestedOrientation = if (config.smallestScreenWidthDp < 600) {
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        } else {
            ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
    }

    /** A blessing link this activity was opened with (`https://uponthyhead.app/b/<id>#<key>`). */
    private fun linkOf(i: Intent?): String? {
        val u = i?.data ?: return null
        if (i.action != Intent.ACTION_VIEW || u.scheme != "https" || u.host != "uponthyhead.app") return null
        return if (u.path?.startsWith("/b/") == true) u.toString() else null
    }

    /** A blessing link (handed to Dart whole, fragment and all; never logged: it holds the key) or a
     *  blessing file (VIEW from Files, Gmail, WhatsApp; SEND into the app) this intent carries. */
    private fun receive(i: Intent?) {
        val place = shortcutOf(i)
        if (place != null) return ShareChannel.shortcut(place)
        ShareChannel.incoming(this, i, linkOf(i))
    }

    /** A launcher shortcut (res/xml/shortcuts.xml): where it leads, as Dart reads it. */
    private fun shortcutOf(i: Intent?): String? = when (i?.action) {
        "dev.summitstudio.uponthyhead.RECORD" -> "record"
        "dev.summitstudio.uponthyhead.HOME" -> "home"
        else -> null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receive(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        val cache = FlutterEngineCache.getInstance()
        // a kept engine has its plugins already
        if (cache.get(ENGINE) !== flutterEngine) super.configureFlutterEngine(flutterEngine)
        cache.put(ENGINE, flutterEngine)
        val app = applicationContext
        val m = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(m, "upon_thy_head/keep_awake").setMethodCallHandler(::keepAwake)
        val speech = MethodChannel(m, "upon_thy_head/speech")
        speech.setMethodCallHandler(SpeechChannel(::liveActivity, app))
        SpeechChannel.channel = speech
        val lock = MethodChannel(m, "upon_thy_head/lock")
        lock.setMethodCallHandler(LockChannel(::liveActivity, app))
        LockChannel.channel = lock
        val words = MethodChannel(m, "upon_thy_head/words")
        words.setMethodCallHandler(WordsChannel.get(app))
        WordsChannel.channel = words
        MethodChannel(m, "upon_thy_head/location").setMethodCallHandler(LocationChannel(::liveActivity, app))
        val player = MethodChannel(m, "upon_thy_head/player")
        val pc = PlayerChannel.get(app)
        player.setMethodCallHandler(pc)
        pc.channel = player
        MethodChannel(m, "upon_thy_head/link").setMethodCallHandler(LinkChannel(app))
        MethodChannel(m, "upon_thy_head/proof").setMethodCallHandler(ProofChannel(app))
        val share = MethodChannel(m, "upon_thy_head/share")
        ShareChannel.channel = share
        share.setMethodCallHandler { call, result -> ShareChannel.handle(::liveActivity, app, call, result) }
        val check = MethodChannel(m, "upon_thy_head/check")
        // the prepared recordings are in the apk only for --dart-define=PHONE_CHECK=true
        if (app.assets.list("phone_check")?.contains("en.m4a") == true) {
            check.setMethodCallHandler(PhoneCheck(::liveActivity, app))
            Log.i("phone_check", "present")
        } else {
            check.setMethodCallHandler(NotYet::check)
        }
        // upon_thy_head/language_menu/<id> is never called here: on Android the Dart side draws the
        // language menu itself (lib/record/language_menu.dart).
    }
}

/**
 * What Android cannot do yet, answered the way the Dart side's "not available" paths expect. Each
 * answer is the iPhone channel's own shape (same method names and keys) with the value that means
 * "this phone cannot", never one that means "done". Error code "unavailable" is the one the Dart
 * side already reads as "not on this phone" (lib/record/speech.dart).
 */
object NotYet {
    private fun no(result: MethodChannel.Result, what: String) =
        result.error("unavailable", "$what is not built on Android yet", null)

    /** The phone check page, in a build that did not bundle its audio (PhoneCheck registers otherwise). */
    fun check(call: MethodCall, result: MethodChannel.Result) = no(result, "The phone check")
}
