package dev.summitstudio.uponthyhead

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.provider.OpenableColumns
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/**
 * Sharing a blessing and receiving one, for lib/share/share.dart on `upon_thy_head/share` (the
 * iPhone's is ios/Runner/Share.swift; the methods, keys and answers are the same).
 *
 *  - `text` {text, subject}, `link` {url, title}: Android's own share sheet with plain text
 *    (`text/plain`, the link alone as the text, so Messages, WhatsApp and Gmail make it a link)
 *  - `pdf` {…}: the PDF ([SharedPdf]) made in cache/share/ and handed over through [BlessingFiles]
 *  - `file` {fileName, bytes, title}: a `.blessing` file the same way, typed
 *    `application/vnd.uponthyhead.blessing`
 *  Each answers, once the share sheet has gone, whether a target was chosen (true) or not (false).
 *  - `copy` {text}: the clipboard, marked sensitive, so Android's copy preview shows dots, not the link
 *  - `dismiss`: close the share sheet now (the app locked); `clean`: empty cache/share/
 *  - `receiving`: Dart is ready; answers what came before (links and files) and sends later ones
 *    with `incoming` {link} | {bytes, name} | {tooLarge} | {unreadable}
 *
 * Android's share sheet is another activity. It is started for a result, so the app hears when it
 * closes and can close it itself ([dismiss]); while it is up, losing focus to it is not leaving the
 * app ([LockChannel.prompting]), as on iPhone, where the sheet is part of the app. Files made for a
 * share stay until the next share or the next launch: the app that received one may read it later
 * (Gmail reads an attachment when the mail is sent), so they are not removed when the sheet closes.
 */
object ShareChannel {
    private const val TAG = "share"
    const val REQUEST = 4207
    const val BLESSING_TYPE = "application/vnd.uponthyhead.blessing"

    /** The same limit as lib/share/blessing_file.dart's blessingFileMaxBytes. */
    const val MAX_BYTES = 512 * 1024

    var channel: MethodChannel? = null
    private var answer: MethodChannel.Result? = null
    private var chosen = false
    private var showing = false
    private var lastItems: List<Map<String, Any?>> = emptyList()

    // what arrived before Dart was ready
    private var listening = false
    private val waiting = mutableListOf<Map<String, Any?>>()

    fun folder(c: Context) = File(c.cacheDir, "share")

