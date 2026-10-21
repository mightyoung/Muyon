package com.mightyoung.muyon.product.research

import android.net.Uri
import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.product.agentipc.ProductClient
import com.mightyoung.muyon.product.ml.IndexSource
import com.mightyoung.muyon.product.ml.IndexedPage
import com.mightyoung.muyon.product.ml.LocalEmbedding
import com.mightyoung.muyon.product.ml.LocalModels
import com.mightyoung.muyon.product.ml.ResearchIndex
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.io.File
import java.util.UUID
import java.util.concurrent.CancellationException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** No synthetic OCR, embeddings, RPC implementation, or source authority in this business loop. */
class LocalResearchIntegrationTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private lateinit var client: ProductClient
    private lateinit var host: ResearchFileHost
    private val temporary = mutableListOf<File>()

    @Before fun connect() {
        val connected = CountDownLatch(1)
        instrumentation.runOnMainSync {
            client = ProductClient(context) { if (it) connected.countDown() }
            client.bind()
        }
        assertTrue("Real product service must connect", connected.await(15, TimeUnit.SECONDS))
        val database = File(context.filesDir, "muyon-product-v2/business-v2.sqlite")
        val health = call("health")
        val readiness = if (health.optString("status") != "ok" && !database.isFile) call("initialize") else health
        assertEquals("Real business store readiness: $readiness", "ok", readiness.getString("status"))
        assertNull("Do not interfere with an original outstanding intent", context.getSharedPreferences(
            "muyon_product_research_v2", 0).getString("intent_id", null))
        host = ResearchFileHost(context, client)
    }

    @After fun close() {
        if (::host.isInitialized) host.close()
        if (::client.isInitialized) instrumentation.runOnMainSync { client.close() }
        temporary.forEach { it.delete() }
    }

    private fun call(method: String, payload: JSONObject = JSONObject()): JSONObject {
        val done = CountDownLatch(1)
        var result: JSONObject? = null
        instrumentation.runOnMainSync { client.call(method, payload) { result = it; done.countDown() } }
        assertTrue("Real service $method response", done.await(35, TimeUnit.SECONDS))
        return requireNotNull(result)
    }

    private fun data(method: String, payload: JSONObject = JSONObject()): JSONObject {
        val reply = call(method, payload)
        assertEquals(reply.toString(), "ok", reply.getString("status"))
        return reply.getJSONObject("data")
    }

    private fun write(operation: JSONObject, project: String?) {
        val request = JSONObject().put("operation", operation).put("expected_revision", "0")
        if (project != null) request.put("project_id", project)
        val plan = data("prepare", request)
        val result = data("confirm", JSONObject().put("plan_id", plan.getString("plan_id")))
        assertEquals(result.toString(), "committed", result.getString("status"))
        assertEquals(plan.getString("intent_id"), result.getJSONObject("receipt").getString("intent_id"))
        assertEquals("ok", call("discard", JSONObject().put("plan_id", plan.getString("plan_id"))).getString("status"))
    }

    private fun project(): String = UUID.randomUUID().toString().also { id ->
        write(JSONObject().put("operation", "project_create").put("project_id", id)
            .put("name", "Local model integration $id"), null)
    }

    private fun committedPaper(project: String): IndexSource {
        val file = File.createTempFile("local-research-", ".pdf", context.cacheDir).also { temporary += it }
        instrumentation.context.assets.open("ml/ocr.pdf").use { input ->
            file.outputStream().use { output -> input.copyTo(output) }
        }
        val upload = host.pdf(project, Uri.fromFile(file))
        val paper = UUID.randomUUID().toString()
        write(JSONObject().put("operation", "paper_create").put("paper_id", paper)
            .put("payload", JSONObject().put("title", "材料金额扫描论文 $paper")
                .put("authors", JSONArray().put("Local integration fixture"))
                .put("attachment", upload.getJSONObject("blob"))
                .put("attachment_upload_id", upload.getString("upload_id"))), project)
        val detail = data("paper", JSONObject().put("project_id", project).put("paper_id", paper))
        val digest = detail.getJSONArray("attachments").getJSONObject(0).getString("digest")
        assertEquals("Committed bytes must match the actual uploaded PDF", upload.getJSONObject("blob").getString("digest"), digest)
        // The subsequent index operation can only use the committed private attachment, not this URI.
        assertTrue(file.delete())
        return IndexSource(project, paper, detail.getString("revision"), digest, LocalModels.IDENTITY)
    }

    @Test fun committedPrivatePdfRecognizedEmbeddedReopenedAndSemanticallyRetrieved() {
        val project = project()
        val isolatedProject = project()
        val source = committedPaper(project)
        val cancelledSource = committedPaper(project)
        val local = LocalResearch(context, host)
        assertFalse(ResearchIndex(context).use { it.contains(source) })
        val chunks = local.index(project, source.paper, source.digest, AtomicBoolean(false))
        assertTrue("Real OCR must yield at least one indexed chunk", chunks > 0)

        // A distinct helper/connection proves publication survives closing and reopening the index.
        ResearchIndex(context).use { assertTrue(it.contains(source)) }
        val hits = LocalResearch(context, host).search(project, "材料的金额是多少", AtomicBoolean(false))
        assertTrue("Real local semantic search produced no hits", hits.isNotEmpty())
        assertTrue("Every result must retain committed provenance", hits.all { it.source == source && it.page == 0 && it.score.isFinite() })
        val recognized = hits.joinToString("\n") { it.text }
        assertTrue("Private PDF OCR lost Chinese material text: $recognized", recognized.contains("材料"))
        assertTrue("Private PDF OCR lost first amount: $recognized", recognized.contains("123.45"))
        assertTrue("Private PDF OCR lost second amount: $recognized", recognized.contains("678.90"))

        // Simulate derived data left behind after its authoritative paper disappeared. Use a
        // genuine model query vector so the stale candidate would otherwise rank very highly.
        val removed = source.copy(paper = UUID.randomUUID().toString(), digest = "f".repeat(64))
        val missing = assertThrows(ResearchReadFailure::class.java) {
            host.currentPaper(project, removed.paper)
        }
        assertEquals("The real business RPC must specifically report a missing paper", "NotFound", missing.code)
        assertNotEquals("ok", missing.status)
        val installed = LocalModels(context).install()
        val queryVector = LocalEmbedding(installed.getValue("embedding.gguf")).use {
            it.embed("材料的金额是多少", query = true)
        }
        ResearchIndex(context).use { index ->
            index.publish(removed, listOf(IndexedPage(0, "已移除论文的材料金额片段", queryVector)))
            assertTrue("The removed-paper candidate must actually be persisted", index.contains(removed))
        }
        val afterRemoval = local.search(project, "材料的金额是多少", AtomicBoolean(false))
        assertTrue("A missing paper must not abort retrieval of a valid paper", afterRemoval.isNotEmpty())
        assertTrue("Stale removed-paper results must be excluded by the real authority check",
            afterRemoval.all { it.source == source && it.source != removed })
        assertTrue("The valid scanned amount must remain retrievable after stale data is encountered",
            afterRemoval.any { it.text.contains("123.45") })
        assertTrue("Project boundaries must exclude another project's indexed paper",
            local.search(isolatedProject, "材料的金额是多少", AtomicBoolean(false)).isEmpty())

        assertThrows(CancellationException::class.java) {
            local.index(project, cancelledSource.paper, cancelledSource.digest, AtomicBoolean(true))
        }
        ResearchIndex(context).use {
            assertFalse("Cancelled work must not publish a source", it.contains(cancelledSource))
            assertTrue("Cancellation must preserve the already published paper", it.contains(source))
        }
        assertThrows(CancellationException::class.java) {
            local.search(project, "材料", AtomicBoolean(true))
        }
        assertThrows(IllegalArgumentException::class.java) {
            local.index(project, source.paper, "0".repeat(64), AtomicBoolean(false))
        }
        ResearchIndex(context).use { assertTrue("Rejected digest must preserve the valid index", it.contains(source)) }
    }

    @Test fun cancellationDuringPublicationRollsBackAfterAnActualChunkWrite() {
        val name = "research-derived-integration-${UUID.randomUUID()}.sqlite"
        val source = IndexSource("isolated-project", "isolated-paper", "1", "a".repeat(64), LocalModels.IDENTITY)
        val vector = FloatArray(768).apply { this[0] = 1f }
        try {
            ResearchIndex(context, name).use { index ->
                index.publish(source, listOf(IndexedPage(0, "original published chunk", vector)))
                var cancellationChecks = 0
                assertThrows(CancellationException::class.java) {
                    index.publish(source.copy(revision = "2"), listOf(
                        IndexedPage(0, "first replacement chunk", vector),
                        IndexedPage(1, "second replacement chunk", vector),
                    )) {
                        cancellationChecks++
                        // 2 validation callbacks, 1 before deletion, 1 before the first write.
                        // Cancel before the second chunk insert, after source and first chunk changed.
                        if (cancellationChecks == 5) throw CancellationException("Cancel after first real chunk insert")
                    }
                }
                assertEquals(5, cancellationChecks)
                assertTrue(index.contains(source))
                assertFalse(index.contains(source.copy(revision = "2")))
            }
            ResearchIndex(context, name).use { index ->
                assertEquals(listOf("original published chunk"), index.search(source.project, vector,
                    LocalModels.IDENTITY, isCurrent = { it == source }).map { it.text })
            }
        } finally { context.deleteDatabase(name) }
    }
}
