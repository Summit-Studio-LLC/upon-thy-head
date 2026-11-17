package dev.summitstudio.uponthyhead

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Where blessings are given, for lib/place/where.dart, on `upon_thy_head/location` (the iPhone's is
 * `LocationChannel` in ios/Runner/Privacy.swift).
 *
 * Only approximate location is ever asked for (`ACCESS_COARSE_LOCATION`; the manifest has no fine
 * location, so Android never offers "Precise"), and Dart keeps it rounded to a tenth of a degree.
 *  - `status` → "undetermined" (never asked), "denied" (asked, not allowed now, including after
 *    "Only this time" has lapsed) or "granted"
 *  - `request` → the status after Android's question (put only if not allowed now; Android itself
 *    answers at once, without a question, once it has been refused twice)
 *  - `locate` → {lat, lon}, or null: not allowed, location off for the whole phone, or nothing
 *    within [LIMIT_MS]. One reading from the platform's own LocationManager, no Google Play services:
 *    one current fix, asked of fused, network and GPS at once, the first to answer used (with
 *    coarse permission Android blurs each to about 2 km), or, if none comes in time, a place the
 *    phone knew in the last ten minutes.
 */
class LocationChannel(private val activity: () -> Activity?, private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        private const val TAG = "location"
        const val ASK = 41
        private const val LIMIT_MS = 6000L
        private const val RECENT_MS = 10 * 60 * 1000L
        private var waiting: (() -> Unit)? = null

        /** From MainActivity.onRequestPermissionsResult. */
        fun answered(code: Int) {
            if (code != ASK) return
            val w = waiting
            waiting = null
            w?.invoke()
        }
    }

    private val prefs = context.getSharedPreferences("permissions", Context.MODE_PRIVATE)
    private val manager = context.getSystemService(LocationManager::class.java)
    private val main = Handler(Looper.getMainLooper())

    private fun granted() = context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    private fun status() = when {
        granted() -> "granted"
        prefs.getBoolean(Manifest.permission.ACCESS_COARSE_LOCATION, false) -> "denied"
        else -> "undetermined"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(status())
            "request" -> {
                val a = activity()
                if (granted() || a == null || waiting != null) return result.success(status())
                prefs.edit().putBoolean(Manifest.permission.ACCESS_COARSE_LOCATION, true).apply()
                LockChannel.prompting = true
                waiting = {
                    LockChannel.prompting = false
                    result.success(status())
                }
                a.requestPermissions(arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION), ASK)
            }
            "locate" -> locate(result)
            else -> result.notImplemented()
        }
    }

    private fun locate(result: MethodChannel.Result) {
        val m = manager
        val started = SystemClock.elapsedRealtime()
        if (!granted() || m == null || !m.isLocationEnabled) {
            Log.i(TAG, "located: none (${if (!granted()) "not allowed" else "location off"}) in ${SystemClock.elapsedRealtime() - started} ms")
            return result.success(null)
        }
        var done = false
        val signals = mutableListOf<CancellationSignal>()
        val settle = { l: Location? ->
            if (!done) {
                done = true
                signals.forEach { it.cancel() }
                Log.i(TAG, "located: ${if (l == null) "none" else "a place"} in ${SystemClock.elapsedRealtime() - started} ms")
                result.success(l?.let { mapOf("lat" to it.latitude, "lon" to it.longitude) })
            }
        }
        val providers = listOf(LocationManager.FUSED_PROVIDER, LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER)
            .filter { m.allProviders.contains(it) && m.isProviderEnabled(it) }
        try {
            // a recent place the phone already knows, for when no current one comes in time
            val now = SystemClock.elapsedRealtimeNanos()
            val recent = providers.mapNotNull { m.getLastKnownLocation(it) }
                .filter { (now - it.elapsedRealtimeNanos) / 1_000_000 < RECENT_MS }
                .maxByOrNull { it.elapsedRealtimeNanos }
            if (providers.isEmpty()) return settle(recent)
            // asked of each at once, the first place to come is used: with approximate permission
            // the fused provider stays at low power and never turns on GPS, so a phone without
            // network location (or the emulator) answers only through GPS
            var left = providers.size
            for (p in providers) {
                val sig = CancellationSignal()
                signals.add(sig)
                m.getCurrentLocation(p, sig, context.mainExecutor) { l ->
                    left--
                    if (l != null) settle(l) else if (left == 0) settle(recent)
                }
            }
            main.postDelayed({ settle(recent) }, LIMIT_MS)
        } catch (e: SecurityException) {
            Log.w(TAG, "$e")
            settle(null)
        }
    }
}
