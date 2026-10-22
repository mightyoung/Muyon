package com.mightyoung.muyon.product

import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.product.agentipc.ProductClient
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class ContractCodecProductTest {
    private val instrumentation=InstrumentationRegistry.getInstrumentation()
    private lateinit var client:ProductClient
    @Before fun connect() {
        bindClient()
        val reply=call(if(File(instrumentation.targetContext.filesDir,"muyon-product-v2/business-v2.sqlite").isFile)"health" else "initialize")
        assertEquals(reply.toString(),"ok",reply.getString("status"))
    }
    private fun bindClient() {
        val ready=CountDownLatch(1)
        instrumentation.runOnMainSync { client=ProductClient(instrumentation.targetContext) { if(it)ready.countDown() };client.bind() }
        assertTrue(ready.await(15,TimeUnit.SECONDS))
    }
    @After fun close() { if(::client.isInitialized) instrumentation.runOnMainSync { client.close() } }
    private fun call(method:String,payload:JSONObject=JSONObject()):JSONObject {
        val ready=CountDownLatch(1); var result:JSONObject?=null
        instrumentation.runOnMainSync { client.call(method,payload) { result=it;ready.countDown() } }
        assertTrue("$method response",ready.await(35,TimeUnit.SECONDS))
        return requireNotNull(result)
    }
    private fun operation(id:String,name:String)=JSONObject().put("operation","supplier_create").put("supplier_id",id)
        .put("payload",JSONObject().put("name",name).put("aliases",JSONArray()).put("categories",JSONArray()))
    @Test fun malformedUtf16AndRawLimitCannotTurnIntoAValidReviewedPlan() {
        val before = call("health").getJSONObject("data")
        val pid = before.getInt("service_pid")
        for(name in listOf("\uD800","\uDC00","bad\u0000name"," ".repeat(2001)+"A")) {
            val reply=call("prepare",JSONObject().put("operation",operation(UUID.randomUUID().toString(),name)).put("expected_revision","0"))
            assertNotEquals("malformed/raw-limit input must be rejected before review", "ok",reply.getString("status"))
            assertFalse(reply.optJSONObject("data")?.has("plan_id")==true)
        }
        // Rejection alone is insufficient: a failed Kotlin lowering must not
        // retain an extra native owner handle and prevent the next Service.
        instrumentation.runOnMainSync { client.close() }
        val deadline = android.os.SystemClock.elapsedRealtime() + 10_000
        var reopened: JSONObject? = null
        do {
            bindClient()
            val health = call("health")
            val data = health.optJSONObject("data")
            if (health.optString("status") == "ok" && data?.optString("epoch") != before.getString("epoch")) {
                reopened = data
                break
            }
            assertTrue("only owner drain or old-instance reuse may be awaited: $health",
                health.optString("status") == "ok" || health.optString("error") == "InvalidAuthority")
            instrumentation.runOnMainSync { client.close() }
            // Await a specific lifecycle condition; no business call is retried.
            android.os.SystemClock.sleep(20)
        } while (android.os.SystemClock.elapsedRealtime() < deadline)
        assertNotNull("old Service must retire and its native owner lock must release", reopened)
        assertEquals("reopen must be proved without a process death hiding a leaked handle", pid,
            reopened!!.getInt("service_pid"))
        assertNotEquals(before.getString("epoch"), reopened.getString("epoch"))
    }
    @Test fun actualKotlinToRustCodecPreservesPairsAndUsesTheSameNfcRule() {
        val id=UUID.randomUUID().toString()
        val plan=call("prepare",JSONObject().put("operation",operation(id,"\uFEFF e\u0301 🧪  ")).put("expected_revision","0")).getJSONObject("data")
        val receipt=call("confirm",JSONObject().put("plan_id",plan.getString("plan_id"))).getJSONObject("data")
        assertEquals("committed",receipt.getString("status"))
        assertEquals(plan.getString("intent_id"),receipt.getJSONObject("receipt").getString("intent_id"))
        val record=call("supplier",JSONObject().put("id",id)).getJSONObject("data")
        assertEquals("é 🧪",record.getJSONObject("payload").getString("name"))
        assertEquals("1",record.getString("revision"))
    }
}
