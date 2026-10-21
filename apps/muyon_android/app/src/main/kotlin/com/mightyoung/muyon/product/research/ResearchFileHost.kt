package com.mightyoung.muyon.product.research

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.util.Base64
import com.mightyoung.muyon.product.agentipc.ProductClient
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.InputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.zip.ZipInputStream

internal class ResearchReadFailure(val status: String, val code: String) :
    IllegalStateException("$status: $code")

/** User-selected documents are streams only; no provider path is passed to Rust. */
internal class ResearchFileHost(private val context: Context, private val client: ProductClient) : AutoCloseable {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val staged = mutableListOf<String>()
    private val viewers = mutableListOf<PrivatePdf>()
    @Volatile private var closed = false
    private val singleLimit = 30L * 1024 * 1024
    private val totalLimit = 150L * 1024 * 1024

    fun <T> run(task: () -> T, result: (Result<T>) -> Unit) {
        if (closed) return
        worker.execute { val answer = runCatching(task); main.post { if (!closed) result(answer) } }
    }

    override fun close() {
        if (closed) return
        closed = true
        // Finish already queued reads, then release private renderers. Uploads
        // remain recoverable: leaving a tab never aborts an uncertain write.
        worker.execute { viewers.forEach { it.close() }; viewers.clear() }
        worker.shutdown()
    }

    private fun rpc(method: String, payload: JSONObject = JSONObject()): Any {
        check(Looper.myLooper() != Looper.getMainLooper())
        val latch = CountDownLatch(1)
        var response: JSONObject? = null
        main.post { client.call(method, payload) { response = it; latch.countDown() } }
        check(latch.await(35, TimeUnit.SECONDS)) { "响应未知，请检查原操作" }
        val reply = requireNotNull(response)
        if (reply.optString("status") != "ok") throw ResearchReadFailure(reply.optString("status"), reply.optString("error"))
        return reply.opt("data") ?: JSONObject.NULL
    }

    private fun path(value: String): String {
        require(value.isNotBlank() && value.length <= 1024 && !value.contains('\\') && !value.contains(':') &&
            value.none { it.isISOControl() } && value.split('/').none { it.isEmpty() || it == "." || it == ".." }) { "文件路径不受支持" }
        return value
    }