    fun handle(activity: () -> Activity?, context: Context, call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "text" -> send(activity(), result, plain(call.argument<String>("text") ?: "", call.argument<String>("subject") ?: ""), mapOf("kind" to "text"))
                "link" -> {
                    val url = call.argument<String>("url") ?: ""
                    val u = Uri.parse(url)
                    if (u.scheme != "https" && u.scheme != "http") return result.error("link", "not a link", null)
                    val d = mutableMapOf<String, Any?>("kind" to "url", "type" to "text/plain", "scheme" to u.scheme, "length" to url.length)
                    if (debuggable(context)) d["url"] = url // tests only: the link holds its key
                    send(activity(), result, plain(url, call.argument<String>("title") ?: ""), d)
                }
                "pdf" -> {
                    close()
                    clean(context)
                    val name = safeName(call.argument<String>("fileName"), "Blessing.pdf")
                    val f = File(folder(context).apply { mkdirs() }, name)
                    SharedPdf(context, call.arguments as Map<*, *>).write(f)
                    sendFile(activity(), context, result, f, "application/pdf", call.argument<String>("title") ?: "")
                }
                "file" -> {
                    close()
                    clean(context)
                    val name = safeName(call.argument<String>("fileName"), "Blessing.blessing")
                    val bytes = call.argument<ByteArray>("bytes") ?: return result.error("file", "no bytes", null)
                    val f = File(folder(context).apply { mkdirs() }, name)
                    f.writeBytes(bytes)
                    sendFile(activity(), context, result, f, BLESSING_TYPE, call.argument<String>("title") ?: "")
                }
                "copy" -> {
                    val cm = context.getSystemService(ClipboardManager::class.java)
                    val clip = ClipData.newPlainText("", call.argument<String>("text") ?: "")
                    clip.description.extras = PersistableBundle().apply { putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true) }
                    cm.setPrimaryClip(clip)
                    if (debuggable(context)) { // tests only: read back, the length and the flag, never the text
                        val back = cm.primaryClip
                        Log.i(TAG, "copied: ${clip.getItemAt(0).text.length} characters, read back " +
                            "${back?.getItemAt(0)?.text?.toString() == clip.getItemAt(0).text.toString()}, sensitive " +
                            "${back?.description?.extras?.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE) == true}")
                    }
                    result.success(null)
                }
                "receiving" -> {
                    listening = true
                    result.success(waiting.toList())
                    waiting.clear()
                }
                "dismiss" -> {
                    activity()?.finishActivity(REQUEST)
                    closed()
                    result.success(null)
                }
                "clean" -> {
                    clean(context)
                    result.success(null)
                }
                "debugShowing" -> result.success(showing)
                "debugPaper" -> result.success(if (SharedPdf.usesLetter()) "letter" else "a4")
                "debugItems" -> result.success(lastItems)
                "debugReceivedLeft" -> result.success(
                    context.filesDir.parentFile?.walkTopDown()?.filter { it.isFile && it.name.endsWith(".blessing", true) }
                        ?.map { it.path }?.toList() ?: emptyList<String>(),
                )
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.w(TAG, "${call.method}: ${e.javaClass.simpleName}")
            clean(context)
            result.error(call.method, e.javaClass.simpleName, null)
        }
    }

    private fun debuggable(c: Context) = (c.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0

    /** A name with no folder in it. */
    private fun safeName(n: String?, fallback: String) = n?.substringAfterLast('/')?.takeIf { it.isNotBlank() } ?: fallback

    private fun plain(text: String, title: String) = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_TEXT, text)
        // the sheet's heading names the blessing; no subject, which some messaging apps turn into an MMS
        if (title.isNotEmpty()) putExtra(Intent.EXTRA_TITLE, title)
    }

    private fun sendFile(a: Activity?, c: Context, result: MethodChannel.Result, f: File, type: String, title: String) {
        val uri = BlessingFiles.uriOf(c, f)
        val i = Intent(Intent.ACTION_SEND).apply {
            this.type = type
            putExtra(Intent.EXTRA_STREAM, uri)
            if (title.isNotEmpty()) putExtra(Intent.EXTRA_TITLE, title)
            clipData = ClipData(ClipDescription(f.name, arrayOf(type)), ClipData.Item(uri))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        send(a, result, i, mapOf("kind" to "file", "name" to f.name, "type" to type, "bytes" to f.length(), "path" to f.path, "uri" to uri.toString()))
    }

    private fun send(a: Activity?, result: MethodChannel.Result, i: Intent, item: Map<String, Any?>) {
        if (a == null) return result.error("share", "no window", null)
        close()
        lastItems = listOf(item)
        // what Android's share sheet is handed: the type and, for a file, its content address; never
        // the text (a link holds its key); debug builds only (a file's address holds its title)
        if (debuggable(a)) Log.i(TAG, "handed ${i.type}: ${item["kind"]}" + (item["uri"]?.let { ", $it" } ?: "") +
            (item["length"]?.let { ", $it characters" } ?: ""))
        chosen = false
        val back = Intent(CHOSEN).setPackage(a.packageName)
        val pi = PendingIntent.getBroadcast(a, 0, back, PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val chooser = Intent.createChooser(i, null, pi.intentSender)
        answer = result
        showing = true
        LockChannel.prompting = true
        a.startActivityForResult(chooser, REQUEST)
    }

    private const val CHOSEN = "dev.summitstudio.uponthyhead.SHARE_CHOSEN"

    /** A target was picked in the share sheet (Android says which; nothing of it is kept). */
    class Chosen : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            chosen = true
        }
    }

    fun register(c: Context) {
        c.applicationContext.registerReceiver(Chosen(), IntentFilter(CHOSEN), Context.RECEIVER_NOT_EXPORTED)
    }

    /** MainActivity.onActivityResult: the share sheet has gone. The chosen broadcast may come just
     *  after it, so the answer waits a moment for it. */
    fun closed() {
        if (!showing && answer == null) return
        showing = false
        LockChannel.prompting = false
        val a = answer
        answer = null
        Handler(Looper.getMainLooper()).postDelayed({ a?.success(chosen) }, 300)
    }

    /** An earlier sheet's answer, given now (a new one is starting). */
    private fun close() {
        val a = answer
        answer = null
        a?.success(false)
    }

    fun clean(c: Context) {
        folder(c).deleteRecursively()
    }

    // ---- receiving ----

    /** A blessing link or file this intent carries, read; null when it carries neither. */
    fun incoming(a: Activity, i: Intent?, link: String?): Boolean {
        if (link != null) {
            deliver(mapOf("link" to link))
            return true
        }
        if (i == null) return false
        val uri: Uri = when (i.action) {
            Intent.ACTION_VIEW -> i.data?.takeIf { it.scheme == "content" || it.scheme == "file" }
            Intent.ACTION_SEND -> @Suppress("DEPRECATION") (i.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri)
            else -> null
        } ?: return false
        val cr = a.contentResolver
        Thread {
            val item: Map<String, Any?> = try {
                val name = try {
                    cr.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
                } catch (e: Exception) {
                    null
                } ?: uri.lastPathSegment
                cr.openInputStream(uri)?.use { s ->
                    val buf = java.io.ByteArrayOutputStream()
                    val chunk = ByteArray(16 * 1024)
                    var over = false
                    while (true) {
                        val n = s.read(chunk)
                        if (n < 0) break
                        buf.write(chunk, 0, n)
                        if (buf.size() > MAX_BYTES) { over = true; break }
                    }
                    if (over) mapOf("tooLarge" to true) else mapOf("bytes" to buf.toByteArray(), "name" to name)
                } ?: mapOf("unreadable" to true)
            } catch (e: Exception) {
                Log.w(TAG, "receive: ${e.javaClass.simpleName}")
                mapOf("unreadable" to true)
            }
            Log.i(TAG, "receive: a file (${if (item.containsKey("bytes")) "read" else item.keys.first()}, type ${i.type ?: "none"})")
            Handler(Looper.getMainLooper()).post { deliver(item) }
        }.start()
        return true
    }

    private fun deliver(item: Map<String, Any?>) {
        val c = channel
        if (listening && c != null) c.invokeMethod("incoming", item) else waiting.add(item)
    }

    /** A new engine (the process lived on): Dart asks again. */
    fun reset() {
        listening = false
    }
}

