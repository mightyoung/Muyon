package com.mightyoung.muyon.product

import android.app.ActivityManager
import android.content.Context
import android.os.Process
import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.product.agentipc.ProductClient
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Real private Service process and real bundled SQLite, no fixture runtime. */
class ProductRecoveryTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private lateinit var client: ProductClient
    private fun connect() {
        val ready = CountDownLatch(1)
        instrumentation.runOnMainSync {
            client = ProductClient(context) { if (it) ready.countDown() }
            client.bind()
        }
        assertTrue("new real Service connection", ready.await(15, TimeUnit.SECONDS))
    }
    private fun call(method: String, payload: JSONObject = JSONObject()): JSONObject {
        val done = CountDownLatch(1)
        var response: JSONObject? = null
        instrumentation.runOnMainSync { client.call(method, payload) { response = it; done.countDown() } }
        assertTrue("$method must return", done.await(35, TimeUnit.SECONDS))
        return requireNotNull(response)
    }
    private fun close() = instrumentation.runOnMainSync { client.close() }
    @Test fun rapidCloseAndRebindWaitsForPriorOwnersWithoutKillingTheProcess() {
        val epochs = mutableSetOf<String>()
        val processes = mutableSetOf<Int>()
        repeat(8) {
            connect()
            try {
                // No retry: Binder readiness followed immediately by a real read.
                val reply = call("health")
                assertEquals(reply.toString(), "ok", reply.getString("status"))
                val health = reply.getJSONObject("data")
                epochs.add(health.getString("epoch"))
                processes.add(health.getInt("service_pid"))
            } finally { close() }
        }
        assertTrue("the test must cross an actual owner generation", epochs.size > 1)
        assertEquals("a process restart must not mask a stale native owner", 1, processes.size)
    }
    @Test fun closingWithAllRequestSlotsBusyStillRevokesTheLiveBinderLease() {
        connect()
        var other: ProductClient? = null
        try {
            val initialization = call(if (java.io.File(context.filesDir, "muyon-product-v2/business-v2.sqlite").isFile) "health" else "initialize")
            assertEquals(initialization.toString(), "ok", initialization.getString("status"))
            val ready = CountDownLatch(1)
            instrumentation.runOnMainSync { other = ProductClient(context) { if (it) ready.countDown() }.also { it.bind() } }
            assertTrue(ready.await(15, TimeUnit.SECONDS))
            instrumentation.runOnMainSync {
                repeat(128) { client.call("health") {} }
                client.close()
            }
            val deadline = android.os.SystemClock.elapsedRealtime() + 10_000
            var active = -1
            do {
                val done = CountDownLatch(1)
                instrumentation.runOnMainSync { other!!.call("health") { reply ->
                    active = reply.optJSONObject("data")?.optInt("active_clients", -1) ?: -1
                    done.countDown()
                } }
                assertTrue("other lease must stay usable", done.await(15, TimeUnit.SECONDS))
            } while (active != 1 && android.os.SystemClock.elapsedRealtime() < deadline)
            assertEquals("close must revoke even when pending=128 and Binder process is alive", 1, active)
        } finally {
            close()
            instrumentation.runOnMainSync { other?.close() }
        }
    }
    @Test fun actualServiceDeathChangesEpochAndOnlyOriginalReceiptRecovers() {
        connect()
        try {
            val initialization = call(if (java.io.File(context.filesDir, "muyon-product-v2/business-v2.sqlite").isFile) "health" else "initialize")
            assertEquals(initialization.toString(), "ok", initialization.getString("status"))
            val before = call("health").getJSONObject("data")
            assertFalse(before.getBoolean("synthetic"))
            assertEquals(BuildConfig.MUYON_SOURCE, before.getString("build_id"))
            assertFalse(before.getString("build_id").contains("unsealed"))
            val id = "recovery-${UUID.randomUUID()}"
            val operation = JSONObject().put("operation", "supplier_create").put("supplier_id", id)
                .put("payload", JSONObject().put("name", id).put("aliases", org.json.JSONArray()).put("categories", org.json.JSONArray()))
            val plan = call("prepare", JSONObject().put("operation", operation).put("expected_revision", "0")).getJSONObject("data")
            val intent = plan.getString("intent_id")
            val result = call("confirm", JSONObject().put("plan_id", plan.getString("plan_id"))).getJSONObject("data")
            assertEquals("committed", result.getString("status"))
            val receipt = result.getJSONObject("receipt").toString()
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val pid = manager.runningAppProcesses.single { it.processName == "${context.packageName}:core" }.pid
            assertTrue(pid != Process.myPid())
            close()
            Process.killProcess(pid)
            connect()
            val after = call("health").getJSONObject("data")
            assertNotEquals(before.getString("epoch"), after.getString("epoch"))
            val recovered = call("lookup", JSONObject().put("intent_id", intent)).getJSONObject("data")
            assertEquals("committed", recovered.getString("status"))
            assertEquals(receipt, recovered.getJSONObject("receipt").toString())
            val refused = call("confirm", JSONObject().put("plan_id", plan.getString("plan_id")))
            assertNotEquals("ok", refused.getString("status"))
            val pageSize = 10
            var offset = 0
            var recoveredIdCount = 0
            val listedIds = mutableSetOf<String>()
            do {
                assertTrue("supplier pagination must terminate within 10,000 rows", offset < 10_000)
                val page = call("suppliers", JSONObject().put("limit", pageSize).put("offset", offset))
                assertEquals("each real supplier page must succeed: $page", "ok", page.getString("status"))
                val rows = page.getJSONArray("data")
                assertTrue("page must respect the requested limit", rows.length() <= pageSize)
                for (index in 0 until rows.length()) {
                    val listedId = rows.getJSONObject(index).getString("id")
                    assertTrue("supplier must appear on exactly one page: $listedId", listedIds.add(listedId))
                    if (listedId == id) recoveredIdCount++
                }
                offset += rows.length()
            } while (rows.length() == pageSize)
            assertEquals("recovered supplier must occur exactly once across all pages", 1, recoveredIdCount)
            assertEquals("1", call("supplier", JSONObject().put("id", id)).getJSONObject("data").getString("revision"))
            val missing = call("lookup", JSONObject().put("intent_id", "unknown-${UUID.randomUUID()}"))
                .getJSONObject("data")
            assertEquals("unknown", missing.getString("status"))
            assertEquals("query_original", missing.getString("recovery_action"))
        } finally { close() }
    }
}
