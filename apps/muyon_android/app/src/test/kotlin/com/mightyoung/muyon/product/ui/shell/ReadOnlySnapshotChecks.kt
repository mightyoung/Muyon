package com.mightyoung.muyon.product.ui.shell

import org.json.JSONArray
import org.json.JSONObject

fun main() {
    fun fixture() = JSONObject().put("schema_version", 1).put("status", "read_only")
        .put("scope", JSONObject().put("workspace_id", "w").put("conversation_id", "c")
            .put("project_id", "p").put("generation", 7).put("agent_id", JSONObject.NULL))
        .put("original_request", JSONObject().put("request_id", "r").put("request_conversation_id", "native-child").put("intent_id", JSONObject.NULL))
        .put("observation", JSONObject().put("status", "unknown").put("execution_status", "unknown")
            .put("reserved_micro_cny", "2620").put("charged_micro_cny", JSONObject.NULL)
            .put("cancellation_status", "intent_recorded_outcome_unknown"))
        .put("binding", JSONObject.NULL).put("capabilities", JSONArray())
    fun decode(data: JSONObject) = decodeReadOnlySnapshot(data, "w", "c", "p", 7, "r")
    val valid = checkNotNull(decode(fixture())) { "valid original scoped snapshot must remain visible" }
    check(valid.requestConversation == "native-child" && valid.requestId == "r")
    check(valid.reservedMicroCny == "2620" && valid.chargedMicroCny == null)
    check(valid.nativeStatus == "unknown" && valid.executionStatus == "unknown")
    check(valid.cancellationStatus == "intent_recorded_outcome_unknown")
    for ((key, value) in listOf("workspace_id" to "other", "conversation_id" to "other", "project_id" to "other", "generation" to 8)) {
        val wrong = fixture(); wrong.getJSONObject("scope").put(key, value)
        check(decode(wrong) == null) { "mismatched $key must fail closed" }
    }
    check(decode(fixture().apply { getJSONObject("original_request").put("request_id", "other") }) == null)
    check(decode(fixture().put("binding", JSONObject())) == null)
    check(decode(fixture().put("capabilities", JSONArray().put("cancel"))) == null)
    check(decode(fixture().apply { getJSONObject("scope").put("generation", "7") }) == null)
    check(decode(fixture().put("schema_version", 1.0)) == null)
    check(decode(fixture().put("status", "unavailable")) == null)
    check(decode(fixture().apply { getJSONObject("original_request").put("intent_id", "fabricated") }) == null)
    val pending = checkNotNull(decode(fixture().apply {
        getJSONObject("observation").put("status", "pending").put("execution_status", "unavailable")
    }))
    check(pending.executionStatus == "unavailable")
    check(decode(fixture().apply { getJSONObject("observation").put("execution_status", "completed") }) == null)
    val unknownCosts = checkNotNull(decode(fixture().apply {
        getJSONObject("observation").put("reserved_micro_cny", 0).put("charged_micro_cny", "18446744073709551616")
    }))
    check(unknownCosts.reservedMicroCny == null && unknownCosts.chargedMicroCny == null)
    val maximum = checkNotNull(decode(fixture().apply {
        getJSONObject("observation").put("reserved_micro_cny", "18446744073709551615").put("charged_micro_cny", "0")
    }))
    check(maximum.reservedMicroCny == "18446744073709551615" && maximum.chargedMicroCny == null) // unknown ledger0 is not known actual charge
    val completed = fixture().apply {
        getJSONObject("observation").put("status", "completed").put("execution_status", "completed")
            .put("attempted", true).put("charged_micro_cny", "42")
    }
    check(decode(completed)?.chargedMicroCny == "42")
    completed.getJSONObject("observation").put("attempted", "true")
    check(decode(completed)?.chargedMicroCny == null)
    val unknownPositive = fixture().apply { getJSONObject("observation").put("charged_micro_cny", "99") }
    check(decode(unknownPositive)?.chargedMicroCny == null)
    val absent = checkNotNull(decode(fixture().apply {
        getJSONObject("observation").put("status", JSONObject.NULL).put("execution_status", "unavailable")
    }))
    check(absent.nativeStatus == null)
    println("PASS shell read-only snapshot: exact scope/request, child identity, null/unsigned costs, unavailable binding, status coherence; no client/network code")
}
