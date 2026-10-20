package com.mightyoung.muyon.product

import android.graphics.Paint
import android.graphics.Rect
import android.graphics.pdf.PdfDocument
import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.Role
import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.product.agentipc.ProductClient
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Real MainActivity -> Android DocumentsUI -> app-private import. No substituted results. */
class SystemPickerProductTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val automation get() = instrumentation.uiAutomation
    private val preferences get() = context.getSharedPreferences("system_picker_acceptance", 0)

    /** Parent runs this first, then copies only this generated directory into Downloads. */
    @Test fun generatePickerInputs() {
        val directory = requireNotNull(context.getExternalFilesDir("picker-fixtures"))
        assertTrue(directory.isDirectory || directory.mkdirs())
        val pdf = PdfDocument()
        try {
            val page = pdf.startPage(PdfDocument.PageInfo.Builder(300, 400, 1).create())
            page.canvas.drawText("Muyon system picker fixture", 20f, 40f, Paint())
            pdf.finishPage(page)
            File(directory, "picker-paper.pdf").outputStream().use(pdf::writeTo)
        } finally { pdf.close() }
        val files = linkedMapOf(
            "research/papers.jsonl" to "{\"schema_version\":2,\"id\":\"picker-import-paper\",\"rev\":1,\"title\":\"System picker imported paper\"}\n",
            "research/sources.jsonl" to "\n", "research/claims.jsonl" to "\n", "research/opportunities.jsonl" to "\n")
        files.forEach { (name, text) ->
            File(directory, "picker-workspace/$name").apply { parentFile!!.mkdirs(); writeText(text) }
        }
        ZipOutputStream(File(directory, "picker-workspace.zip").outputStream()).use { zip ->
            files.forEach { (name, text) -> zip.putNextEntry(ZipEntry(name)); zip.write(text.toByteArray()); zip.closeEntry() }
        }
        assertTrue(File(directory, "picker-paper.pdf").length() > 0)
        assertTrue(File(directory, "picker-workspace.zip").length() > 0)
        println("PICKER_FIXTURES_READY=${directory.absolutePath}")
    }

    @Test fun pdfSystemPickerManualReviewAndPrivateAttachment() {
        openResearch()
        val project = createProject("Picker PDF")
        // A real picked PDF may be reviewed and discarded without publishing.
        val cancelledTitle = "Discarded picker PDF ${UUID.randomUUID()}"
        clickTag("research-add-pdf")
        chooseDocument("picker-paper.pdf")
        waitTag("research-field-title")
        compose.onNodeWithTag("research-field-title").performScrollTo().performTextInput(cancelledTitle)
        clickTag("research-paper-preview")
        waitTag("research-preview")
        assertNoPublishedPaper(cancelledTitle)
        compose.onNodeWithText("返回科研草稿").performClick()
        compose.onNodeWithText("放弃科研草稿").performScrollTo().performClick()
        compose.onAllNodesWithText("放弃科研草稿").onLast().performClick()
        waitTag("research-add-pdf")
        assertNoPublishedPaper(cancelledTitle)
        clickTag("research-add-pdf")
        chooseDocument("picker-paper.pdf")
        waitTag("research-field-title")
        val title = "Picker manual paper ${UUID.randomUUID()}"
        mapOf("title" to title, "authors" to "Picker Researcher", "year" to "2026",
            "doi" to "10.1234/picker-fixture", "url" to "https://example.org/picker-fixture", "notes" to "System document picker metadata").forEach { (field, value) ->
            compose.onNodeWithTag("research-field-$field").performScrollTo().performTextInput(value)
        }
        clickTag("research-paper-preview")
        waitTag("research-preview")
        compose.onNodeWithTag("research-preview").assertTextContains(title, substring = true)
        // Visible review is still a proposal: there must be no published paper button yet.
        compose.onAllNodes(paperButton(title)).assertCountEquals(0)
        assertNoPublishedPaper(title)
        clickTag("research-confirm")
        waitPaper(title)
        assertTrue(preferences.edit().putString("paper_title", title).putString("project_name", project).commit())
        openAttachment(title)
        println("PICKER_PDF_COMMITTED=$title")
    }

    /** Parent removes the exact generated PDF before running this independently. */
    @Test fun reopenPrivatePdfAfterOriginalRemoved() {
        val sourceState = shellRead("if test -e /sdcard/Download/MuyonRefactorFixtures/picker-paper.pdf; then echo present; else echo absent; fi").trim()
        assertEquals("Parent must remove only the generated original PDF first", "absent", sourceState)
        val title = requireNotNull(preferences.getString("paper_title", null)) { "Run the successful PDF picker test first" }
        openResearch()
        selectProject(requireNotNull(preferences.getString("project_name", null)))
        openAttachment(title)
        println("PICKER_PRIVATE_ATTACHMENT_AFTER_SOURCE_REMOVAL=PASS")
    }

    @Test fun zipSystemPickerReviewAndImport() {
        openResearch()
        createProject("Picker ZIP")
        compose.onNodeWithText("导入科研工作台 ZIP").performScrollTo().performClick()
        chooseDocument("picker-workspace.zip")
        confirmImport("picker-zip-${UUID.randomUUID()}")
    }

    @Test fun directorySystemPickerReviewAndImport() {
        openResearch()
        createProject("Picker directory")
        compose.onNodeWithText("导入科研工作台目录").performScrollTo().performClick()
        enterFixtureDirectory()
        openPickerDirectory("MuyonRefactorFixtures", "picker-workspace")
        systemClick(setOf("SELECT", "Select", "选择", "使用此文件夹"))
        // API/provider versions may show a separate directory-access grant dialog.
        val grantDeadline = SystemClock.uptimeMillis() + 2_000
        while (SystemClock.uptimeMillis() < grantDeadline) {
            if (trySystemClick(setOf("ALLOW", "Allow", "允许"))) break
            SystemClock.sleep(50)
        }
        confirmImport("picker-directory-${UUID.randomUUID()}")
    }

    private fun openResearch() {
        compose.waitUntil(20_000) {
            compose.onAllNodesWithText("创建新工作台").fetchSemanticsNodes().isNotEmpty() ||
                compose.onAllNodes(hasText("科研工作台") and hasClickAction()).fetchSemanticsNodes().isNotEmpty()
        }
        if (compose.onAllNodesWithText("创建新工作台").fetchSemanticsNodes().isNotEmpty()) {
            compose.onNodeWithText("创建新工作台").performClick()
        }
        compose.waitUntil(15_000) { compose.onAllNodes(hasText("科研工作台") and hasClickAction()).fetchSemanticsNodes().isNotEmpty() }
        compose.onNode(hasText("科研工作台") and hasClickAction()).performClick()
        waitTag("research-new-project")
        waitEnabled("research-new-project")
    }

    private fun createProject(prefix: String): String {
        val name = "$prefix ${UUID.randomUUID()}"
        clickTag("research-new-project")
        compose.onNodeWithTag("research-project-name").performScrollTo().performTextInput(name)
        clickTag("research-project-preview")
        waitTag("research-preview")
        clickTag("research-confirm")
        waitTag("research-receipt")
        // A newly created project is selected by the actual screen, independent of list pagination.
        waitTag("research-add-pdf")
        return name
    }

    private fun confirmImport(source: String) {
        waitTag("research-import-preview", 35_000)
        compose.onNodeWithTag("research-source-id").performScrollTo().performTextReplacement(source)
        clickTag("research-import-preview")
        waitTag("research-preview")
        compose.onNodeWithTag("research-preview").assertTextContains(source, substring = true)
        compose.onAllNodes(paperButton("System picker imported paper")).assertCountEquals(0)
        assertNoPublishedPaper("System picker imported paper")
        clickTag("research-confirm")
        waitPaper("System picker imported paper")
        compose.onNode(paperButton("System picker imported paper")).performScrollTo().performClick()
        waitTag("research-paper-detail")
        compose.onNodeWithTag("research-paper-detail").assertTextContains("System picker imported paper", substring = true)
        println("PICKER_IMPORT_COMMITTED=$source")
    }

    private fun selectProject(name: String) {
        // A test may follow many other real projects; navigate the visible product pagination.
        fun page() = compose.onNodeWithTag("research-project-page").fetchSemanticsNode()
            .config[SemanticsProperties.Text].joinToString { it.text }
        while (compose.onAllNodes(hasTestTag("research-project-previous") and isEnabled()).fetchSemanticsNodes().isNotEmpty()) {
            val previous = page()
            clickTag("research-project-previous")
            compose.waitUntil(15_000) { page() != previous }
            waitEnabled("research-new-project")
        }
        repeat(100) {
            val match = hasText(name, substring = true) and hasClickAction()
            if (compose.onAllNodes(match).fetchSemanticsNodes().isNotEmpty()) {
                compose.onNode(match).performScrollTo().performClick()
                return
            }
            assertTrue("Generated project missing from all visible project pages: $name",
                compose.onAllNodes(hasTestTag("research-project-next") and isEnabled()).fetchSemanticsNodes().isNotEmpty())
            val previous = page()
            clickTag("research-project-next")
            compose.waitUntil(15_000) { page() != previous }
            waitEnabled("research-new-project")
        }
        fail("Generated project not found after 100 project pages: $name")
    }

    private fun openAttachment(title: String) {
        waitPaper(title)
        compose.onNode(paperButton(title)).performScrollTo().performClick()
        waitTag("research-paper-detail")
        clickTag("research-open-attachment-0")
        compose.waitUntil(20_000) { compose.onAllNodesWithContentDescription("论文 PDF 第 1 页").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithContentDescription("论文 PDF 第 1 页").assertExists()
        compose.onNodeWithText("第 1 / 1 页").assertExists()
    }

    private fun waitPaper(title: String) = compose.waitUntil(20_000) {
        compose.onAllNodes(paperButton(title)).fetchSemanticsNodes().isNotEmpty()
    }
    private fun paperButton(title: String): SemanticsMatcher = hasText("$title · ", substring = true) and
        hasClickAction() and SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button)

    private fun assertNoPublishedPaper(title: String) {
        val projectId = requireNotNull(context.getSharedPreferences("muyon_product_research_v2", 0).getString("project_id", null))
        val connected = CountDownLatch(1)
        lateinit var reader: ProductClient
        instrumentation.runOnMainSync {
            reader = ProductClient(context) { if (it) connected.countDown() }
            reader.bind()
        }
        try {
            assertTrue("real read-only observer must connect", connected.await(15, TimeUnit.SECONDS))
            var offset = 0
            val seen = mutableSetOf<String>()
            do {
                val done = CountDownLatch(1)
                var reply: JSONObject? = null
                instrumentation.runOnMainSync {
                    reader.call("papers", JSONObject().put("project_id", projectId).put("limit", 10).put("offset", offset)) {
                        reply = it; done.countDown()
                    }
                }
                assertTrue("real paper page must return", done.await(35, TimeUnit.SECONDS))
                val response = requireNotNull(reply)
                assertEquals("a failed read cannot prove absence: $response", "ok", response.getString("status"))
                val rows = response.getJSONArray("data")
                assertTrue(rows.length() <= 10)
                for (index in 0 until rows.length()) {
                    val row = rows.getJSONObject(index)
                    assertTrue("real paper pages must not repeat ids", seen.add(row.getString("id")))
                    assertNotEquals("preview must not publish this exact title", title, row.getString("title"))
                }
                offset += rows.length()
            } while (rows.length() == 10)
        } finally { instrumentation.runOnMainSync { reader.close() } }
    }
    private fun waitTag(tag: String, timeout: Long = 20_000) = compose.waitUntil(timeout) {
        compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
    }
    private fun clickTag(tag: String) {
        waitEnabled(tag)
        val node = compose.onNodeWithTag(tag)
        if (tag != "research-confirm") node.performScrollTo()
        node.performClick()
    }
    private fun waitEnabled(tag: String) = compose.waitUntil(20_000) {
        compose.onAllNodes(hasTestTag(tag) and isEnabled()).fetchSemanticsNodes().isNotEmpty()
    }

    private fun chooseDocument(name: String) {
        enterFixtureDirectory()
        systemClick(setOf(name))
    }

    private fun enterFixtureDirectory() {
        waitSystem("DocumentsUI is foreground") { root -> root.packageName?.toString() == "com.android.documentsui" }
        // Open navigation roots so a prior provider/location cannot select an unrelated file.
        systemClick(setOf("Show roots", "显示根目录", "显示位置", "Open navigation drawer"), byDescription = true)
        systemClick(setOf("Downloads", "下载", "下载内容"))
        // A chooser can reopen in the old target directory. Do not mistake that
        // stale toolbar for arrival while the Downloads navigation is still queued.
        waitSystem("Downloads root navigation is complete") { root ->
            hasToolbarTitle(root, "Downloads") && !hasVisibleResource(root, "com.android.documentsui:id/roots_list")
        }
        openPickerDirectory("Downloads", "MuyonRefactorFixtures")
    }

    private fun openPickerDirectory(parentTitle: String, directory: String) {
        waitSystem("picker directory $directory is actually open") { root ->
            // Re-read actual navigation state before every attempt; never tap after arrival.
            if (hasToolbarTitle(root, directory)) return@waitSystem true
            if (!hasToolbarTitle(root, parentTitle)) return@waitSystem false
            if (hasVisibleResource(root, "com.android.documentsui:id/roots_list")) return@waitSystem false
            val list = findNode(root) { it.viewIdResourceName == "com.android.documentsui:id/dir_list" }
                ?: return@waitSystem false
            val folder = findNode(list) {
                it.packageName?.toString() == "com.android.documentsui" &&
                    it.viewIdResourceName == "android:id/title" && it.text?.toString() == directory &&
                    it.isVisibleToUser && it.isEnabled
            } ?: return@waitSystem false
            // A drawer transition may consume an earlier tap. Only an unchanged parent
            // and its still-visible exact child permit another bounded navigation attempt.
            if (touchMatchedNode(folder)) automation.waitForIdle(250, 5_000)
            automation.rootInActiveWindow?.let { hasToolbarTitle(it, directory) } == true
        }
    }

    private fun hasVisibleResource(root: AccessibilityNodeInfo, id: String): Boolean =
        findNode(root) { it.viewIdResourceName == id && it.isVisibleToUser } != null

    private fun findNode(root: AccessibilityNodeInfo, predicate: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo? {
        if (predicate(root)) return root
        for (index in 0 until root.childCount) {
            val child = root.getChild(index) ?: continue
            findNode(child, predicate)?.let { return it }
        }
        return null
    }

    private fun systemClick(names: Set<String>, byDescription: Boolean = false) {
        waitSystem("DocumentsUI control $names") { trySystemClick(names, byDescription) }
        // Synchronize on real accessibility quiescence after drawer/window transitions.
        // A successful dispatched action alone does not mean the next row is unobscured.
        automation.waitForIdle(250, 5_000)
    }

    private fun trySystemClick(names: Set<String>, byDescription: Boolean = false): Boolean {
        val root = automation.rootInActiveWindow ?: return false
        fun walk(node: AccessibilityNodeInfo): Boolean {
            val label = if (byDescription) node.contentDescription?.toString() else node.text?.toString()
            if (label in names && node.isVisibleToUser && node.isEnabled) {
                var target: AccessibilityNodeInfo? = node
                while (target != null && !target.isClickable) target = target.parent
                if (target?.performAction(AccessibilityNodeInfo.ACTION_CLICK) == true) return true
                // API26 DocumentsUI's RecyclerView handles row gestures while its file title
                // and every ancestor advertise clickable=false. Use the exact matched title's
                // current screen bounds, not guessed coordinates or a fabricated result.
                if (node.packageName?.toString() == "com.android.documentsui" &&
                    node.viewIdResourceName == "android:id/title" && touchMatchedNode(node)) return true
            }
            for (index in 0 until node.childCount) {
                val child = node.getChild(index) ?: continue
                if (walk(child)) return true
            }
            return false
        }
        return walk(root)
    }

    private fun touchMatchedNode(node: AccessibilityNodeInfo): Boolean {
        if (!node.refresh()) return false
        val bounds = Rect()
        node.getBoundsInScreen(bounds)
        if (bounds.isEmpty) return false
        // This is the same real input-command path verified on the retained API26 failure
        // screen. Raw injectInputEvent acceptance previously left the directory unchanged.
        val output = automation.executeShellCommand("input tap ${bounds.exactCenterX()} ${bounds.exactCenterY()}").use { descriptor ->
            android.os.ParcelFileDescriptor.AutoCloseInputStream(descriptor).bufferedReader().use { it.readText() }
        }
        assertEquals("system input command must not report an error", "", output.trim())
        return true
    }

    private fun hasToolbarTitle(root: AccessibilityNodeInfo, title: String): Boolean {
        fun containsTitle(node: AccessibilityNodeInfo): Boolean {
            if (node.isVisibleToUser && node.text?.toString() == title) return true
            return (0 until node.childCount).any { index -> node.getChild(index)?.let(::containsTitle) == true }
        }
        if (root.viewIdResourceName == "com.android.documentsui:id/toolbar" && containsTitle(root)) return true
        return (0 until root.childCount).any { index -> root.getChild(index)?.let { hasToolbarTitle(it, title) } == true }
    }

    private fun waitSystem(description: String, condition: (AccessibilityNodeInfo) -> Boolean) {
        val deadline = SystemClock.uptimeMillis() + 15_000
        while (SystemClock.uptimeMillis() < deadline) {
            val root = automation.rootInActiveWindow
            if (root != null && condition(root)) return
            SystemClock.sleep(50)
        }
        val root = automation.rootInActiveWindow
        fun labels(node: AccessibilityNodeInfo?): String {
            if (node == null) return "<no active window>"
            return "[${node.packageName}|${node.text}|${node.contentDescription}|${node.viewIdResourceName}]" +
                (0 until node.childCount).joinToString("") { labels(node.getChild(it)) }
        }
        fail("Timed out waiting for $description; actual accessibility tree: ${labels(root)}")
    }

    private fun shellRead(command: String): String = automation.executeShellCommand(command).use { descriptor ->
        android.os.ParcelFileDescriptor.AutoCloseInputStream(descriptor).bufferedReader().use { it.readText() }
    }
}
