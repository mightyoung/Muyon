package com.mightyoung.muyon.product.ml

import java.io.Closeable
import java.io.File

/** CPU-only, offline embedding. Call from a background thread; each instance serializes access. */
internal class LocalEmbedding(model: File) : Closeable {
    val dimension: Int = 768
    private var handle: Long

    init {
        require(model.isFile && model.length() > 0) { "本地 embedding 模型不可用" }
        handle = nativeOpen(model.absolutePath.toByteArray(Charsets.UTF_8))
        check(handle != 0L) { "本地 embedding 模型加载失败" }
    }

    @Synchronized
    fun embed(text: String, query: Boolean = false): FloatArray {
        check(handle != 0L) { "本地 embedding 已关闭" }
        require(text.isNotBlank() && text.length <= 8192 && '\u0000' !in text) { "待嵌入文本为空或过长" }
        // Public retrieval task format. Native tokenization adds model BOS/EOS and rejects overflow.
        val formatted = if (query) "task: search result | query: $text" else "title: none | text: $text"
        val result = nativeEmbed(handle, formatted.toByteArray(Charsets.UTF_8))
        check(result.size == dimension && result.all { it.isFinite() }) { "本地 embedding 输出无效" }
        return result
    }

    @Synchronized
    override fun close() {
        if (handle != 0L) {
            nativeClose(handle)
            handle = 0L
        }
    }

    private external fun nativeOpen(path: ByteArray): Long
    private external fun nativeEmbed(handle: Long, input: ByteArray): FloatArray
    private external fun nativeClose(handle: Long)

    companion object {
        init { System.loadLibrary("muyon_local_embedding") }
    }
}
