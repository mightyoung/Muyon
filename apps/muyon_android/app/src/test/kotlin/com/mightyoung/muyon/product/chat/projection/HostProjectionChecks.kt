package com.mightyoung.muyon.product.chat

import org.json.JSONObject
import java.lang.reflect.Proxy
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Real runtime + fake private local port; transport throws if ever reached. */
fun main() {
    var lookups = 0
    var writes = 0
    var next = 0
    var observation = JSONObject()
    var mismatch = false
    var omitConversation = false
    val port = Proxy.newProxyInstance(ProductChatPort::class.java.classLoader, arrayOf(ProductChatPort::class.java)) { _, method, args ->
        when (method.name) {
            "configure" -> JSONObject().put("id", "config")
            "prepareScoped" -> JSONObject().put("request_id", "request-${++next}").put("conversation_id", if (omitConversation) JSONObject.NULL else args!![0])
            "workflowPrepare" -> JSONObject().put("request_id", "request-${++next}").put("conversation_id", "native-child")
            "followup" -> JSONObject().put("request_id", "request-${++next}").put("conversation_id", "native-followup")
            "bindScope" -> null
            "lookup" -> { lookups++; JSONObject(observation.toString()).put("request_id", if (mismatch) "wrong-original" else args!![0]) }
            "cancel", "discardBusinessPlan" -> { writes++; JSONObject() }
            "failureCode" -> null
            else -> error("unexpected port: ${method.name}")
        }
    } as ProductChatPort
    val runtime = ProductChatRuntime(port, ProductChatExchange { _, _, _, _, _ -> error("NETWORK FORBIDDEN") })
    fun call(block: ((JSONObject) -> Unit) -> Unit): JSONObject {
        val done = CountDownLatch(1)
        var result: JSONObject? = null
        block { result = it; done.countDown() }
        check(done.await(5, TimeUnit.SECONDS)) { "callback missing" }
        return checkNotNull(result)
    }
    fun scope(session: String, project: String?) = call { runtime.updateScope(session, project, it) }.getLong("scope_generation")
    fun snapshot(session: String, conversation: String, request: String, project: String?, generation: Long) =
        call { runtime.readSnapshot(session, "workspace", conversation, request, project, generation, it) }
    fun denied(result: JSONObject) { check(result.getString("status") == "unavailable"); check(!result.has("observation")) }
    try {
        val generation = scope("session", "project")
        denied(snapshot("session", "conversation", "absent", "project", generation))
        check(lookups == 0 && writes == 0)
        call { runtime.configure("session", CharArray(20) { 'x' }, "0", "0", true, true, it) }
        val request = call { runtime.prepare("session", "conversation", "fixture", false, 1, "project", it) }.getString("request_id")
        observation = JSONObject().put("status", "unknown").put("reserved_micro_cny", "2620")
            .put("charged_micro_cny", JSONObject.NULL).put("cancelled", true).put("attempted", true)
            .put("answer", JSONObject().put("command", "untrusted"))
        val result = snapshot("session", "conversation", request, "project", generation)
        check(result.getString("status") == "read_only")
        check(result.isNull("binding") && result.getJSONArray("capabilities").length() == 0)
        check(result.getJSONObject("original_request").getString("request_id") == request)
        check(result.getJSONObject("original_request").isNull("intent_id"))
        check(result.getJSONObject("scope").getLong("generation") == generation)
        check(result.getJSONObject("scope").isNull("agent_id"))
        val fact = result.getJSONObject("observation")
        check(fact.getString("status") == "unknown")
        check(fact.getString("reserved_micro_cny") == "2620" && fact.isNull("charged_micro_cny"))
        check(fact.isNull("current_business_state") && !fact.has("answer"))
        check(fact.getString("cancellation_status") == "intent_recorded_outcome_unknown")
        check(result.getJSONArray("unavailable").toString().contains("state_revision"))
        // Native requests.charged defaults to 0 before a validated settlement.
        observation = JSONObject().put("status", "unknown").put("attempted", true)
            .put("reserved_micro_cny", "2620").put("charged_micro_cny", "0")
        val nativeUnknown = snapshot("session", "conversation", request, "project", generation).getJSONObject("observation")
        check(nativeUnknown.isNull("charged_micro_cny")) { "native unknown ledger zero is not actual cost proof" }
        check(nativeUnknown.getString("reserved_micro_cny") == "2620")
        listOf("prepared", "reserved", "pending", "tool_pending", "tool_consumed", "failed", "cancelled").forEach { status ->
            observation = JSONObject().put("status", status).put("attempted", true).put("charged_micro_cny", "0")
            check(snapshot("session", "conversation", request, "project", generation).getJSONObject("observation").isNull("charged_micro_cny")) {
                "$status has no exposed terminal settlement proof"
            }
        }
        observation = JSONObject().put("status", "unknown").put("attempted", true).put("charged_micro_cny", "66")
        check(snapshot("session", "conversation", request, "project", generation).getJSONObject("observation").isNull("charged_micro_cny"))
        listOf(false, JSONObject.NULL, "true").forEach { attempted ->
            observation = JSONObject().put("status", "completed").put("attempted", attempted).put("charged_micro_cny", "0")
            check(snapshot("session", "conversation", request, "project", generation).getJSONObject("observation").isNull("charged_micro_cny"))
        }
        observation = JSONObject().put("status", "completed").put("attempted", true).put("charged_micro_cny", "0")
        check(snapshot("session", "conversation", request, "project", generation).getJSONObject("observation").getString("charged_micro_cny") == "0")
        val before = lookups
        val other = scope("other", "project")
        denied(snapshot("other", "conversation", request, "project", other))
        denied(snapshot("session", "other-conversation", request, "project", generation))
        denied(snapshot("session", "conversation", request, "other-project", generation))
        denied(snapshot("session", "conversation", request, "project", generation + 1))
        check(lookups == before)
        mismatch = true
        denied(snapshot("session", "conversation", request, "project", generation))
        mismatch = false
        observation = JSONObject()
        val empty = snapshot("session", "conversation", request, "project", generation).getJSONObject("observation")
        check(empty.isNull("status") && empty.isNull("attempted") && empty.isNull("cancelled"))
        check(empty.isNull("reserved_micro_cny") && empty.isNull("charged_micro_cny"))
        observation = JSONObject().put("status", "unknown").put("reserved_micro_cny", "18446744073709551616")
            .put("charged_micro_cny", 0)
        val malformed = snapshot("session", "conversation", request, "project", generation).getJSONObject("observation")
        check(malformed.isNull("reserved_micro_cny") && malformed.isNull("charged_micro_cny"))
        observation = JSONObject().put("status", "pending")
        val pending = snapshot("session", "conversation", request, "project", generation).getJSONObject("observation")
        check(pending.getString("status") == "pending" && pending.getString("execution_status") == "unavailable")
        check(pending.isNull("reserved_micro_cny") && pending.isNull("charged_micro_cny"))
        observation = JSONObject().put("status", "tool_consumed")
        val consumed = snapshot("session", "conversation", request, "project", generation).getJSONObject("observation")
        check(consumed.getString("status") == "tool_consumed" && consumed.getString("execution_status") == "unavailable")
        observation = JSONObject().put("status", "completed").put("attempted", true).put("charged_micro_cny", "66")
        val completed = snapshot("session", "conversation", request, "project", generation).getJSONObject("observation")
        check(completed.getString("execution_status") == "completed")
        check(completed.isNull("current_business_state"))
        check(completed.getString("charged_micro_cny") == "66")
        // Detached output cannot mutate a subsequent observation or its host origin.
        result.getJSONObject("scope").put("conversation_id", "tampered")
        check(snapshot("session", "conversation", request, "project", generation).getJSONObject("scope").getString("conversation_id") == "conversation")
        omitConversation = true
        val incompleteRequest = call { runtime.prepare("session", "conversation", "fixture", true, 1, "project", it) }.getString("request_id")
        denied(snapshot("session", "conversation", incompleteRequest, "project", generation))
        omitConversation = false // missing projection facts cannot break prepare
        val searchRequest = call { runtime.prepare("session", "conversation", "fixture", true, 1, "project", it) }.getString("request_id")
        check(snapshot("session", "conversation", searchRequest, "project", generation).getString("status") == "read_only")
        val workflowRequest = call { runtime.workflowPrepare("session", "conversation", "fixture-run", it) }.getString("request_id")
        val workflow = snapshot("session", "conversation", workflowRequest, "project", generation)
        check(workflow.getJSONObject("scope").getString("conversation_id") == "conversation")
        check(workflow.getJSONObject("original_request").getString("request_conversation_id") == "native-child")
        val followupRequest = call { runtime.followup("session", workflowRequest, it) }.getString("request_id")
        val followup = snapshot("session", "conversation", followupRequest, "project", generation)
        check(followup.getJSONObject("scope").getString("conversation_id") == "conversation")
        check(followup.getJSONObject("original_request").getString("request_conversation_id") == "native-followup")
        check(writes == 0) // projection never calls a write port
        scope("session", "other-project"); scope("session", "project")
        val staleBefore = lookups
        denied(snapshot("session", "conversation", request, "project", generation))
        check(lookups == staleBefore)
        val currentGeneration = scope("session", "project")
        var first: String? = null
        var last = ""
        repeat(257) { index ->
            if (index % 80 == 0) call { runtime.configure("session", CharArray(20) { 'x' }, "0", "0", true, true, it) }
            last = call { runtime.prepare("session", "conversation", "fixture", true, 1, "project", it) }.getString("request_id")
            if (index == 0) first = last
        }
        // Cache capacity cannot become a new business prepare gate.
        denied(snapshot("session", "conversation", checkNotNull(first), "project", currentGeneration))
        check(snapshot("session", "conversation", last, "project", currentGeneration).getString("status") == "read_only")
        runtime.releaseSession("session")
        scope("session", "project") // drain release queue, then remount; old origin is gone
        denied(snapshot("session", "conversation", request, "project", generation))
        println("PASS host projection: scope/absent/unknown/pending/history/detachment/malformed/search/workflow/followup/release/cache capacity/actual charge proof checks")
    } finally { runtime.close(); check(runtime.awaitDrain(5000)) }
}
