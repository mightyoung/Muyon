package com.mightyoung.muyon.product.supplier

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

/** Uses the real bound product Service and native business store; no recording client. */
class SupplierProductTest {
    @get:Rule val compose = createComposeRule()
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private lateinit var client: ProductClient

    @Before fun connect() {
        val connected = CountDownLatch(1)
        instrumentation.runOnMainSync {
            client = ProductClient(instrumentation.targetContext) { if (it) connected.countDown() }
            client.bind()
        }
        assertTrue("real service must connect", connected.await(15, TimeUnit.SECONDS))
        val database = File(instrumentation.targetContext.filesDir, "muyon-product-v2/business-v2.sqlite")
        val health = call("health")
        val readiness = if (health.optString("status") != "ok" && !database.isFile) call("initialize") else health
        assertEquals("real product readiness: $readiness", "ok", readiness.getString("status"))
        assertNull("resolve an existing supplier intent before running this test", instrumentation.targetContext
            .getSharedPreferences("muyon_product_supplier_v2", 0).getString("intent_id", null))
        compose.setContent { MaterialTheme { SupplierScreen(client) } }
    }

    @After fun close() { if (::client.isInitialized) instrumentation.runOnMainSync { client.close() } }

    private fun call(method: String, payload: JSONObject = JSONObject()): JSONObject {
        val done = CountDownLatch(1)
        var result: JSONObject? = null
        instrumentation.runOnMainSync { client.call(method, payload) { result = it; done.countDown() } }
        assertTrue("real $method response", done.await(35, TimeUnit.SECONDS))
        return requireNotNull(result)
    }

    private fun click(tag: String) {
        val node = compose.onNodeWithTag(tag)
        if (tag == "supplier-confirm") node.performClick() else node.performScrollTo().performClick()
    }
    private fun waitFor(tag: String) {
        compose.waitUntil(15_000) { compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty() }
    }
    private fun select(name: String) {
        fun ready() { compose.waitUntil(15_000) { compose.onAllNodes(hasTestTag("supplier-new") and isEnabled()).fetchSemanticsNodes().isNotEmpty() } }
        ready()
        while (compose.onAllNodes(hasTestTag("supplier-previous") and isEnabled()).fetchSemanticsNodes().isNotEmpty()) { click("supplier-previous"); ready() }
        while (compose.onAllNodes(hasText("$name ·", substring = true) and hasClickAction()).fetchSemanticsNodes().isEmpty()) {
            compose.onNodeWithTag("supplier-next").assertIsEnabled()
            click("supplier-next"); ready()
        }
        compose.onNode(hasText("$name ·", substring = true) and hasClickAction()).performScrollTo().performClick()
    }
    private fun suppliers(): List<JSONObject> {
        val result = mutableListOf<JSONObject>()
        while (true) {
            val reply = call("suppliers", JSONObject().put("limit", 10).put("offset", result.size))
            assertEquals(reply.toString(), "ok", reply.getString("status"))
            val rows = reply.getJSONArray("data")
            (0 until rows.length()).forEach { result += rows.getJSONObject(it) }
            if (rows.length() < 10) return result
        }
    }