/**
 * The PDF of a blessing, as the iPhone makes it (ios/Runner/Share.swift, `SharedPdf`): US Letter
 * where the region uses it, A4 elsewhere; an inch of margin; Newsreader from the Flutter assets
 * (Android's PDF writer embeds the font, subset, so the text is real and searchable); black on white.
 * The measures are the iPhone's, in points.
 */
class SharedPdf(private val context: Context, a: Map<*, *>) {
    private val title = a["title"] as? String ?: ""
    private val date = a["date"] as? String ?: ""
    private val from = a["from"] as? String ?: ""
    private val recipient = a["recipient"] as? String ?: ""
    private val pageOf = a["pageOf"] as? String ?: "{n} / {total}"
    private val paragraphs = (a["paragraphs"] as? List<*>)?.map { it.toString() } ?: emptyList()

    companion object {
        private val letterRegions = setOf("US", "CA", "MX", "CL", "CO", "CR", "GT", "PA", "PH", "PR", "SV", "VE", "NI", "BZ")
        fun usesLetter() = Locale.getDefault().country.ifEmpty { "US" } in letterRegions
        const val MARGIN = 72f
        const val BODY = 12.5f
        const val LEAD = 20.5f
        const val GAP = 10.25f
        const val FOOTER = 8.5f
    }

    private val fonts = mutableMapOf<String, Typeface>()

    /** Newsreader at the app's settings: regular weight, the optical size following the size. */
    private fun face(italic: Boolean, size: Float): Typeface {
        val asset = if (italic) "assets/fonts/Newsreader-Italic.ttf" else "assets/fonts/Newsreader.ttf"
        val opsz = min(72f, max(6f, size))
        return fonts.getOrPut("$asset $opsz") {
            try {
                val f = File(context.cacheDir, "fonts/" + asset.substringAfterLast('/'))
                if (!f.exists()) {
                    f.parentFile?.mkdirs()
                    val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(asset)
                    context.assets.open(key).use { i -> f.outputStream().use { o -> i.copyTo(o) } }
                }
                Typeface.Builder(f).setFontVariationSettings("'wght' 400, 'opsz' $opsz").build()
            } catch (e: Exception) {
                Typeface.create(Typeface.SERIF, if (italic) Typeface.ITALIC else Typeface.NORMAL)
            }
        }
    }

