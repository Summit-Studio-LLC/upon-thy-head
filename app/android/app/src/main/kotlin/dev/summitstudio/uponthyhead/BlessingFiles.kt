package dev.summitstudio.uponthyhead

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

/**
 * The files the app shares (a PDF or a `.blessing` file in cache/share/), handed to the app that
 * receives them by a `content://` address, so no storage permission is ever asked. It is AndroidX's
 * FileProvider cut down to what is needed, without the dependency, and with one difference that
 * matters: a `.blessing` file reports its own type, `application/vnd.uponthyhead.blessing`, where
 * FileProvider would answer `application/octet-stream` for an extension Android does not know.
 *
 * Read only, one folder, not exported: an app sees a file only with the grant on the share intent.
 */
class BlessingFiles : ContentProvider() {
    companion object {
        fun authority(c: Context) = "${c.packageName}.files"

        fun uriOf(c: Context, f: File): Uri = Uri.Builder().scheme("content").authority(authority(c)).appendPath("share").appendPath(f.name).build()

        fun typeOf(name: String) = when {
            name.endsWith(".blessing", true) -> ShareChannel.BLESSING_TYPE
            name.endsWith(".pdf", true) -> "application/pdf"
            else -> "application/octet-stream"
        }
    }

    override fun onCreate() = true

    private fun fileOf(uri: Uri): File {
        val c = context ?: throw FileNotFoundException()
        val seg = uri.pathSegments
        if (seg.size != 2 || seg[0] != "share") throw FileNotFoundException()
        val dir = ShareChannel.folder(c).canonicalFile
        val f = File(dir, seg[1]).canonicalFile
        if (f.parentFile != dir || !f.isFile) throw FileNotFoundException()
        return f
    }

    override fun getType(uri: Uri): String? = uri.lastPathSegment?.let(::typeOf)

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, args: Array<out String>?, sort: String?): Cursor {
        val f = fileOf(uri)
        val cols = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val known = cols.filter { it == OpenableColumns.DISPLAY_NAME || it == OpenableColumns.SIZE }.toTypedArray()
        return MatrixCursor(known, 1).apply {
            addRow(known.map { if (it == OpenableColumns.DISPLAY_NAME) f.name else f.length() })
        }
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw SecurityException("read only")
        return ParcelFileDescriptor.open(fileOf(uri), ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException()
    override fun delete(uri: Uri, selection: String?, args: Array<out String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, args: Array<out String>?) = 0
}
