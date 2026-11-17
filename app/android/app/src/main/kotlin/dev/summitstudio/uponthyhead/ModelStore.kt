package dev.summitstudio.uponthyhead

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/**
 * The speech model, downloaded only after the person taps Download (docs/android-plan.md 3.5).
 *
 * What it is (name, address, size, SHA-256) is decided on the Dart side (lib/record/words_model.dart)
 * and handed over with each request. It is kept in the app's no-backup folder: private to the app,
 * never in Android's backup, out of reach of other apps. It is written to `<name>.part` and becomes
 * `<name>` only once its size and SHA-256 are right; a file that is wrong is deleted and refused.
 *
 * The download runs on its own thread while the app's process lives (no background service): leave
 * the app and it goes on; lose the connection and it waits for one, then carries on from the byte it
 * had (an HTTP range request; a server that will not resume starts it again from the beginning).
 * The app killed: the next launch carries on, because the person's Download is remembered until the
 * model is there or they remove it.
 */
class ModelStore(private val context: Context, private val changed: (Map<String, Any?>) -> Unit) {
    companion object {
        private const val TAG = "model"

        /** Room kept free beyond the model itself, so the phone is never filled to the brim. */
        const val MARGIN = 50L * 1024 * 1024
    }

    data class Spec(val name: String, val url: String, val bytes: Long, val sha256: String)

