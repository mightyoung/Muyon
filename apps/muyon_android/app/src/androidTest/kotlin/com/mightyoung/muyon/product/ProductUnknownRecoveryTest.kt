package com.mightyoung.muyon.product

import android.database.sqlite.SQLiteDatabase
import android.os.Process
import android.os.SystemClock
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.product.agentipc.ProductClient
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Real P04 client loses its callback after an independently observed SQL COMMIT.
 * The UI resumes the same durable marker. No transport, store or callback is faked.
 */
class ProductUnknownRecoveryTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test fun supplierConfirmationNotReceivedUnlocksOnlyAfterDurableSealInUi() = unreceivedConfirmation("supplier")

    @Test fun researchConfirmationNotReceivedUnlocksOnlyAfterDurableSealInUi() = unreceivedConfirmation("research")

    private fun unreceivedConfirmation(kind: String) {
        val owner = connect()
        val preferences = context.getSharedPreferences("muyon_product_${kind}_v2", 0)
        assertNull("do not overwrite an existing unresolved original", preferences.getString("intent_id", null))
        try {
            val ready = call(owner, if (owner.workspaceExists) "health" else "initialize")
            assertEquals(ready.toString(), "ok", ready.getString("status"))
            val id = "unreceived-${UUID.randomUUID()}"
            val operation = if (kind == "supplier") JSONObject().put("operation", "supplier_create")
                .put("supplier_id", id).put("payload", JSONObject().put("name", id)
                    .put("aliases", JSONArray()).put("categories", JSONArray()))
            else JSONObject().put("operation", "project_create").put("project_id", id).put("name", id)
            val plan = call(owner, "prepare", JSONObject().put("operation", operation)
                .put("expected_revision", "0")).getJSONObject("data")
            val intent = plan.getString("intent_id")
            // Exact crash boundary from the review: client marker is durable,
            // but NO confirm call has been delivered to the separate Service.
            assertTrue(preferences.edit().putString("intent_id", intent).commit())
            val pid = call(owner, "health").getJSONObject("data").getInt("service_pid")
            assertNotEquals(Process.myPid(), pid)
            instrumentation.runOnMainSync { owner.close(); Process.killProcess(pid) }
            compose.activityRule.scenario.recreate()
            compose.waitUntil(20_000) {
                compose.onAllNodesWithContentDescription("打开工作空间导航").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithContentDescription("打开工作空间导航").performClick()
            compose.onNodeWithTag("nav-$kind").performClick()
            compose.waitUntil(20_000) {
                compose.onAllNodes(hasTestTag("$kind-lookup") and isEnabled()).fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithTag("$kind-receipt").assertDoesNotExist()
            compose.onNodeWithTag("$kind-lookup").performScrollTo().performClick()
            compose.waitUntil(20_000) { preferences.getString("intent_id", null) == null }
            compose.onNodeWithTag("$kind-status").assertTextContains("核心未接收此确认", substring = true)
            compose.onNodeWithTag(if (kind == "supplier") "supplier-new" else "research-new-project")
                .performScrollTo().assertIsEnabled()
            compose.onNodeWithTag("$kind-receipt").assertDoesNotExist()
            val fresh = connect()
            try {
                val result = call(fresh, "lookup", JSONObject().put("intent_id", intent)).getJSONObject("data")
                assertEquals("not_submitted", result.getString("status"))
                assertTrue(result.isNull("receipt"))
                SQLiteDatabase.openDatabase(File(context.filesDir, "muyon-product-v2/business-v2.sqlite").absolutePath,
                    null, SQLiteDatabase.OPEN_READONLY).use { database ->
                    for ((table, column, value) in listOf(Triple("intents", "intent_id", intent),
                        Triple(if (kind == "supplier") "supplier" else "projects", "id", id))) {
                        database.rawQuery("SELECT count(*) FROM $table WHERE $column=?", arrayOf(value)).use { cursor ->
                            assertTrue(cursor.moveToFirst()); assertEquals("no original replay or write", 0, cursor.getInt(0))
                        }
                    }
                }
            } finally { instrumentation.runOnMainSync { fresh.close() } }
        } finally { instrumentation.runOnMainSync { owner.close() } }
    }

    @Test fun committedWriteWithLostClientReplyRecoversOnlyOriginalReceiptInUi() {
        val owner = connect()
        val preferences = context.getSharedPreferences("muyon_product_supplier_v2", 0)
        val chatPreferences = context.getSharedPreferences("product-chat-state", 0)
        assertNull("an earlier unresolved original must not be overwritten", preferences.getString("intent_id", null))
        assertNull("an earlier unresolved chat business original must not be overwritten", chatPreferences.getString("original_business_intent", null))
        try {
            val admission = call(owner, if (owner.workspaceExists) "health" else "initialize")
            assertEquals(admission.toString(), "ok", admission.getString("status"))
            val ready = call(owner, "health")
            assertEquals(ready.toString(), "ok", ready.getString("status"))
            val pid = ready.getJSONObject("data").getInt("service_pid")
            assertNotEquals(Process.myPid(), pid)
            val id = UUID.randomUUID().toString()
            val name = "Lost reply ${UUID.randomUUID()}"
            val operation = JSONObject().put("operation", "supplier_create").put("supplier_id", id)
                .put("payload", JSONObject().put("name", name).put("address", "Committed before callback loss")
                    .put("aliases", JSONArray()).put("categories", JSONArray()))
            val plan = call(owner, "prepare", JSONObject().put("operation", operation).put("expected_revision", "0"))
                .getJSONObject("data")
            val intent = plan.getString("intent_id")
            // This test writes the same durable client journal as SupplierScreen before
            // its send. It tests protocol-loss plus real UI recovery, not a synthetic UI click.
            assertTrue(preferences.edit().putString("intent_id", intent).putString("supplier_id", id).commit())
            assertTrue(chatPreferences.edit().putString("original_business_intent", intent)
                .putString("original_business_plan", plan.getString("plan_id")).commit())
            var observedReceipt: String? = null
            var callback: JSONObject? = null
            val path = File(context.filesDir, "muyon-product-v2/business-v2.sqlite")
            SQLiteDatabase.openDatabase(path.absolutePath, null, SQLiteDatabase.OPEN_READONLY).use { database ->
                instrumentation.runOnMainSync {
                    owner.call("confirm", JSONObject().put("plan_id", plan.getString("plan_id"))) { callback = it }
                    // Holding this test's main looper prevents the Messenger callback
                    // from running while the independent Service commits real SQLite.
                    val deadline = SystemClock.elapsedRealtime() + 3_000
                    while (observedReceipt == null && SystemClock.elapsedRealtime() < deadline) {
                        database.rawQuery("SELECT receipt_json FROM intents WHERE intent_id=? AND status='committed'", arrayOf(intent)).use { cursor ->
                            if (cursor.moveToFirst()) observedReceipt = cursor.getString(0)
                        }
                        if (observedReceipt == null) SystemClock.sleep(5)
                    }
                    assertNotNull("actual COMMIT must precede callback loss", observedReceipt)
                    assertNull("the committed reply has not reached its client callback", callback)
                    owner.close() // Suppresses even an already queued reply; settles unknown exactly once.
                    assertEquals("unknown", callback!!.getString("status"))
                    assertEquals("query_original", callback!!.getString("recovery_action"))
                    Process.killProcess(pid)
                }
            }
            assertEquals(intent, preferences.getString("intent_id", null))
            compose.activityRule.scenario.recreate()
            compose.waitUntil(20_000) {
                compose.onAllNodesWithContentDescription("打开工作空间导航").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithContentDescription("打开工作空间导航").performClick()
            compose.onNodeWithTag("nav-supplier").performClick()
            compose.waitUntil(20_000) {
                compose.onAllNodes(hasTestTag("supplier-lookup") and isEnabled()).fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithTag("supplier-receipt").assertDoesNotExist()
            compose.onNodeWithTag("supplier-lookup").performScrollTo().performClick()
            compose.waitUntil(20_000) {
                compose.onAllNodesWithTag("supplier-receipt").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithTag("supplier-receipt").assertTextContains(intent, substring = true)
            compose.onNodeWithTag("supplier-receipt").assertTextContains(id, substring = true)
            assertNull(preferences.getString("intent_id", null))
            // Chat must query an original business receipt after losing its
            // runtime tool origin, without configuring or contacting a model.
            compose.onNodeWithContentDescription("打开工作空间导航").performClick()
            compose.onNodeWithTag("nav-chat").performClick()
            compose.waitUntil(15_000) {
                compose.onAllNodesWithTag("chat-business-original-lookup").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithTag("chat-business-original-lookup").performScrollTo().performClick()
            compose.waitUntil(15_000) {
                compose.onAllNodes(hasTestTag("chat-business-original-result") and
                    hasText(intent, substring = true) and hasText(id, substring = true)).fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithTag("chat-business-original-result").assertTextContains(intent, substring = true)
            compose.onNodeWithTag("chat-business-original-result").assertTextContains(id, substring = true)
            assertNull(chatPreferences.getString("original_business_intent", null))
            val fresh = connect()
            try {
                val recovered = call(fresh, "lookup", JSONObject().put("intent_id", intent)).getJSONObject("data")
                assertEquals("committed", recovered.getString("status"))
                assertEquals(JSONObject(observedReceipt!!).toString(), recovered.getJSONObject("receipt").toString())
                val supplier = call(fresh, "supplier", JSONObject().put("id", id)).getJSONObject("data")
                assertEquals(name, supplier.getJSONObject("payload").getString("name"))
                assertEquals("1", supplier.getString("revision"))
                SQLiteDatabase.openDatabase(path.absolutePath, null, SQLiteDatabase.OPEN_READONLY).use { database ->
                    database.rawQuery("SELECT count(*) FROM supplier_history WHERE intent_id=?", arrayOf(intent)).use { cursor ->
                        assertTrue(cursor.moveToFirst()); assertEquals(1, cursor.getInt(0))
                    }
                }
            } finally { instrumentation.runOnMainSync { fresh.close() } }
        } finally { instrumentation.runOnMainSync { owner.close() } }
    }

    private fun connect(): ProductClient {
        val ready = CountDownLatch(1)
        lateinit var client: ProductClient
        instrumentation.runOnMainSync {
            client = ProductClient(context) { if (it) ready.countDown() }
            client.bind()
        }
        assertTrue(ready.await(15, TimeUnit.SECONDS))
        return client
    }
    private fun call(client: ProductClient, method: String, payload: JSONObject = JSONObject()): JSONObject {
        val done = CountDownLatch(1)
        var response: JSONObject? = null
        instrumentation.runOnMainSync { client.call(method, payload) { response = it; done.countDown() } }
        assertTrue(done.await(35, TimeUnit.SECONDS))
        return requireNotNull(response)
    }
}