    private fun paint(italic: Boolean, size: Float, oldstyle: Boolean = false, gray: Float = 0f, tracking: Float = 0f) = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = face(italic, size)
        textSize = size
        val g = (gray * 255).toInt()
        color = Color.rgb(g, g, g)
        if (oldstyle) fontFeatureSettings = "'onum' 1"
        letterSpacing = tracking / size
        isSubpixelText = true
    }

    private class Line(val text: String, val paint: TextPaint)
    private class Placed(val line: Line, val x: Float, val baseline: Float)

    /** [s] broken into lines [width] wide; a hard line break inside it is kept. */
    private fun lines(s: String, p: TextPaint, width: Float): List<Line> {
        val out = mutableListOf<Line>()
        for (segment in s.split("\n")) {
            val t = segment.trim()
            if (t.isEmpty()) { out.add(Line("", p)); continue }
            val l = StaticLayout.Builder.obtain(t, 0, t.length, p, width.toInt())
                .setIncludePad(false)
                .setAlignment(Layout.Alignment.ALIGN_NORMAL)
                .setBreakStrategy(Layout.BREAK_STRATEGY_HIGH_QUALITY)
                .setHyphenationFrequency(Layout.HYPHENATION_FREQUENCY_NONE)
                .build()
            for (n in 0 until l.lineCount) out.add(Line(t.substring(l.getLineStart(n), l.getLineEnd(n)).trimEnd(), p))
        }
        return out
    }

    fun write(f: File) {
        val letter = usesLetter()
        val pw = if (letter) 612 else 595
        val ph = if (letter) 792 else 842
        val m = MARGIN
        val width = pw - 2 * m
        val top = m
        val bottom = ph - m
        val pages = mutableListOf(mutableListOf<Placed>())
        var y = top
        fun put(ls: List<Line>, leading: Float, ascent: Float) {
            for (l in ls) { pages.last().add(Placed(l, m, y + ascent)); y += leading }
        }
        put(lines(date, paint(false, 9.5f, oldstyle = true, tracking = 0.1f), width), 14f, 10f)
        y += 10
        put(lines(title, paint(false, 26f, tracking = -0.3f), width), 31f, 25f)
        if (from.isNotEmpty()) { y += 5; put(lines(from, paint(true, 13.5f), width), 19f, 14f) }
        if (recipient.isNotEmpty()) { y += if (from.isEmpty()) 6 else 1; put(lines(recipient, paint(false, 11f), width), 16f, 12f) }
        y += 16
        val ruleY = y
        y += 26

        val body = paint(false, BODY, oldstyle = true)
        val ascent = 13f
        var pageTop = false
        for (para in paragraphs) {
            val ls = lines(para, body, width)
            var i = 0
            if (!pageTop && y > top + 1) y += GAP
            while (i < ls.size) {
                val fit = max(0, floor((bottom - y) / LEAD + 0.001f).toInt())
                val left = ls.size - i
                var take = min(fit, left)
                if (take < left) {
                    if (left - take == 1) take = max(0, take - 1)
                    if (i == 0 && take == 1) take = 0
                    if (take <= 0 && pageTop) take = max(1, min(fit, left))
                }
                for (l in ls.subList(i, i + max(0, take))) {
                    pages.last().add(Placed(l, m, y + ascent)); y += LEAD; pageTop = false
                }
                i += max(0, take)
                if (i < ls.size) { pages.add(mutableListOf()); y = top; pageTop = true }
            }
        }

        val doc = PdfDocument()
        val footer = paint(false, FOOTER, oldstyle = true, gray = 0.35f)
        try {
            for ((n, placed) in pages.withIndex()) {
                val page = doc.startPage(PdfDocument.PageInfo.Builder(pw, ph, n + 1).create())
                val c = page.canvas
                if (n == 0) {
                    val rule = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK; strokeWidth = 0.5f }
                    c.drawLine(m, ruleY, m + 96, ruleY, rule)
                }
                for (p in placed) c.drawText(p.line.text, p.x, p.baseline, p.line.paint)
                if (n > 0) {
                    val numbers = pageOf.replace("{n}", "${n + 1}").replace("{total}", "${pages.size}")
                    val rw = footer.measureText(numbers)
                    val left = TextUtils.ellipsize(title, footer, width - rw - 24, TextUtils.TruncateAt.END).toString()
                    val base = ph - m + 34
                    c.drawText(left, m, base, footer)
                    c.drawText(numbers, m + width - rw, base, footer)
                }
                doc.finishPage(page)
            }
            f.outputStream().use { doc.writeTo(it) }
        } finally {
            doc.close()
        }
    }
}
