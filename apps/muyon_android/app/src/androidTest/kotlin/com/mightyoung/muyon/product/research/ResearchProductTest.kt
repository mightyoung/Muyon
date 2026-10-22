package com.mightyoung.muyon.product.research

import android.graphics.Paint
import android.graphics.pdf.PdfDocument
import android.net.Uri
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.product.agentipc.ProductClient
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Real Service/native integration. Test files are inputs, not alternate providers or clients. */
class ResearchProductTest {
    @get:Rule val compose = createComposeRule()
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private lateinit var client: ProductClient
    private val temporary = mutableListOf<File>()
    private val hosts = mutableListOf<ResearchFileHost>()
    private fun host() = ResearchFileHost(context, client).also { hosts += it }

    @Before fun connect() {
        val connected = CountDownLatch(1)
        instrumentation.runOnMainSync {
            client = ProductClient(context) { if (it) connected.countDown() }
            client.bind()
        }
        assertTrue(connected.await(15, TimeUnit.SECONDS))
        val database = File(context.filesDir, "muyon-product-v2/business-v2.sqlite")
        val health = call("health")
        val readiness = if (health.optString("status") != "ok" && !database.isFile) call("initialize") else health
        assertEquals("real product readiness: $readiness", "ok", readiness.getString("status"))
        assertNull("resolve existing original intent before test", context.getSharedPreferences("muyon_product_research_v2", 0).getString("intent_id", null))
        compose.setContent { MaterialTheme { ResearchScreen(client) } }
    }

    @After fun close() {
        hosts.forEach { it.close() }
        if (::client.isInitialized) instrumentation.runOnMainSync { client.close() }
        temporary.forEach { it.delete() }
    }

    private fun call(method: String, payload: JSONObject = JSONObject()): JSONObject {
        val done = CountDownLatch(1)
        var result: JSONObject? = null
        instrumentation.runOnMainSync { client.call(method, payload) { result = it; done.countDown() } }
        assertTrue("real service $method response", done.await(35, TimeUnit.SECONDS))
        return requireNotNull(result)
    }
    private fun data(method: String, payload: JSONObject = JSONObject()): JSONObject {
        val reply = call(method, payload)
        assertEquals(reply.toString(), "ok", reply.getString("status"))
        return reply.getJSONObject("data")
    }
    private fun write(operation: JSONObject, project: String?, revision: String = "0"): JSONObject {
        val request = JSONObject().put("operation", operation).put("expected_revision", revision)
        if (project != null) request.put("project_id", project)
        val plan = data("prepare", request)
        val result = data("confirm", JSONObject().put("plan_id", plan.getString("plan_id")))
        assertEquals(result.toString(), "committed", result.getString("status"))
        assertEquals(plan.getString("intent_id"), result.getJSONObject("receipt").getString("intent_id"))
        call("discard", JSONObject().put("plan_id", plan.getString("plan_id")))
        return result.getJSONObject("receipt")
    }
    private fun rows(method: String, project: String? = null): List<JSONObject> {
        val result = mutableListOf<JSONObject>()
        while (true) {
            val request = JSONObject().put("limit", 10).put("offset", result.size)
            if (project != null) request.put("project_id", project)
            val reply = call(method, request)
            assertEquals(reply.toString(), "ok", reply.getString("status"))
            val page = reply.getJSONArray("data")
            (0 until page.length()).forEach { result += page.getJSONObject(it) }
            if (page.length() < 10) return result
        }
    }
    private fun selectPaged(name: String, kind: String) {
        fun ready() { compose.waitUntil(15_000) { compose.onAllNodes(hasTestTag("research-new-project") and isEnabled()).fetchSemanticsNodes().isNotEmpty() } }
        fun click(tag: String) { compose.onNodeWithTag(tag).performScrollTo().performClick(); ready() }
        ready()
        while (compose.onAllNodes(hasTestTag("research-$kind-previous") and isEnabled()).fetchSemanticsNodes().isNotEmpty()) click("research-$kind-previous")
        while (compose.onAllNodes(hasText("$name ·", substring = true) and hasClickAction()).fetchSemanticsNodes().isEmpty()) {
            compose.onNodeWithTag("research-$kind-next").assertIsEnabled()
            click("research-$kind-next")
        }
        compose.onNode(hasText("$name ·", substring = true) and hasClickAction()).performScrollTo().performClick()
        ready()
    }
    private fun zip(files: Map<String, String>, deflated: Boolean): File {
        val file = File.createTempFile("research-input-", ".zip", context.cacheDir).also { temporary += it }
        ZipOutputStream(file.outputStream()).use { stream ->
            files.forEach { (name, content) ->
                val bytes = content.toByteArray(Charsets.UTF_8)
                val entry = ZipEntry(name)
                if (!deflated) entry.apply {
                    method = ZipEntry.STORED; size = bytes.size.toLong(); compressedSize = size
                    crc = CRC32().apply { update(bytes) }.value
                }
                stream.putNextEntry(entry); stream.write(bytes); stream.closeEntry()
            }
        }
        return file
    }

