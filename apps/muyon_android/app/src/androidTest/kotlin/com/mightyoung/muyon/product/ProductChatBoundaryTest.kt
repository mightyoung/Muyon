package com.mightyoung.muyon.product

import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.product.agentipc.ProductClient
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Real Service/native budget owner. No pricing verifier, socket or real key. */
class ProductChatBoundaryTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private lateinit var client: ProductClient
    private fun call(method: String, payload: JSONObject = JSONObject()): JSONObject {
        val done=CountDownLatch(1)
        var result:JSONObject?=null
        instrumentation.runOnMainSync { client.call(method,payload) { result=it;done.countDown() } }
        assertTrue("real $method response",done.await(35,TimeUnit.SECONDS))
        val reply=requireNotNull(result)
        assertEquals(reply.toString(),"ok",reply.getString("status"))
        return reply.getJSONObject("data")
    }
    @Test fun explicitConfigurationCannotTurnMissingPriceProofIntoOutboundAuthority() {
        val ready=CountDownLatch(1)
        instrumentation.runOnMainSync { client=ProductClient(instrumentation.targetContext) { if(it)ready.countDown() };client.bind() }
        assertTrue(ready.await(15,TimeUnit.SECONDS))
        try {
            call(if(File(instrumentation.targetContext.filesDir,"muyon-product-v2/business-v2.sqlite").isFile)"health" else "initialize")
            val key="fixture-not-a-real-key-0000".toCharArray()
            val configured=CountDownLatch(1)
            var result:JSONObject?=null
            instrumentation.runOnMainSync {
                client.configureChat(JSONObject().put("cap_micro_cny","50000").put("max_calls","2")
                    .put("chat",true).put("search",true),key) { result=it;configured.countDown() }
                assertTrue("caller credential buffer must be cleared",key.all { it=='\u0000' })
            }
            assertTrue(configured.await(35,TimeUnit.SECONDS))
            val reply=requireNotNull(result)
            assertEquals(reply.toString(),"ok",reply.getString("status"))
            assertFalse(reply.toString().contains("fixture-not-a-real-key"))
            assertEquals("unavailable",reply.getJSONObject("data").getString("pricing_proof"))
            call("chat_scope")
            for(search in listOf(false,true)) {
                val plan=call("chat_prepare",JSONObject().put("conversation_id",UUID.randomUUID().toString())
                    .put("text","你好，请简短介绍一下。").put("search",search).put("count",5).put("project_id",JSONObject.NULL))
                assertFalse(plan.getBoolean("send_allowed"))
                assertEquals("0",plan.getString("reserved_micro_cny"))
                val blocked=call("chat_confirm",JSONObject().put("request_id",plan.getString("request_id")))
                assertEquals("unavailable",blocked.getString("status"))
                val observation=call("chat_lookup",JSONObject().put("request_id",plan.getString("request_id")))
                assertEquals("0",observation.getString("reserved_micro_cny"))
                call("chat_cancel",JSONObject().put("request_id",plan.getString("request_id")))
            }
            val budget=call("chat_budget")
            assertEquals("0",budget.getString("held_micro_cny"))
            assertEquals("0",budget.getString("charged_micro_cny"))
            assertEquals("0",budget.getString("used_calls"))
        } finally { instrumentation.runOnMainSync { client.close() } }
    }
}
