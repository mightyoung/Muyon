package com.mightyoung.muyon.product.research

import android.content.Context
import com.mightyoung.muyon.product.ml.*
import org.json.JSONObject
import java.util.concurrent.CancellationException
import java.util.concurrent.atomic.AtomicBoolean
import java.io.Closeable

/** Local, derived data only; never grants outbound disclosure or changes business rows. */
internal class LocalResearch(private val context: Context, private val host: ResearchFileHost) : Closeable {
    private val embedding = ModelResourceCache<LocalEmbedding>()
    private var closed = false

    private fun <T> withEmbedding(project: String, checkCancelled: () -> Unit, action: (LocalEmbedding) -> T): T {
        kotlin.check(!closed) { "本地检索已关闭" }
        val models = LocalModels(context)
        val file = models.installEmbedding(checkCancelled)
        val identity = "$project:${models.embeddingIdentity(file)}"
        return embedding.use(identity, { LocalEmbedding(file) }) { engine -> checkCancelled(); action(engine) }
    }

    @Synchronized
    override fun close() { if (!closed) { closed = true; embedding.close() } }
    private fun current(source: IndexSource): Boolean {
        val paper = try { host.currentPaper(source.project, source.paper) }
        catch (error: ResearchReadFailure) { if (error.code == "NotFound") return false else throw error }
        val attachments = paper.optJSONArray("attachments") ?: return false
        return paper.optString("revision") == source.revision &&
            (0 until attachments.length()).any { attachments.getJSONObject(it).optString("digest") == source.digest }
    }

    @Synchronized
    fun index(project: String, paper: String, digest: String, cancelled: AtomicBoolean): Int {
        fun check() { if (cancelled.get()) throw CancellationException("本地索引已取消") }
        check()
        kotlin.check(!closed) { "本地检索已关闭" }
        val detail = host.currentPaper(project, paper)
        val source = IndexSource(project, paper, detail.getString("revision"), digest, LocalModels.IDENTITY)
        require(current(source)) { "附件已变化，请刷新论文" }
        val attachments = detail.getJSONArray("attachments")
        val blob = (0 until attachments.length()).map(attachments::getJSONObject).first { it.getString("digest") == digest }
        val chunks = mutableListOf<IndexedPage>()
        host.attachment(project, paper, blob).use { pdf ->
            require(pdf.pages in 1..200) { "本地索引支持1至200页PDF" }
            withEmbedding(project, ::check) { engine ->
                LocalModels(context).openOcr(::check).use { ocr ->
                    for (page in 0 until pdf.pages) {
                        check()
                        val bitmap = pdf.render(page)
                        val text = try { ocr.recognize(bitmap, ::check).joinToString("\n") { it.text } }
                        finally { bitmap.recycle() }
                        val points = text.codePoints().toArray()
                        for (offset in points.indices step 192) {
                            check()
                            val content = String(points, offset, minOf(192, points.size - offset)).trim()
                            if (content.isNotEmpty()) {
                                require(chunks.size < 3200) { "论文文字超过本地索引上限" }
                                chunks += IndexedPage(page, content, engine.embed(content))
                            }
                        }
                    }
                }
            }
        }
        check()
        require(chunks.isNotEmpty()) { "未识别到文字，未建立索引" }
        require(current(source)) { "论文已变化，未发布过期索引" }
        check()
        ResearchIndex(context).use { it.publish(source, chunks, ::check) }
        return chunks.size
    }

    @Synchronized
    fun search(project: String, query: String, cancelled: AtomicBoolean): List<SearchHit> {
        fun check() { if (cancelled.get()) throw CancellationException("本地检索已取消") }
        require(query.isNotBlank() && query.codePointCount(0, query.length) <= 192) { "搜索内容需为1至192字" }
        check()
        val vector = withEmbedding(project, ::check) { it.embed(query, query = true) }
        check()
        val verified = mutableMapOf<IndexSource, Boolean>()
        return ResearchIndex(context).use { index ->
            index.search(project, vector, LocalModels.IDENTITY, isCurrent = { source ->
                check()
                verified.getOrPut(source) { current(source) }
            })
        }.also { check() }
    }
}