    @Test fun visibleReviewCrudUsesActualReceipts() {
        val name = "Supplier-${UUID.randomUUID()}"
        click("supplier-new")
        val values = mapOf("name" to name, "aliases" to "Alias A\nAlias B", "address" to "Lab 26",
            "categories" to "Optics\nElectronics", "notes" to "Original note", "rating" to "preferred", "rating_note" to "Reviewed")
        values.forEach { (key, value) -> compose.onNodeWithTag("supplier-field-$key").performScrollTo().performTextInput(value) }
        click("supplier-save-preview")
        waitFor("supplier-preview")
        // A visible preview has no business side effect.
        assertFalse(suppliers().any { it.getJSONObject("payload").getString("name") == name })
        click("supplier-confirm")
        waitFor("supplier-receipt")
        val created = suppliers().single { it.getJSONObject("payload").getString("name") == name }
        val id = created.getString("id")
        assertEquals("Lab 26", created.getJSONObject("payload").getString("address"))
        assertEquals(2, created.getJSONObject("payload").getJSONArray("aliases").length())
        assertEquals("preferred", created.getJSONObject("payload").getString("rating"))
        select(name)
        click("supplier-edit")
        compose.onNodeWithTag("supplier-field-notes").performScrollTo().performTextReplacement("Updated note")
        click("supplier-save-preview")
        click("supplier-confirm")
        compose.waitUntil(15_000) { compose.onAllNodesWithText("已提交 · 版本 2").fetchSemanticsNodes().isNotEmpty() }
        select(name)
        click("supplier-delete")
        click("supplier-confirm")
        compose.waitUntil(15_000) { compose.onAllNodesWithText("已提交 · 版本 3").fetchSemanticsNodes().isNotEmpty() }
        assertFalse(suppliers().any { it.getString("id") == id })
        compose.onNodeWithText("查看已删除").performScrollTo().performClick()
        select(name)
        click("supplier-restore")
        click("supplier-confirm")
        compose.waitUntil(15_000) { compose.onAllNodesWithText("已提交 · 版本 4").fetchSemanticsNodes().isNotEmpty() }
        val restoredReply = call("supplier", JSONObject().put("id", id))
        assertEquals(restoredReply.toString(), "ok", restoredReply.getString("status"))
        val restored = restoredReply.getJSONObject("data")
        assertEquals("Updated note", restored.getJSONObject("payload").getString("notes"))
        assertEquals("Reviewed", restored.getJSONObject("payload").getString("rating_note"))
    }

    @Test fun dismissingReviewKeepsDraftAndDoesNotWrite() {
        val name = "Unconfirmed-${UUID.randomUUID()}"
        click("supplier-new")
        compose.onNodeWithTag("supplier-field-name").performTextInput(name)
        click("supplier-save-preview")
        waitFor("supplier-preview")
        compose.onNodeWithText("返回修改").performClick()
        compose.onNodeWithTag("supplier-field-name").assertTextContains(name)
        assertFalse(suppliers().any { it.getJSONObject("payload").getString("name") == name })
        compose.onNodeWithText("放弃草稿").performScrollTo().performClick()
        compose.onNodeWithText("继续编辑").performClick()
        compose.onNodeWithTag("supplier-field-name").assertTextContains(name)
        compose.onNodeWithText("放弃草稿").performScrollTo().performClick()
        compose.onNodeWithText("放弃", useUnmergedTree = true).performClick()
        compose.onNodeWithTag("supplier-new").assertExists()
    }

    @Test fun elevenRealSuppliersAreReachableThroughNextPage() {
        val prefix = "Pagination-${UUID.randomUUID()}"
        val created = mutableListOf<Pair<String, String>>()
        repeat(11) { index ->
            val id = UUID.randomUUID().toString()
            created += id to "$prefix-$index"
            val payload = JSONObject().put("name", "$prefix-$index").put("aliases", JSONArray())
                .put("categories", JSONArray()).put("address", JSONObject.NULL).put("notes", JSONObject.NULL)
                .put("rating", JSONObject.NULL).put("rating_note", JSONObject.NULL).put("merged_into", JSONObject.NULL)
            val prepared = call("prepare", JSONObject().put("expected_revision", "0").put("operation", JSONObject()
                .put("operation", "supplier_create").put("supplier_id", id).put("payload", payload)))
            assertEquals(prepared.toString(), "ok", prepared.getString("status"))
            val plan = prepared.getJSONObject("data")
            val committed = call("confirm", JSONObject().put("plan_id", plan.getString("plan_id")))
            assertEquals(committed.toString(), "committed", committed.getJSONObject("data").getString("status"))
            assertEquals(plan.getString("intent_id"), committed.getJSONObject("data").getJSONObject("receipt").getString("intent_id"))
            call("discard", JSONObject().put("plan_id", plan.getString("plan_id")))
        }
        compose.onNodeWithText("刷新当前值").performScrollTo().performClick()
        val target = created.maxBy { it.first }.second
        select(target)
        val pageText = compose.onNodeWithTag("supplier-page").fetchSemanticsNode().config[SemanticsProperties.Text].joinToString { it.text }
        assertFalse("last of eleven new rows must cross page zero: $pageText", pageText.startsWith("供应商偏移：0 ·"))
        click("supplier-edit")
        compose.onNodeWithTag("supplier-next").assertDoesNotExist()
        compose.onNodeWithTag("supplier-field-name").assertTextContains(target)
    }
}
