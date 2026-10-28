package com.mightyoung.muyon.study

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

object StudyFiles {
    private const val FILE_LIMIT = 64L * 1024 * 1024
    private const val BACKUP_LIMIT = 256L * 1024 * 1024
    fun saveResource(context: Context, uri: Uri): JSONObject {
        var title = "附件"
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) title = c.getString(0) ?: title
        }
        val id = UUID.randomUUID().toString()
        val relative = "resources/$id/${safeName(title)}"
        val file = safeFile(context, relative); file.parentFile!!.mkdirs()
        try {
            context.contentResolver.openInputStream(uri)?.use { input -> file.outputStream().use { copyBounded(input, it, FILE_LIMIT) } } ?: error("无法读取附件")
            return JSONObject().put("id", id).put("title", title).put("type", "file").put("path", relative).put("mime", context.contentResolver.getType(uri) ?: "application/octet-stream").put("size", file.length())
        } catch (e: Exception) { file.parentFile?.deleteRecursively(); throw e }
    }
    fun openResource(context: Context, resource: JSONObject) {
        if(resource.optString("type")=="video") {
            val url=resource.getString("url");require(url.startsWith("https://")||url.startsWith("http://")){"无效视频链接"}
            context.startActivity(Intent(Intent.ACTION_VIEW,Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));return
        }
        val file = safeFile(context, resource.getString("path")); require(file.isFile) { "附件文件不存在" }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        context.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, resource.optString("mime", "application/octet-stream")).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK))
    }
    fun exportBackup(context: Context, state: JSONObject, out: OutputStream) {
        val refs = resources(state)
        refs.forEach { require(safeFile(context, it.getString("path")).isFile) { "附件缺失，备份未完成" } }
        val stateBytes=state.toString().toByteArray();require(stateBytes.size<=24*1024*1024){"备份状态超过24MB"}
        ZipOutputStream(out).use { zip ->
            zip.putNextEntry(ZipEntry("state.json")); zip.write(stateBytes); zip.closeEntry()
            var total = stateBytes.size.toLong()
            refs.distinctBy { it.getString("path") }.forEach { resource ->
                val path = resource.getString("path"); val file = safeFile(context, path)
                total += file.length(); require(total <= BACKUP_LIMIT) { "备份附件总计超过256MB" }
                zip.putNextEntry(ZipEntry(path)); file.inputStream().use { copyBounded(it, zip, FILE_LIMIT) }; zip.closeEntry()
            }
        }
    }
    /** Stages into fresh resource paths. Existing files are never overwritten, even on failure. */
    fun readBackup(context: Context, input: InputStream): JSONObject {
        val stage = File(context.cacheDir, "restore-${UUID.randomUUID()}").apply { mkdirs() }
        val installed = mutableListOf<File>()
        try {
            val entries = mutableMapOf<String, File>(); var total = 0L
            ZipInputStream(input).use { zip -> while (true) {
                val entry = zip.nextEntry ?: break
                require(entries.size < 4096 && validPath(entry.name)) { "备份包含不安全路径" }
                if (entry.isDirectory) continue
                require(entry.name == "state.json" || entry.name.startsWith("resources/")) { "备份包含未知文件" }
                require(!entries.containsKey(entry.name)) { "备份包含重复文件" }
                val file = File(stage, entry.name); file.parentFile!!.mkdirs()
                file.outputStream().use { total += copyBounded(zip, it, if (entry.name == "state.json") 24L * 1024 * 1024 else FILE_LIMIT) }
                require(total <= BACKUP_LIMIT) { "备份解压后超过256MB" }; entries[entry.name] = file
            } }
            val state = JSONObject((entries["state.json"] ?: error("备份缺少state.json")).readText())
            val refs = resources(state)
            val replacements = mutableMapOf<String, String>()
            refs.forEach { ref ->
                val old = ref.getString("path")
                require(validPath(old) && old.startsWith("resources/") && entries[old]?.isFile == true) { "备份缺少附件: $old" }
            }
            refs.forEach { ref ->
                val old = ref.getString("path")
                val relative = replacements.getOrPut(old) {
                    val path = "resources/${UUID.randomUUID()}/${safeName(File(old).name)}"
                    val target = safeFile(context, path); target.parentFile!!.mkdirs(); installed.add(target.parentFile!!)
                    entries.getValue(old).inputStream().use { src -> target.outputStream().use { dst -> copyBounded(src, dst, FILE_LIMIT) } }
                    path
                }
                ref.put("path", relative)
            }
            return state
        } catch (e: Exception) { installed.forEach { it.deleteRecursively() }; throw e }
        finally { stage.deleteRecursively() }
    }
    private fun resources(state: JSONObject): List<JSONObject> {
        val refs = mutableListOf<JSONObject>()
        fun visit(value: Any?) { when (value) {
            is JSONObject -> {
                if (value.has("path") && value.optString("type") in listOf("file", "example")) refs.add(value)
                value.keys().forEach { visit(value.opt(it)) }
            }
            is JSONArray -> for (i in 0 until value.length()) visit(value.opt(i))
        } }
        visit(state); return refs
    }
    private fun validPath(path: String) = path.isNotBlank() && !path.startsWith('/') && !path.contains('\\') && !path.contains('\u0000') && path.split('/').none { it == ".." || it == "." || it.isEmpty() }
    private fun safeFile(context: Context, path: String): File {
        require(validPath(path) && path.startsWith("resources/")) { "无效附件路径" }
        val base = File(context.filesDir, "resources").canonicalFile
        val file = File(context.filesDir, path).canonicalFile
        require(file.path.startsWith(base.path + File.separator)) { "附件路径越界" }; return file
    }
    private fun safeName(name: String) = name.replace(Regex("[^\\p{L}\\p{N}._ -]"), "_").take(160).trim().takeIf { it.isNotEmpty() && it != "." && it != ".." } ?: "附件"
    private fun copyBounded(input: InputStream, out: OutputStream, limit: Long): Long {
        val buffer = ByteArray(8192); var count = 0L
        while (true) { val n = input.read(buffer); if (n < 0) break; count += n; require(count <= limit) { "文件超过允许大小" }; out.write(buffer, 0, n) }
        return count
    }
}
