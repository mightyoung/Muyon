package com.mightyoung.muyon.product.ml

import android.content.Context
import android.os.Build
import android.system.Os
import android.system.OsConstants
import org.json.JSONArray
import java.io.Closeable
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest

/** Frozen application models only. No arbitrary model import or network fallback. */
internal class LocalModels(private val context: Context) {
    companion object {
        const val IDENTITY = "eg2-q8:2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135:llama-b11763:768:det-a431985659dc921974177a95adcfbb90fd9e51989a5e04d70d0b75f597b6e61d:rec-da72dc72ca4dc220df0dfde68c1dedc31c58d3e76a25871122e5056227d50092:dict-d858428fbe0ada92b439a5f277b51bc1b318fd985d80946a3ce859d7f2446a92:bgr-v1:chunk192-v1"
        private val lock = Any()
        private val verified = ModelFileVerificationCache()
        private val expected = linkedMapOf(
            "embedding.gguf" to (309855456L to "2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135"),
            "det.onnx" to (4826518L to "a431985659dc921974177a95adcfbb90fd9e51989a5e04d70d0b75f597b6e61d"),
            "rec.onnx" to (16534782L to "da72dc72ca4dc220df0dfde68c1dedc31c58d3e76a25871122e5056227d50092"),
            "dictionary.json" to (110788L to "d858428fbe0ada92b439a5f277b51bc1b318fd985d80946a3ce859d7f2446a92")
        )
    }
    private val directory = File(context.noBackupFilesDir, "local-models-v1")
    fun install(checkCancelled: () -> Unit = {}): Map<String, File> = installNames(expected.keys, checkCancelled)

    /** Searches do not need to install or validate either OCR network or its dictionary. */
    fun installEmbedding(checkCancelled: () -> Unit = {}): File =
        installNames(setOf("embedding.gguf"), checkCancelled).getValue("embedding.gguf")

    fun embeddingIdentity(file: File): String {
        val stat = Os.lstat(file.absolutePath)
        check(OsConstants.S_ISREG(stat.st_mode)) { "本地模型文件不可用" }
        // API 26 has just been fully rehashed by installEmbedding; inode changes still retire a
        // previously mapped handle. Later APIs additionally detect nanosecond metadata changes.
        return "$IDENTITY:${file.absolutePath}:${stat.st_dev}:${stat.st_ino}:${stat.st_size}:" +
            (modelFingerprint(file) ?: "${stat.st_mode}:${stat.st_mtime}:${stat.st_ctime}")
    }

    private fun installNames(names: Set<String>, checkCancelled: () -> Unit): Map<String, File> = synchronized(lock) {
        check(directory.isDirectory || directory.mkdirs()) { "本地模型目录不可用" }
        expected.filterKeys { it in names }.mapValues { (name, identity) ->
            checkCancelled()
            val (bytes, digest) = identity
            val target = File(directory, name)
            if (!verified.verify(target, bytes, digest, checkCancelled)) {
                val part = File(directory, "$name.part")
                try {
                    context.assets.open("local-models/$name").use { input ->
                        FileOutputStream(part).use { output ->
                            val buffer = ByteArray(65536)
                            var size = 0L
                            while (true) {
                                checkCancelled()
                                val count = input.read(buffer); if (count < 0) break
                                size += count; check(size <= bytes) { "本地模型大小不符" }
                                output.write(buffer, 0, count)
                            }
                            check(size == bytes) { "本地模型不完整" }
                            output.fd.sync()
                        }
                    }
                    check(modelHash(part, checkCancelled) == digest) { "本地模型校验失败" }
                    checkCancelled()
                    check(part.renameTo(target)) { "本地模型安装失败" }
                } finally { part.delete() }
            }
            target
        }
    }
    fun open(checkCancelled: () -> Unit = {}): ModelRuntime {
        val files = install(checkCancelled)
        val ocr = openOcrFiles(files)
        try {
            checkCancelled()
            return ModelRuntime(ocr, LocalEmbedding(files.getValue("embedding.gguf")))
        } catch (error: Throwable) { ocr.close(); throw error }
    }

    fun openOcr(checkCancelled: () -> Unit = {}): LocalOcr = openOcrFiles(
        installNames(expected.keys - "embedding.gguf", checkCancelled))

    private fun openOcrFiles(files: Map<String, File>): LocalOcr {
        val dictionary = JSONArray(files.getValue("dictionary.json").readText()).let { array ->
            (0 until array.length()).map(array::getString)
        }
        return LocalOcr(files.getValue("det.onnx"), files.getValue("rec.onnx"), dictionary)
    }
}

/** Positive, process-only integrity receipts; no model handles, text, vectors or business scope. */
internal class ModelFileVerificationCache(
    private val fingerprint: (File) -> String? = ::modelFingerprint,
    private val hash: (File, () -> Unit) -> String = ::modelHash,
) {
    private data class Receipt(val bytes: Long, val digest: String, val fingerprint: String)
    private val receipts = linkedMapOf<String, Receipt>()

    @Synchronized
    fun verify(file: File, bytes: Long, digest: String, checkCancelled: () -> Unit = {}): Boolean {
        checkCancelled()
        val key = file.absolutePath
        if (!file.isFile || file.length() != bytes) { receipts.remove(key); return false }
        val before = fingerprint(file)
        val receipt = receipts[key]
        if (before != null && receipt == Receipt(bytes, digest, before)) return true
        receipts.remove(key)
        if (hash(file, checkCancelled) != digest) return false
        checkCancelled()
        val after = fingerprint(file)
        // Never reuse a receipt if a file changed during hashing, or precise metadata is unavailable.
        if (before != after) return false
        if (after != null) {
            if (receipts.size >= 4) receipts.remove(receipts.keys.first())
            receipts[key] = Receipt(bytes, digest, after)
        }
        return true
    }
}

private fun modelFingerprint(file: File): String? {
    // StructStat nanosecond ctime was added in API 27. API 26 deliberately rehashes rather than
    // accepting same-size writes hidden by second-resolution metadata or a restored mtime.
    if (Build.VERSION.SDK_INT < 27) return null
    return try {
        val stat = Os.lstat(file.absolutePath)
        if (!OsConstants.S_ISREG(stat.st_mode)) null else
            "${stat.st_dev}:${stat.st_ino}:${stat.st_size}:${stat.st_mode}:" +
                "${stat.st_mtim.tv_sec}:${stat.st_mtim.tv_nsec}:${stat.st_ctim.tv_sec}:${stat.st_ctim.tv_nsec}"
    } catch (_: android.system.ErrnoException) { null }
}

private fun modelHash(file: File, checkCancelled: () -> Unit): String {
    val digest = MessageDigest.getInstance("SHA-256")
    file.inputStream().use { input ->
        val buffer = ByteArray(65536)
        while (true) {
            checkCancelled()
            val count = input.read(buffer)
            if (count < 0) break
            digest.update(buffer, 0, count)
        }
    }
    return digest.digest().joinToString("") { "%02x".format(it) }
}

internal class ModelRuntime(val ocr: LocalOcr, val embedding: LocalEmbedding) : Closeable {
    override fun close() { try { embedding.close() } finally { ocr.close() } }
}
