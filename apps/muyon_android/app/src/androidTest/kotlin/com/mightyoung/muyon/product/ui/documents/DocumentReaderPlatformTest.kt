package com.mightyoung.muyon.product.ui.documents

import android.net.Uri
import android.graphics.Color
import android.graphics.Paint
import android.graphics.pdf.PdfDocument
import android.os.ParcelFileDescriptor
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.Rule
import kotlinx.coroutines.CompletableDeferred
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicBoolean
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DocumentReaderPlatformTest {
    @get:Rule val compose = createComposeRule()

    @Test fun pendingSaveAndUnknownLockSurvivePageNavigationAndOtherScopesAreHidden() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val file = File.createTempFile("synthetic-reader-ui-", ".pdf", context.cacheDir)
        val result = CompletableDeferred<SidecarSaveResult>()
        val calls = AtomicInteger()
        try {
            PdfDocument().use { doc ->
                repeat(2) { index ->
                    val page = doc.startPage(PdfDocument.PageInfo.Builder(100, 100, index + 1).create())
                    page.canvas.drawColor(Color.WHITE); doc.finishPage(page)
                }
                file.outputStream().use { doc.writeTo(it) }
            }
            val ref = ReaderDocumentRef("w", "p", "d", "1", DocumentFormat.PDF)
            val note = SidecarAnnotation("n", "1", ref, "{opaque-core-anchor}", "第 1 页", "人工 h",
                AnnotationContent.Comment("before"), false, false)
            val foreign = note.copy(id = "foreign", document = ref.copy(projectId = "other"),
                content = AnnotationContent.Comment("OTHER_SCOPE_SECRET"))
            val host = DocumentReaderHost(
                openCurrent = { _, _, _ -> ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY) },
                isCurrent = { _, _ -> true },
                saveSidecar = { _, _ -> calls.incrementAndGet(); result.await() },
            )
            compose.setContent { MaterialTheme {
                DocumentReaderScreen(DocumentReaderSnapshot(ref, Uri.parse("content://synthetic/fixture"),
                    1L, true, listOf(note, foreign)), host, {})
            } }
            fun awaitPage(number: Int) {
                compose.waitUntil(10000) {
                    compose.onAllNodesWithContentDescription("文档 d 第 $number 页原文件渲染")
                        .fetchSemanticsNodes().isNotEmpty()
                }
            }
            awaitPage(1)
            compose.onNodeWithText("OTHER_SCOPE_SECRET").assertDoesNotExist()
            compose.onNodeWithText("批注正文").performScrollTo().performTextReplacement("edited")
            compose.onNodeWithText("保存 sidecar 批注").performScrollTo().performClick()
            compose.waitUntil { calls.get() == 1 }
            compose.onNodeWithText("下一页").performClick()
            awaitPage(2)
            // In-flight save survives annotation subtree removal; still no second submit.
            compose.onNodeWithText("保存中…").performScrollTo().assertIsNotEnabled()
            result.complete(SidecarSaveResult.Unknown)
            compose.onNodeWithText("保存 sidecar 批注").performScrollTo().assertIsNotEnabled()
            compose.onNodeWithText("上一页").performClick()
            awaitPage(1)
            compose.onNodeWithText("保存 sidecar 批注").performScrollTo().assertIsNotEnabled()
            compose.onNodeWithText("edited").assertExists()
            assertEquals(1, calls.get())
        } finally { result.cancel(); file.delete() }
    }

    @Test fun pageReadFailureCanNavigateAndExplicitlyRetryWithoutResendingUnknownSave() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val file = File.createTempFile("synthetic-reader-retry-", ".pdf", context.cacheDir)
        val failOpen = AtomicBoolean(false)
        val current = AtomicBoolean(true)
        val saves = AtomicInteger()
        try {
            PdfDocument().use { doc ->
                repeat(3) { index ->
                    val page = doc.startPage(PdfDocument.PageInfo.Builder(100, 100, index + 1).create())
                    page.canvas.drawColor(Color.WHITE); doc.finishPage(page)
                }
                file.outputStream().use { doc.writeTo(it) }
            }
            val ref = ReaderDocumentRef("w", "p", "retry-doc", "1", DocumentFormat.PDF)
            val note = SidecarAnnotation("n", "1", ref, "{opaque-core-anchor}", "第 1 页", "人工 h",
                AnnotationContent.Comment("before"), false, false)
            val host = DocumentReaderHost(
                openCurrent = { _, _, _ ->
                    if (failOpen.get()) error("Synthetic transient FD failure")
                    ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                },
                isCurrent = { _, _ -> current.get() },
                saveSidecar = { _, _ -> saves.incrementAndGet(); SidecarSaveResult.Unknown },
            )
            compose.setContent { MaterialTheme {
                DocumentReaderScreen(DocumentReaderSnapshot(ref, Uri.parse("content://synthetic/retry"),
                    1L, true, listOf(note)), host, {})
            } }
            fun awaitPage(number: Int) = compose.waitUntil(10000) {
                compose.onAllNodesWithContentDescription("文档 retry-doc 第 $number 页原文件渲染")
                    .fetchSemanticsNodes().isNotEmpty()
            }
            fun awaitFailure() = compose.waitUntil(10000) {
                compose.onAllNodesWithText("重试读取当前页").fetchSemanticsNodes().isNotEmpty()
            }
            awaitPage(1)
            compose.onNodeWithText("批注正文").performScrollTo().performTextReplacement("retained draft")
            compose.onNodeWithText("保存 sidecar 批注").performScrollTo().performClick()
            compose.waitUntil { saves.get() == 1 }
            failOpen.set(true)
            compose.onNodeWithText("下一页").performClick()
            awaitFailure()
            compose.onNodeWithText("上一页").assertIsEnabled()
            compose.onNodeWithText("下一页").assertIsEnabled()
            compose.onNodeWithText("定位").assertIsEnabled()
            // Recovery reads no longer require closing this reader or discarding its editor state.
            failOpen.set(false)
            compose.onNodeWithText("重试读取当前页").performScrollTo().performClick()
            awaitPage(2)
            compose.onNodeWithText("保存 sidecar 批注").performScrollTo().assertIsNotEnabled()
            compose.onNodeWithText("retained draft").assertExists()
            assertEquals(1, saves.get())
            failOpen.set(true)
            compose.onNodeWithText("下一页").performClick()
            awaitFailure()
            failOpen.set(false)
            compose.onNodeWithText("上一页").performClick()
            awaitPage(2)
            assertEquals(1, saves.get())
            // Distinct failure class: invalid current document cannot retry or navigate.
            current.set(false)
            compose.onNodeWithText("下一页").performClick()
            compose.waitUntil(10000) {
                compose.onAllNodesWithText("访问或修订已失效；请返回重新打开。")
                    .fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText("上一页").assertIsNotEnabled()
            compose.onNodeWithText("下一页").assertIsNotEnabled()
            compose.onNodeWithText("定位").assertIsNotEnabled()
            compose.onNodeWithText("重试读取当前页").assertDoesNotExist()
            assertEquals(1, saves.get())
        } finally { file.delete() }
    }

    @Test fun nativePdfRendersActualPagesAndRejectsBadPage() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val file = File.createTempFile("synthetic-reader-", ".pdf", context.cacheDir)
        try {
            PdfDocument().use { doc ->
                listOf(Color.RED, Color.BLUE).forEachIndexed { index, color ->
                    val page = doc.startPage(PdfDocument.PageInfo.Builder(100, 200, index + 1).create())
                    page.canvas.drawRect(0f, 0f, 100f, 200f, Paint().apply { this.color = color })
                    doc.finishPage(page)
                }
                file.outputStream().use { doc.writeTo(it) }
            }
            fun descriptor() = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            val first = NativeDocumentPreview.pdf(descriptor(), 0)
            assertEquals(2, first.pageCount)
            assertEquals(Color.RED, first.bitmap.getPixel(first.bitmap.width / 2, first.bitmap.height / 2))
            first.bitmap.recycle()
            val second = NativeDocumentPreview.pdf(descriptor(), 1)
            assertEquals(Color.BLUE, second.bitmap.getPixel(second.bitmap.width / 2, second.bitmap.height / 2))
            second.bitmap.recycle()
            assertTrue(runCatching { NativeDocumentPreview.pdf(descriptor(), 2) }.isFailure)
        } finally { file.delete() }
    }

    @Test fun sharedCoreJsonPreservesAnchorAndExactRevision() {
        val ref = JSONObject("""{"scope":{"workspace_id":"w","project_id":null},"document_id":"d","revision":"18446744073709551615","format":"pdf"}""")
        assertTrue(runCatching { SharedDocumentJson.document(JSONObject(ref.toString()).put("revision", 123)) }.isFailure)
        val anchor = JSONObject().put("document", ref).put("location", JSONObject().put("pdf",
            JSONObject().put("page_index_zero_based", 0).put("coordinates", "unknown")
                .put("rotation", JSONObject.NULL).put("crop", JSONObject.NULL)
                .put("region", JSONObject("""{"x":0,"y":0,"width":1,"height":1}"""))))
        val record = JSONObject().put("id", "n").put("revision", "9").put("anchor", anchor)
            .put("body", JSONObject("""{"kind":"comment","text":"actual note"}"""))
            .put("created_by", JSONObject("""{"kind":"ai","agent_id":"a","run_id":"r"}"""))
            .put("modified_by", JSONObject("""{"kind":"human","actor_id":"h"}"""))
            .put("deleted", false).put("anchor_state", "current")
        val projected = SharedDocumentJson.annotation(record)
        assertEquals("18446744073709551615", projected.document.revision)
        assertEquals(anchor.toString(), projected.anchorJson)
        assertTrue(projected.authorLabel.contains("AI"))
        assertTrue(projected.authorLabel.contains("h"))
        assertEquals("9", projected.edit(projected.document, "edited")!!.expectedAnnotationRevision)
        assertEquals("comment", SharedDocumentJson.replacementBody(projected.edit(projected.document, "edited")!!).getString("kind"))
    }
}
