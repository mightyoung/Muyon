package com.mightyoung.muyon.product

import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.product.agentipc.ProductClient
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** The identical JSON vectors run through real Kotlin IPC -> Service -> Rust preparation. */
class ContractVectorsProductTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private lateinit var client: ProductClient

    @Test fun sharedVectorsRejectWithoutPlansAndOneEightFieldReceiptSurvivesServiceReopen() {
        val fixture = JSONObject(instrumentation.context.assets.open("codec-vectors.json").bufferedReader(Charsets.UTF_8).use { it.readText() })
        val cases = fixture.getJSONArray("cases")
        assertEquals(32, cases.length())
        var confirmations = 0
        var committedId: String? = null
        var committedExpected: JSONObject? = null
        var committedReceipt: JSONObject? = null
        connect()
        try {
            val health = call("health")
            val readiness = if (health.optString("status") != "ok" && !client.workspaceExists) call("initialize") else health
            assertEquals(readiness.toString(), "ok", readiness.getString("status"))
            val originalEpoch = call("health").getJSONObject("data").getString("epoch")
            for (index in 0 until cases.length()) {
                val vector = cases.getJSONObject(index)
                val label = vector.getString("id")
                assertTrue("$label revision must remain JSON text", vector.get("revision") is String)
                val revision = vector.getString("revision")
                val id = "codec-${UUID.randomUUID()}-$label"
                val payload = materialize(fixture, vector)
                val operation = JSONObject().put("operation", vector.optString("operation", "supplier_create")).put("supplier_id", id).put("payload", payload)
                val reply = call("prepare", JSONObject().put("operation", operation).put("expected_revision", revision))
                if (vector.has("error")) {
                    assertNotEquals("$label invalid vector must not prepare: $reply", "ok", reply.getString("status"))
                    assertEquals(label, vector.getString("error"), reply.getString("error"))
                    assertFalse("$label must yield no plan", reply.has("plan_id"))
                    assertFalse("$label must yield no nested plan", reply.optJSONObject("data")?.has("plan_id") == true)
                    assertMissing(id, label)
                    continue
                }
                assertEquals("$label valid prepare: $reply", "ok", reply.getString("status"))
                val plan = reply.getJSONObject("data")
                assertTrue("$label Rust revision wire type", plan.get("expected_revision") is String)
                assertEquals("$label exact revision without floating conversion", revision, plan.getString("expected_revision"))
                assertEquals(label, id, plan.getJSONObject("command").getString("supplier_id"))
                assertMissing(id, "$label pure preparation")
                if (vector.optBoolean("confirm")) {
                    confirmations++
                    val committed = call("confirm", JSONObject().put("plan_id", plan.getString("plan_id")))
                    assertEquals(committed.toString(), "ok", committed.getString("status"))
                    val result = committed.getJSONObject("data")
                    assertEquals("committed", result.getString("status"))
                    val receipt = result.getJSONObject("receipt")
                    assertEquals(plan.getString("intent_id"), receipt.getString("intent_id"))
                    assertEquals(id, receipt.getString("target_id"))
                    assertEquals("1", receipt.getString("revision"))
                    assertNormalized(id, vector.getJSONObject("expected"))
                    committedId = id; committedExpected = vector.getJSONObject("expected"); committedReceipt = receipt
                }
                val discarded = call("discard", JSONObject().put("plan_id", plan.getString("plan_id")))
                assertEquals("$label dispose reviewed plan: $discarded", "ok", discarded.getString("status"))
                if (!vector.optBoolean("confirm")) assertMissing(id, "$label discard must not publish")
            }
            assertEquals("only the explicit eight-field case confirms", 1, confirmations)
            instrumentation.runOnMainSync { client.close() }
            connect()
            val reopenedHealth = call("health")
            assertEquals(reopenedHealth.toString(), "ok", reopenedHealth.getString("status"))
            assertNotEquals("sole-client Service close/reopen must establish a fresh owner", originalEpoch,
                reopenedHealth.getJSONObject("data").getString("epoch"))
            assertNormalized(requireNotNull(committedId), requireNotNull(committedExpected))
            val receipt = requireNotNull(committedReceipt)
            val recovered = call("lookup", JSONObject().put("intent_id", receipt.getString("intent_id")))
            assertEquals(recovered.toString(), "ok", recovered.getString("status"))
            assertEquals("committed", recovered.getJSONObject("data").getString("status"))
            assertEquals("same original durable receipt after reopen", receipt.toString(), recovered.getJSONObject("data").getJSONObject("receipt").toString())
        } finally { if (::client.isInitialized) instrumentation.runOnMainSync { client.close() } }
    }

    private fun materialize(fixture: JSONObject, vector: JSONObject): JSONObject {
        val payload = JSONObject(fixture.getJSONObject("base_payload").toString())
        vector.optJSONObject("patch")?.let { patch -> patch.keys().forEach { key -> payload.put(key, patch.get(key)) } }
        vector.optJSONObject("repeat")?.let { specification ->
            val unit = specification.getString("unit")
            val count = specification.getInt("count")
            payload.put(specification.getString("field"), if (specification.getBoolean("array")) JSONArray().apply {
                repeat(count) { put(unit) }
            } else unit.repeat(count) + specification.getString("suffix"))
        }
        return payload
    }
    private fun assertNormalized(id: String, expected: JSONObject) {
        val reply = call("supplier", JSONObject().put("id", id))
        assertEquals(reply.toString(), "ok", reply.getString("status"))
        val row = reply.getJSONObject("data")
        assertEquals(id, row.getString("id"))
        assertEquals("1", row.getString("revision"))
        val actual = row.getJSONObject("payload")
        assertEquals(expected.keys().asSequence().toSet(), actual.keys().asSequence().toSet())
        assertEquals(8, actual.length())
        expected.keys().forEach { field -> assertEquals("normalized eight-field value: $field", expected.get(field).toString(), actual.get(field).toString()) }
    }
    private fun assertMissing(id: String, label: String) {
        val result = call("supplier", JSONObject().put("id", id))
        assertNotEquals("$label must not publish $id", "ok", result.getString("status"))
        assertEquals("$label requires precise NotFound, not transport/storage failure", "NotFound", result.getString("error"))
    }
    private fun connect() {
        val connected = CountDownLatch(1)
        instrumentation.runOnMainSync {
            client = ProductClient(context) { if (it) connected.countDown() }
            client.bind()
        }
        assertTrue("real service connection", connected.await(15, TimeUnit.SECONDS))
    }
    private fun call(method: String, payload: JSONObject = JSONObject()): JSONObject {
        val completed = CountDownLatch(1)
        var response: JSONObject? = null
        instrumentation.runOnMainSync { client.call(method, payload) { response = it; completed.countDown() } }
        assertTrue("real $method result", completed.await(35, TimeUnit.SECONDS))
        return requireNotNull(response)
    }
}
