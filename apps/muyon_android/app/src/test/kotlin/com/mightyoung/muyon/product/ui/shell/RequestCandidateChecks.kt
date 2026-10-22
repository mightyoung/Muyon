package com.mightyoung.muyon.product.ui.shell

import com.mightyoung.muyon.product.chat.*
import org.json.JSONObject
import java.lang.reflect.Proxy
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

fun main() {
    var prepares = 0
    val port = Proxy.newProxyInstance(ProductChatPort::class.java.classLoader, arrayOf(ProductChatPort::class.java)) { _, method, args ->
        when (method.name) {
            "configure" -> JSONObject().put("id", "offline-test-only")
            "prepareScoped" -> JSONObject().put("request_id", "r-${++prepares}").put("conversation_id", args!![0]).put("configuration_id", "cfg-$prepares")
            "bindScope" -> null
            "lookup" -> JSONObject().put("status", "unknown").put("charged_micro_cny", "0").put("reserved_micro_cny", "2620").put("request_id", args!![0])
            else -> error("unexpected native ${method.name}")
        }
    } as ProductChatPort
    val runtime = ProductChatRuntime(port, ProductChatExchange { _, _, _, _, _ -> error("NETWORK FORBIDDEN") })
    fun call(block: ((JSONObject) -> Unit) -> Unit): JSONObject {
        val done = CountDownLatch(1); var result: JSONObject? = null
        block { result = it; done.countDown() }; check(done.await(5, TimeUnit.SECONDS)); return checkNotNull(result)
    }
    try {
        val gen = call { runtime.updateScope("s", "p", it) }.getLong("scope_generation")
        call { runtime.configure("s", CharArray(20) { 'x' }, "0", "0", true, true, it) } // private fake port only
        val request = call { runtime.prepare("s", "c", "offline fixture", false, 1, "p", it) }.getString("request_id")
        fun source() = call { runtime.cardCandidates("s", "w", "c", request, "p", gen, it) }
        fun decode(value: JSONObject) = decodeRequestCandidate(value, "w", "c", "p", gen, request)
        val valid = checkNotNull(decode(source())) { "real host candidate must decode" }
        check(valid.configurationId == "cfg-1" && valid.snapshot.chargedMicroCny == null)
        check(valid.snapshot.reservedMicroCny == "2620")
        call { runtime.prepare("s", "c", "later offline fixture", false, 1, "p", it) }
        check(decode(source()) == valid) // later request never replaces original identity/config
        fun changed(change: (JSONObject) -> Unit): JSONObject = source().apply { change(getJSONArray("candidates").getJSONObject(0)) }
        check(decode(changed { it.put("request_id", "r-2") }) == null)
        check(decode(changed { it.put("request_conversation_id", "other") }) == null)
        check(decode(changed { it.put("binding", JSONObject()) }) == null)
        check(decode(changed { it.put("can_cancel", true) }) == null)
        check(decode(changed { it.put("can_execute", true) }) == null)
        check(decode(changed { it.put("kind", "task") }) == null)
        check(decode(changed { it.getJSONObject("observation").put("status", "completed") }) == null)
        for (key in listOf("cancelled", "attempted", "current_business_state")) {
            check(decode(changed { it.getJSONObject("observation").remove(key) }) == null)
            check(decode(changed { it.getJSONObject("observation").put(key, false) }) == null)
            check(decode(changed { it.getJSONObject("observation").put(key, "null") }) == null)
        }
        check(decode(changed { candidate ->
            val original = candidate.getJSONObject("observation")
            val reversed = JSONObject()
            val keys = mutableListOf<String>(); val iterator = original.keys()
            while (iterator.hasNext()) keys += checkNotNull(iterator.next() as? String)
            for (key in keys.reversed()) reversed.put(key, original.opt(key))
            candidate.put("observation", reversed)
        }) == valid)
        check(sameRequestObservation(JSONObject().put("n", 1), JSONObject().put("n", 1)))
        check(!sameRequestObservation(JSONObject().put("n", 1), JSONObject().put("n", 1.0)))
        check(!sameRequestObservation(JSONObject().put("n", false), JSONObject().put("n", "false")))
        check(!sameRequestObservation(JSONObject().put("n", JSONObject.NULL), JSONObject()))
        check(!sameRequestObservation(JSONObject(), JSONObject().put("n", JSONObject.NULL)))
        check(!sameRequestObservation(JSONObject().put("n", JSONObject()), JSONObject().put("n", JSONObject())))
        check(!sameRequestObservation(null, null))
        check(decodeRequestCandidate(source(), "w", "c", "p", gen + 1, request) == null)
        check(decode(source().put("projection_type", "unknown")) == null)
        println("PASS real host candidate: original request/config identity, exact scope, finite read-only kind, binding/actions absent, unknown charge remains unknown, mismatched duplicate observation rejects; no transport")
    } finally { runtime.close(); check(runtime.awaitDrain(5000)) }
}
