package com.mightyoung.muyon.product.ml

import android.content.Context
import org.json.JSONArray
import java.io.Closeable
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest

/** Frozen application models only. No arbitrary model import or network fallback. */
internal class LocalModels(private val context: Context) {
    companion object {
        const val IDENTITY = "eg2-q8:6f1bd4ac6c5df7444f9cca7ca36cafe6cfa34cd6f49fefb1e0b4be8143aed8bc:llama-b11763:768:det-a431985659dc921974177a95adcfbb90fd9e51989a5e04d70d0b75f597b6e61d:rec-da72dc72ca4dc220df0dfde68c1dedc31c58d3e76a25871122e5056227d50092:dict-d858428fbe0ada92b439a5f277b51bc1b318fd985d80946a3ce859d7f2446a92:bgr-v1:chunk192-v1"
        private val lock = Any()
        private val expected = linkedMapOf(
            "embedding.gguf" to (309855520L to "6f1bd4ac6c5df7444f9cca7ca36cafe6cfa34cd6f49fefb1e0b4be8143aed8bc"),
            "det.onnx" to (4826518L to "a431985659dc921974177a95adcfbb90fd9e51989a5e04d70d0b75f597b6e61d"),
            "rec.onnx" to (16534782L to "da72dc72ca4dc220df0dfde68c1dedc31c58d3e76a25871122e5056227d50092"),
            "dictionary.json" to (110788L to "d858428fbe0ada92b439a5f277b51bc1b318fd985d80946a3ce859d7f2446a92")
        )
    }
    private val directory = File(context.noBackupFilesDir, "local-models-v1")
    private fun hash(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(65536)
            while (true) { val count = input.read(buffer); if (count < 0) break; digest.update(buffer, 0, count) }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
    fun install(checkCancelled: () -> Unit = {}): Map<String, File> = synchronized(lock) {
        check(directory.isDirectory || directory.mkdirs()) { "本地模型目录不可用" }
        expected.mapValues { (name, identity) ->
            checkCancelled()
            val (bytes, digest) = identity
            val target = File(directory, name)
            if (!target.isFile || target.length() != bytes || hash(target) != digest) {
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
                    check(hash(part) == digest) { "本地模型校验失败" }
                    checkCancelled()
                    check(part.renameTo(target)) { "本地模型安装失败" }
                } finally { part.delete() }
            }
            target
        }
    }
    fun open(checkCancelled: () -> Unit = {}): ModelRuntime {
        val files = install(checkCancelled)
        val dictionary = JSONArray(files.getValue("dictionary.json").readText()).let { array ->
            (0 until array.length()).map(array::getString)
        }
        val ocr = LocalOcr(files.getValue("det.onnx"), files.getValue("rec.onnx"), dictionary)
        try {
            checkCancelled()
            return ModelRuntime(ocr, LocalEmbedding(files.getValue("embedding.gguf")))
        } catch (error: Throwable) { ocr.close(); throw error }
    }
}

internal class ModelRuntime(val ocr: LocalOcr, val embedding: LocalEmbedding) : Closeable {
    override fun close() { try { embedding.close() } finally { ocr.close() } }
}