    private val dir = File(context.noBackupFilesDir, "models").also { it.mkdirs() }
    private val prefs = context.getSharedPreferences("model", Context.MODE_PRIVATE)
    private val main = Handler(Looper.getMainLooper())
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)

    @Volatile private var thread: Thread? = null
    @Volatile private var stopping = false
    @Volatile private var state = "absent"
    @Volatile private var problem: String? = null
    @Volatile private var lastSent = 0L

    fun file(spec: Spec) = File(dir, spec.name)
    private fun part(spec: Spec) = File(dir, spec.name + ".part")

    /** The model, if it is on the phone whole (checked when it arrived). */
    fun ready(spec: Spec): File? = file(spec).takeIf { it.isFile && it.length() == spec.bytes }

    /** The Download the person tapped, remembered until the model is here or removed. */
    fun wanted(): Spec? {
        val url = prefs.getString("url", null) ?: return null
        return Spec(prefs.getString("name", "")!!, url, prefs.getLong("bytes", 0), prefs.getString("sha256", "")!!)
    }

    private fun freeBytes(): Long {
        // tests, in a debuggable build only: pretend the phone has this much room
        val debuggable = context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0
        val fake = File(context.filesDir, "debug_free_bytes")
        if (debuggable && fake.exists()) fake.readText().trim().toLongOrNull()?.let { return it }
        return StatFs(dir.path).availableBytes
    }

    private fun network(): Pair<Boolean, Boolean> {
        val caps = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
        val online = caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
        return online to connectivity.isActiveNetworkMetered
    }

    /** Everything the screens need. */
    fun describe(spec: Spec): Map<String, Any?> {
        val (online, metered) = network()
        val s = when {
            ready(spec) != null -> "ready"
            thread != null -> state
            problem != null -> "failed"
            else -> "absent"
        }
        val have = if (s == "ready") spec.bytes else part(spec).let { if (it.exists()) it.length() else 0L }
        return mapOf(
            "state" to s, // absent, downloading, waiting (for a connection), checking, ready, failed
            "problem" to problem, // checksum, room, server, null
            "got" to have,
            "total" to spec.bytes,
            "size" to if (s == "ready") file(spec).length() else 0L,
            "free" to freeBytes(),
            "needed" to (spec.bytes - have + MARGIN),
            "online" to online,
            "metered" to metered,
            "wanted" to (wanted()?.url == spec.url),
        )
    }

    private fun send(spec: Spec, force: Boolean = false) {
        val now = System.currentTimeMillis()
        if (!force && now - lastSent < 250) return
        lastSent = now
        val d = describe(spec)
        main.post { changed(d) }
    }

    /** The person tapped Download (or the app opened again after they had). */
    @Synchronized
    fun download(spec: Spec) {
        if (ready(spec) != null) return send(spec, true)
        prefs.edit().putString("url", spec.url).putString("name", spec.name).putLong("bytes", spec.bytes)
            .putString("sha256", spec.sha256).apply()
        if (thread != null) return send(spec, true)
        problem = null
        stopping = false
        state = "downloading"
        thread = Thread({ run(spec) }, "model-download").also { it.start() }
        send(spec, true)
    }

    /** Stop and forget the Download, removing what had come. */
    @Synchronized
    fun cancel(spec: Spec) {
        stopping = true
        thread?.interrupt()
        prefs.edit().clear().apply()
        thread?.join(3000)
        thread = null
        part(spec).delete()
        problem = null
        send(spec, true)
    }

    /** Settings: take the model off the phone. */
    @Synchronized
    fun remove(spec: Spec) {
        cancel(spec)
        file(spec).delete()
        dir.listFiles()?.forEach { it.delete() }
        send(spec, true)
    }

    private fun run(spec: Spec) {
        var wait = 2000L
        try {
            while (!stopping) {
                try {
                    if (fetch(spec)) break
                    wait = 2000L
                } catch (e: RoomException) {
                    problem = "room"
                    Log.w(TAG, "not enough room: ${e.message}")
                    break
                } catch (e: ChecksumException) {
                    problem = "checksum"
                    Log.w(TAG, "refused: ${e.message}")
                    break
                } catch (e: ServerException) {
                    problem = "server"
                    Log.w(TAG, "server: ${e.message}")
                    break
                } catch (e: IOException) {
                    if (stopping) break
                    // lost the connection: wait for one, then carry on from where it stopped
                    Log.i(TAG, "interrupted at ${part(spec).length()} bytes: $e; waiting for a connection")
                    state = "waiting"
                    send(spec, true)
                    waitForNetwork(wait)
                    wait = (wait * 2).coerceAtMost(30_000)
                    state = "downloading"
                }
            }
        } catch (e: InterruptedException) {
            // cancelled
        } finally {
            if (thread === Thread.currentThread()) thread = null
            send(spec, true)
        }
    }

    /** Sleeps until a network with the internet is there (at most [ms], then tries anyway). */
    private fun waitForNetwork(ms: Long) {
        val lock = Object()
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = synchronized(lock) { lock.notifyAll() }
        }
        runCatching { connectivity.registerDefaultNetworkCallback(cb) }
        try {
            synchronized(lock) { lock.wait(ms) }
        } finally {
            runCatching { connectivity.unregisterNetworkCallback(cb) }
        }
    }

    private class RoomException(m: String) : Exception(m)
    private class ChecksumException(m: String) : Exception(m)
    private class ServerException(m: String) : Exception(m)

    /** One attempt. True when the model is in place. */
    private fun fetch(spec: Spec): Boolean {
        val part = part(spec)
        var have = if (part.exists()) part.length() else 0L
        if (have > spec.bytes) { part.delete(); have = 0 }
        if (have < spec.bytes) {
            val needed = spec.bytes - have + MARGIN
            val free = freeBytes()
            if (free < needed) throw RoomException("$free free, $needed needed")
            val c = URL(spec.url).openConnection() as HttpURLConnection
            c.connectTimeout = 15_000
            c.readTimeout = 20_000
            c.instanceFollowRedirects = true
            c.setRequestProperty("Accept-Encoding", "identity")
            if (have > 0) c.setRequestProperty("Range", "bytes=$have-")
            try {
                val code = c.responseCode
                Log.i(TAG, "GET ${c.url.host} → $code from byte $have")
                val append = when {
                    code == 206 && have > 0 -> true
                    code == 200 -> { have = 0; false } // the server would not resume: start again
                    code == 416 -> true // nothing more to send
                    code in 500..599 -> throw IOException("server $code")
                    else -> throw ServerException("HTTP $code")
                }
                if (code != 416) {
                    FileOutputStream(part, append).use { out ->
                        c.inputStream.use { inp ->
                            val buf = ByteArray(64 * 1024)
                            while (true) {
                                if (stopping || Thread.interrupted()) throw InterruptedException()
                                val n = inp.read(buf)
                                if (n < 0) break
                                out.write(buf, 0, n)
                                have += n
                                if (have > spec.bytes) break
                                send(spec)
                            }
                            out.fd.sync()
                        }
                    }
                }
            } finally {
                c.disconnect()
            }
            if (part.length() < spec.bytes) throw IOException("ended at ${part.length()} of ${spec.bytes}")
        }
        state = "checking"
        send(spec, true)
        val sha = sha256(part)
        if (part.length() != spec.bytes || !sha.equals(spec.sha256, ignoreCase = true)) {
            part.delete()
            prefs.edit().clear().apply()
            throw ChecksumException("${part.length()} bytes, SHA-256 $sha; expected ${spec.bytes}, ${spec.sha256}")
        }
        if (!part.renameTo(file(spec))) throw IOException("could not put the model in place")
        prefs.edit().clear().apply()
        state = "ready"
        Log.i(TAG, "the model is here and checked (${spec.name}, ${spec.bytes} bytes)")
        return true
    }

    private fun sha256(f: File): String {
        val md = MessageDigest.getInstance("SHA-256")
        f.inputStream().use { i ->
            val buf = ByteArray(1 shl 16)
            while (true) {
                val n = i.read(buf)
                if (n < 0) break
                md.update(buf, 0, n)
            }
        }
        return md.digest().joinToString("") { "%02x".format(it) }
    }
}
