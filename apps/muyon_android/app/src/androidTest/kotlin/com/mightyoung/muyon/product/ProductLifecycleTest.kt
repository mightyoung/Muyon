package com.mightyoung.muyon.product

import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.view.KeyEvent
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.product.agentipc.ProductClient
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Real Activity configuration/back events and real private Service/native queries. */
class ProductLifecycleTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private lateinit var observer: ProductClient

    @Before fun ready() {
        observer = connect()
        val health = call(observer, "health")
        if (health.optString("status") != "ok" && !observer.workspaceExists) {
            compose.waitUntil(15_000) { compose.onAllNodesWithText("创建新工作台").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithText("创建新工作台").performClick()
        } else assertEquals("existing real workspace must be readable: $health", "ok", health.getString("status"))
        compose.onNodeWithContentDescription("打开工作空间导航").performClick()
        compose.onNodeWithTag("nav-supplier").performClick()
        waitEnabled("supplier-new")
        assertNull("prior unresolved intent requires its own recovery", context.getSharedPreferences("muyon_product_supplier_v2", 0).getString("intent_id", null))
    }

    @After fun close() {
        if (::observer.isInitialized) instrumentation.runOnMainSync { observer.close() }
    }

    @Test fun backFromReviewThenRealRotationDiscardsUnconfirmedDraftWithoutWriting() {
        val name = "Lifecycle draft ${UUID.randomUUID()}"
        compose.onNodeWithTag("supplier-new").performScrollTo().performClick()
        compose.onNodeWithTag("supplier-field-name").performScrollTo().performTextInput(name)
        compose.onNodeWithTag("supplier-field-address").performScrollTo().performTextInput("Unconfirmed lifecycle address")
        preview()
        val first = previewCommand()
        val id = first.getString("supplier_id")
        assertEquals(name, first.getJSONObject("payload").getString("name"))
        assertEquals("Unconfirmed lifecycle address", first.getJSONObject("payload").getString("address"))
        assertAbsent(id, name)

        instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
        compose.waitUntil(15_000) { compose.onAllNodesWithTag("supplier-preview").fetchSemanticsNodes().isEmpty() }
        compose.onNodeWithTag("supplier-field-name").assertTextContains(name)
        compose.onNodeWithTag("supplier-field-address").assertTextContains("Unconfirmed lifecycle address")
        assertAbsent(id, name)
        preview()
        assertEquals("returning from review must retain the same draft identity", id, previewCommand().getString("supplier_id"))

        val originalActivity = compose.activity
        val originalOrientation = originalActivity.resources.configuration.orientation
        val requested = if (originalOrientation == Configuration.ORIENTATION_LANDSCAPE)
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT else ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        val expected = if (originalOrientation == Configuration.ORIENTATION_LANDSCAPE)
            Configuration.ORIENTATION_PORTRAIT else Configuration.ORIENTATION_LANDSCAPE
        instrumentation.runOnMainSync { originalActivity.requestedOrientation = requested }
        compose.waitUntil(20_000) {
            compose.activity !== originalActivity && compose.activity.resources.configuration.orientation == expected
        }
        // Draft/plan use remember, not rememberSaveable: a real rotation drops unconfirmed UI state.
        waitEnabled("supplier-new")
        compose.onNodeWithTag("supplier-preview").assertDoesNotExist()
        compose.onNodeWithTag("supplier-field-name").assertDoesNotExist()
        compose.onNodeWithTag("supplier-receipt").assertDoesNotExist()
        compose.onAllNodesWithText("已提交", substring = true).assertCountEquals(0)
        assertAbsent(id, name)
        assertNull(context.getSharedPreferences("muyon_product_supplier_v2", 0).getString("intent_id", null))
    }

    @Test fun closingLeaseBeforePrepareReplyCannotReportStaleSuccessOrPublishSupplier() {
        val stale = connect()
        try {
            val id = "lifecycle-${UUID.randomUUID()}"
            val name = "Closed lease supplier $id"
            val replies = mutableListOf<JSONObject>()
            val request = JSONObject().put("expected_revision", "0").put("operation", JSONObject()
                .put("operation", "supplier_create").put("supplier_id", id).put("payload", JSONObject()
                    .put("name", name).put("aliases", JSONArray()).put("categories", JSONArray())))
            // Main-looper execution makes close happen before the remote reply handler can run.
            instrumentation.runOnMainSync {
                stale.call("prepare", request) { replies += it }
                stale.close()
            }
            // A new real client connection and round-trip pass through the same Service worker.
            // These are protocol barriers, not a sleep waiting for a race to happen.
            val fresh = connect()
            try {
                repeat(2) {
                    val health = call(fresh, "health")
                    assertEquals(health.toString(), "ok", health.getString("status"))
                }
                instrumentation.waitForIdleSync()
                instrumentation.runOnMainSync {
                    assertEquals("closed request must settle once, never gain a late success", 1, replies.size)
                    assertEquals("unknown", replies.single().getString("status"))
                    assertEquals("service_disconnected", replies.single().getString("error"))
                    assertEquals("query_original", replies.single().getString("recovery_action"))
                }
                assertAbsent(id, name)
                compose.onNodeWithTag("supplier-receipt").assertDoesNotExist()
                assertNull(context.getSharedPreferences("muyon_product_supplier_v2", 0).getString("intent_id", null))
            } finally { instrumentation.runOnMainSync { fresh.close() } }
        } finally { instrumentation.runOnMainSync { stale.close() } }
    }

    private fun preview() {
        waitEnabled("supplier-save-preview")
        compose.onNodeWithTag("supplier-save-preview").performScrollTo().performClick()
        compose.waitUntil(15_000) { compose.onAllNodesWithTag("supplier-preview").fetchSemanticsNodes().isNotEmpty() }
    }
    private fun previewCommand(): JSONObject = JSONObject(compose.onNodeWithTag("supplier-preview")
        .fetchSemanticsNode().config[SemanticsProperties.Text].single().text)

    private fun assertAbsent(id: String, name: String) {
        val missing = call(observer, "supplier", JSONObject().put("id", id))
        assertEquals("a transport/storage failure is not evidence of absence: $missing", "NotFound", missing.getString("error"))
        assertNotEquals("ok", missing.getString("status"))
        val seen = mutableSetOf<String>()
        var offset = 0
        do {
            val page = call(observer, "suppliers", JSONObject().put("limit", 10).put("offset", offset))
            assertEquals(page.toString(), "ok", page.getString("status"))
            val rows = page.getJSONArray("data")
            assertTrue(rows.length() <= 10)
            for (index in 0 until rows.length()) {
                val row = rows.getJSONObject(index)
                assertTrue("each id appears once across pages", seen.add(row.getString("id")))
                assertNotEquals("unconfirmed id must not be published", id, row.getString("id"))
                assertNotEquals("unconfirmed exact field value must not be published", name, row.getJSONObject("payload").getString("name"))
            }
            offset += rows.length()
        } while (rows.length() == 10)
    }
    private fun waitEnabled(tag: String) = compose.waitUntil(20_000) {
        compose.onAllNodes(hasTestTag(tag) and isEnabled()).fetchSemanticsNodes().isNotEmpty()
    }
    private fun connect(): ProductClient {
        val connected = CountDownLatch(1)
        lateinit var client: ProductClient
        instrumentation.runOnMainSync {
            client = ProductClient(context) { if (it) connected.countDown() }
            client.bind()
        }
        assertTrue("real product lease must connect", connected.await(15, TimeUnit.SECONDS))
        return client
    }
    private fun call(client: ProductClient, method: String, payload: JSONObject = JSONObject()): JSONObject {
        val done = CountDownLatch(1)
        var reply: JSONObject? = null
        instrumentation.runOnMainSync { client.call(method, payload) { reply = it; done.countDown() } }
        assertTrue("real $method response must arrive", done.await(35, TimeUnit.SECONDS))
        return requireNotNull(reply)
    }
}