    private fun upload(project: String, input: InputStream, kind: String, budget: LongArray): JSONObject {
        val upload = (rpc("begin_upload", JSONObject().put("project_id", project)) as JSONObject).getString("upload_id")
        staged += upload
        var size = 0L
        input.use { stream ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val count = stream.read(buffer)
                if (count < 0) break
                if (count == 0) continue
                size += count; budget[0] += count
                require(size <= (if (kind == "archive") totalLimit else singleLimit) && budget[0] <= totalLimit) {
                    "普通文件超过30MiB、ZIP超过150MiB或总量超过150MiB"
                }
                rpc("append_upload", JSONObject().put("upload_id", upload)
                    .put("bytes", Base64.encodeToString(buffer, 0, count, Base64.NO_WRAP)))
            }
        }
        return rpc("finish_upload", JSONObject().put("upload_id", upload).put("kind", kind)) as JSONObject
    }

    fun pdf(project: String, uri: Uri): JSONObject = upload(project,
        requireNotNull(context.contentResolver.openInputStream(uri)), "pdf", longArrayOf(0))

    fun directory(project: String, uri: Uri): JSONObject {
        val entries = JSONArray()
        val budget = longArrayOf(0)
        val seen = mutableSetOf<String>()
        fun visit(id: String, prefix: String, depth: Int) {
            require(depth <= 64 && seen.add(id) && seen.size <= 10000) { "目录循环、层级或数量超限" }
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(uri, id)
            context.contentResolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_FLAGS), null, null, null)?.use { cursor ->
                while (cursor.moveToNext()) {
                    val child = cursor.getString(0)
                    val name = cursor.getString(1)
                    require(!name.contains('/')) { "不支持的文档名称" }
                    val relative = path(if (prefix.isEmpty()) name else "$prefix/$name")
                    require(cursor.getInt(3) and DocumentsContract.Document.FLAG_VIRTUAL_DOCUMENT == 0) { "不支持虚拟文件" }
                    if (cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) visit(child, relative, depth + 1)
                    else {
                        require(entries.length() < 10000) { "文件数量超限" }
                        val document = DocumentsContract.buildDocumentUriUsingTree(uri, child)
                        val finished = upload(project, requireNotNull(context.contentResolver.openInputStream(document)), "document", budget)
                        entries.put(JSONObject().put("relative_path", relative).put("upload_id", finished.getString("upload_id")))
                    }
                }
            } ?: error("无法读取目录")
        }
        visit(DocumentsContract.getTreeDocumentId(uri), "", 0)
        return (rpc("seal_snapshot", JSONObject().put("project_id", project).put("entries", entries)) as JSONObject)
            .also { staged += it.getString("snapshot_upload_id") }
    }

    fun archive(project: String, uri: Uri): JSONObject {
        val budget = longArrayOf(0)
        val archive = upload(project, requireNotNull(context.contentResolver.openInputStream(uri)), "archive", longArrayOf(0))
        val archiveId = archive.getString("upload_id")
        // Rust validates the central directory, flags, symlinks and budgets
        // before the platform decoder is allowed to inflate a single entry.
        rpc("archive_manifest", JSONObject().put("upload_id", archiveId))
        val entries = JSONArray()
        val paths = mutableSetOf<String>()
        val reader = (rpc("open_upload_reader", JSONObject().put("upload_id", archiveId)) as JSONObject).getString("reader_id")
        val frozenInput = object : InputStream() {
            private var chunk = ByteArray(0)
            private var offset = 0
            private var ended = false
            override fun read(): Int {
                val byte = ByteArray(1)
                return if (read(byte, 0, 1) < 0) -1 else byte[0].toInt() and 255
            }
            override fun read(target: ByteArray, off: Int, len: Int): Int {
                if (len == 0) return 0
                if (offset == chunk.size && !ended) {
                    val reply = rpc("read_attachment", JSONObject().put("reader_id", reader).put("max_bytes", 64 * 1024)) as JSONObject
                    chunk = Base64.decode(reply.getString("bytes"), Base64.DEFAULT)
                    offset = 0
                    ended = chunk.isEmpty()
                }
                if (ended) return -1
                val count = minOf(len, chunk.size - offset)
                chunk.copyInto(target, off, offset, offset + count)
                offset += count
                return count
            }
            override fun close() { rpc("close_attachment", JSONObject().put("reader_id", reader)) }
        }
        ZipInputStream(frozenInput).use { zip ->
            var count = 0
            while (true) {
                val entry = zip.nextEntry ?: break
                require(++count <= 10000) { "文件数量超限" }
                if (!entry.isDirectory) {
                    val relative = path(entry.name)
                    require(paths.add(relative)) { "重复文件路径" }
                    // Keep ZipInputStream open until every entry has been decoded.
                    val nonClosing = object : InputStream() {
                        override fun read(): Int = zip.read()
                        override fun read(b: ByteArray, off: Int, len: Int): Int = zip.read(b, off, len)
                    }
                    val finished = upload(project, nonClosing, "document", budget)
                    entries.put(JSONObject().put("relative_path", relative).put("upload_id", finished.getString("upload_id")))
                }
                zip.closeEntry()
            }
        }
        return (rpc("seal_snapshot", JSONObject().put("project_id", project).put("entries", entries)
            .put("archive_upload_id", archiveId)) as JSONObject).also { staged += it.getString("snapshot_upload_id") }
    }

    /** Called only after an explicit pre-confirm discard/failure, never after an unknown write. */
    fun discard() {
        staged.toList().forEach { id -> runCatching { rpc("abort_upload", JSONObject().put("upload_id", id)) } }
        staged.clear()
    }

    fun attachment(project: String, paper: String, blob: JSONObject): PrivatePdf {
        val opened = rpc("open_attachment", JSONObject().put("project_id", project).put("paper_id", paper)
            .put("digest", blob.getString("digest"))) as JSONObject
        val reader = opened.getString("reader_id")
        val file = File.createTempFile("muyon-paper-", ".pdf", context.cacheDir)
        try {
            var length = 0L
            file.outputStream().use { output ->
                while (true) {
                    val chunk = rpc("read_attachment", JSONObject().put("reader_id", reader).put("max_bytes", 64 * 1024))
                    val bytes = Base64.decode((chunk as JSONObject).getString("bytes"), Base64.DEFAULT)
                    if (bytes.isEmpty()) break
                    length += bytes.size
                    require(length <= singleLimit) { "附件超过30MiB" }
                    output.write(bytes)
                }
            }
            return PrivatePdf(file).also { viewers += it }
        } catch (error: Exception) {
            file.delete()
            throw error
        } finally { runCatching { rpc("close_attachment", JSONObject().put("reader_id", reader)) } }
    }

    fun currentPaper(project: String, paper: String): JSONObject =
        rpc("paper", JSONObject().put("project_id", project).put("paper_id", paper)) as JSONObject
}

internal class PrivatePdf(private val file: File) : AutoCloseable {
    private val descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    private val renderer = try { PdfRenderer(descriptor) } catch (error: Exception) { descriptor.close(); throw error }
    private var closed = false
    val pages: Int get() = renderer.pageCount
    @Synchronized fun render(index: Int): Bitmap = renderer.openPage(index).use { page ->
        val scale = minOf(1.5f, 1600f / maxOf(page.width, page.height))
        Bitmap.createBitmap((page.width * scale).toInt().coerceAtLeast(1),
            (page.height * scale).toInt().coerceAtLeast(1), Bitmap.Config.ARGB_8888).also {
            it.eraseColor(Color.WHITE)
            page.render(it, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
        }
    }
    @Synchronized override fun close() { if (!closed) { closed = true; renderer.close(); descriptor.close(); file.delete() } }
}
