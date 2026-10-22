package com.mightyoung.muyon.product.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.lang.reflect.Proxy
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

class CompleteResponseSettlementTest {
    @Test fun cancellationAtFinalFramedByteStillReturnsCompleteResponseForSettlement() {
        val body = "{\"answer\":\"complete fixture\"}"
        val framed = ("HTTP/1.1 200 OK\r\nContent-Length: ${body.toByteArray().size}\r\n\r\n" + body).toByteArray()
        val permitted = AtomicBoolean(true)
        val input = object : java.io.ByteArrayInputStream(framed) {
            override fun read(): Int = super.read().also { if (pos == count) permitted.set(false) }
            override fun read(b: ByteArray, off: Int, len: Int): Int = super.read(b, off, len).also {
                if (pos == count) permitted.set(false)
            }
        }
        val output = java.io.ByteArrayOutputStream()
        val result = ProductHttpsTransport.exchangeConnected(input, output, "{}".toByteArray(),
            "fixture-no-real-key-17".toCharArray(), { permitted.get() }, { write -> write(); true })
        assertFalse(permitted.get())
        assertEquals(body, result.toString(Charsets.UTF_8))
        assertTrue(output.size() > 0)
    }
    private fun await(action: ((JSONObject) -> Unit) -> Unit): JSONObject {
        val latch = CountDownLatch(1)
        var result: JSONObject? = null
        action { result = it; latch.countDown() }
        assertTrue(latch.await(10, TimeUnit.SECONDS))
        return requireNotNull(result)
    }
    @Test fun completeResponseSettlesOriginalAfterCancelScopeChangeOrCloseWithoutAnotherWrite() {
        for (stop in listOf("cancel", "scope", "close")) {
            val wrote = CountDownLatch(1); val deliver = CountDownLatch(1); val settled = CountDownLatch(1)
            val cancelled = AtomicBoolean(false); val writes = AtomicInteger(); val settlements = AtomicInteger()
            val port = Proxy.newProxyInstance(ProductChatPort::class.java.classLoader,
                arrayOf(ProductChatPort::class.java)) { _, method, args -> when (method.name) {
                    "configure" -> JSONObject().put("id", "config")
                    "prepareScoped" -> JSONObject().put("request_id", "original").put("configuration_id", "config").put("send_allowed", true)
                    "bindScope" -> null
                    "confirm" -> JSONObject().put("status", "reserved")
                    "claim" -> JSONObject().put("purpose", "chat").put("payload", "{}")
                    "allowed" -> !cancelled.get()
                    "cancel" -> { cancelled.set(true); JSONObject().put("status", "unknown") }
                    "settle" -> {
                        assertEquals("original", args!![0]); assertEquals("complete fixture", JSONObject(args[1] as String).getString("answer"))
                        settlements.incrementAndGet(); settled.countDown()
                        JSONObject().put("status", if (cancelled.get()) "cancelled" else "completed").put("charged_micro_cny", "66")
                    }
                    "diagnostic" -> null
                    else -> error("Unexpected local fixture port: ${method.name}")
                } } as ProductChatPort
            val exchange = ProductChatExchange { _, _, _, allowed, authorize ->
                assertTrue(allowed()); assertTrue(authorize { writes.incrementAndGet() }); wrote.countDown()
                assertTrue(deliver.await(10, TimeUnit.SECONDS))
                "{\"answer\":\"complete fixture\"}".toByteArray()
            }
            val runtime = ProductChatRuntime(port, exchange)
            try {
                await { runtime.configure("session", "fixture-no-real-key-17".toCharArray(), "50000", "1", true, false, it) }
                await { runtime.updateScope("session", null, it) }
                await { runtime.prepare("session", "conversation", "text", false, 1, null, it) }
                await { runtime.confirm("session", "original", it) }
                assertTrue(wrote.await(10, TimeUnit.SECONDS))
                when (stop) {
                    "cancel" -> await { runtime.cancel("session", "original", it) }
                    "scope" -> await { runtime.updateScope("session", "other-project", it) }
                    else -> runtime.close()
                }
                deliver.countDown()
                assertTrue("Complete response lost after $stop", settled.await(10, TimeUnit.SECONDS))
                assertEquals(1, writes.get()); assertEquals(1, settlements.get())
            } finally { deliver.countDown(); runtime.close(); assertTrue(runtime.awaitDrain(10_000)) }
        }
    }
}
