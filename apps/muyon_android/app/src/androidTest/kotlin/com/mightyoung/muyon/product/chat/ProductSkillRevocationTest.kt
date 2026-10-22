package com.mightyoung.muyon.product.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.lang.reflect.Proxy
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Real serialized runtime; no dispatcher, sockets, credentials or provider. */
class ProductSkillRevocationTest {
    private fun await(action: ((JSONObject) -> Unit) -> Unit): JSONObject {
        val latch = CountDownLatch(1)
        var reply: JSONObject? = null
        action { reply = it; latch.countDown() }
        check(latch.await(10, TimeUnit.SECONDS))
        return requireNotNull(reply)
    }

    @Test fun revocationClosesOtherSessionsInTheSameScopeBeforeMutationWithoutTouchingOtherConversations() {
        val cancelled = mutableSetOf<String>()
        val port = Proxy.newProxyInstance(ProductChatPort::class.java.classLoader,
            arrayOf(ProductChatPort::class.java)) { _, method, args ->
            when (method.name) {
                "configure" -> JSONObject().put("id", "config")
                "workflowPrepare" -> JSONObject().put("request_id", args!![0] as String)
                    .put("configuration_id", "config").put("skill_id", "supplier-overview").put("send_allowed", false)
                "cancel" -> { cancelled.add(args!![0] as String); JSONObject().put("status", "cancelled") }
                "workflow" -> {
                    assertEquals(setOf("same-a", "same-b"), cancelled)
                    JSONObject().put("remote_request_ids", JSONArray(listOf("same-a", "same-b")))
                }
                else -> error("Unexpected port: ${method.name}")
            }
        } as ProductChatPort
        val runtime = ProductChatRuntime(port)
        try {
            await { runtime.configure("a", "fixture-not-a-real-key".toCharArray(), "1000000", "10", true, false, it) }
            await { runtime.updateScope("a", null, it) }; await { runtime.updateScope("b", null, it) }
            await { runtime.workflowPrepare("a", "same", "same-a", it) }
            await { runtime.workflowPrepare("b", "same", "same-b", it) }
            await { runtime.workflowPrepare("a", "other", "other-a", it) }
            val result = await { runtime.workflow("a", "same", JSONObject().put("action", "set_skill")
                .put("skill_id", "supplier-overview").put("enabled", false), it) }
            assertFalse(result.has("error"))
            assertEquals(setOf("same-a", "same-b"), cancelled)
        } finally { runtime.close(); assertTrue(runtime.awaitDrain(10_000)) }
    }
}