    @Test fun projectVisibleReviewThenActualPdfHostAndDetail() {
        val projectName = "Research-${UUID.randomUUID()}"
        compose.onNodeWithTag("research-new-project").performScrollTo().performClick()
        compose.onNodeWithTag("research-project-name").performScrollTo().performTextInput(projectName)
        compose.onNodeWithTag("research-project-preview").performScrollTo().performClick()
        compose.waitUntil(15_000) { compose.onAllNodesWithTag("research-preview").fetchSemanticsNodes().isNotEmpty() }
        assertFalse(rows("projects").any { it.getString("name") == projectName })
        compose.onNodeWithTag("research-confirm").performClick()
        compose.waitUntil(15_000) { compose.onAllNodesWithTag("research-receipt").fetchSemanticsNodes().isNotEmpty() }
        val project = rows("projects").single { it.getString("name") == projectName }.getString("id")
        val pdf = File.createTempFile("research-input-", ".pdf", context.cacheDir).also { temporary += it }
        val document = PdfDocument()
        try {
            val page = document.startPage(PdfDocument.PageInfo.Builder(300, 400, 1).create())
            page.canvas.drawText("Controlled research PDF", 20f, 40f, Paint())
            document.finishPage(page)
            pdf.outputStream().use { document.writeTo(it) }
        } finally { document.close() }
        val host = host()
        val upload = host.pdf(project, Uri.fromFile(pdf))
        val title = "Paper-${UUID.randomUUID()}"
        val paperId = UUID.randomUUID().toString()
        write(JSONObject().put("operation", "paper_create").put("paper_id", paperId).put("payload", JSONObject()
            .put("title", title).put("authors", JSONArray().put("Researcher A")).put("year", 2026)
            .put("doi", "10.1234/test").put("url", "https://example.org/paper").put("notes", "Preserved metadata")
            .put("attachment", upload.getJSONObject("blob")).put("attachment_upload_id", upload.getString("upload_id"))), project)
        val detail = data("paper", JSONObject().put("project_id", project).put("paper_id", paperId))
        assertEquals("Preserved metadata", JSONObject(detail.getString("raw_json")).getString("notes"))
        host.attachment(project, paperId, detail.getJSONArray("attachments").getJSONObject(0)).use { rendered ->
            assertEquals(1, rendered.pages)
            val bitmap = rendered.render(0)
            assertTrue(bitmap.width > 0 && bitmap.height > 0)
            bitmap.recycle()
        }
        compose.onNodeWithText("刷新科研当前值").performScrollTo().performClick()
        selectPaged(title, "paper")
        compose.waitUntil(15_000) { compose.onAllNodesWithTag("research-paper-detail").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("research-paper-detail").assertTextContains(title, substring = true)
    }

    @Test fun deflatedZipUsesFrozenArchiveAndSealsActualImport() {
        val prefix = UUID.randomUUID().toString()
        val projectIds = List(11) { UUID.randomUUID().toString() }
        projectIds.forEachIndexed { index, id ->
            write(JSONObject().put("operation", "project_create").put("project_id", id).put("name", "ZIP project $prefix-$index"), null)
        }
        val project = projectIds.max()
        val title = "Imported-${UUID.randomUUID()}"
        val files = linkedMapOf(
            "research/papers.jsonl" to (0..10).joinToString("\n", postfix = "\n") { index ->
                JSONObject().put("schema_version", 2).put("id", "p$index").put("rev", 1).put("title", "$title-$index").toString()
            },
            "research/sources.jsonl" to "\n", "research/claims.jsonl" to "\n", "research/opportunities.jsonl" to "\n")
        val zip = zip(files, deflated = true)
        val host = host()
        val sealed = host.archive(project, Uri.fromFile(zip))
        assertEquals(11, sealed.getInt("record_count"))
        val source = UUID.randomUUID().toString()
        write(JSONObject().put("operation", "research_import").put("source_id", source).put("source_revision", "1")
            .put("snapshot", sealed.getJSONObject("snapshot")).put("snapshot_upload_id", sealed.getString("snapshot_upload_id"))
            .put("records", JSONArray()), project)
        val imported = rows("papers", project)
        assertEquals(11, imported.size)
        assertEquals((0..10).map { "$title-$it" }.toSet(), imported.map { it.getString("title") }.toSet())
        assertTrue(imported.all { it.getString("source_id") == source })
        compose.onNodeWithText("刷新科研当前值").performScrollTo().performClick()
        selectPaged("ZIP project $prefix-${projectIds.indexOf(project)}", "project")
        val projectPage = compose.onNodeWithTag("research-project-page").fetchSemanticsNode().config[SemanticsProperties.Text].joinToString { it.text }
        assertFalse("eleven projects must cross page zero: $projectPage", projectPage.startsWith("项目偏移：0 ·"))
        val last = imported.last().getString("title")
        selectPaged(last, "paper")
        compose.onNodeWithTag("research-paper-page").assertTextEquals("论文偏移：10 · 本页 1 项")
        compose.onNodeWithTag("research-paper-detail").assertTextContains(last, substring = true)
    }

    @Test fun corruptStoredMemberCannotPublishSnapshotOrPaper() {
        val project = UUID.randomUUID().toString()
        write(JSONObject().put("operation", "project_create").put("project_id", project).put("name", "CRC project $project"), null)
        val zip = zip(mapOf("research/papers.jsonl" to "{\"id\":\"crc-paper\",\"title\":\"Original\"}\n"), deflated = false)
        val bytes = zip.readBytes()
        fun short(offset: Int) = (bytes[offset].toInt() and 255) or ((bytes[offset + 1].toInt() and 255) shl 8)
        val start = 30 + short(26) + short(28)
        // Keep local and central CRC metadata intact while changing actual payload.
        bytes[start] = (bytes[start].toInt() xor 1).toByte()
        zip.writeBytes(bytes)
        val host = host()
        val failure = runCatching { host.archive(project, Uri.fromFile(zip)) }.exceptionOrNull()
        assertNotNull("bad CRC must fail before a usable snapshot exists", failure)
        assertTrue("A storage/service failure is not CRC rejection: $failure",
            (failure is java.util.zip.ZipException && failure.message.orEmpty().contains("CRC", ignoreCase = true)) ||
                failure?.message.orEmpty().contains("InvalidPayload"))
        assertEquals(0, call("papers", JSONObject().put("project_id", project)).getJSONArray("data").length())
        host.discard()
    }
}
