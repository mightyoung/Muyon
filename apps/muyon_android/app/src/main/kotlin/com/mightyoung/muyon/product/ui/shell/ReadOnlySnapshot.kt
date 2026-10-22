package com.mightyoung.muyon.product.ui.shell

import org.json.JSONObject

data class ReadOnlySnapshot(
    val requestId: String, val requestConversation: String,
    val nativeStatus: String?, val executionStatus: String,
    val reservedMicroCny: String?, val chargedMicroCny: String?, val cancellationStatus: String,
    val settlementObserved: Boolean = false,
)

/** Display facts only. Never constructs a CardBinding, revision, intent or action capability. */
fun decodeReadOnlySnapshot(data: JSONObject, workspace: String, conversation: String,
    project: String?, generation: Long, request: String): ReadOnlySnapshot? {
    if (generation < 0 || conversation.isBlank() || request.isBlank()) return null
    fun integer(value: Any?): Long? = when (value) { is Int -> value.toLong(); is Long -> value; else -> null }
    if (integer(data.opt("schema_version")) != 1L || data.opt("status") != "read_only" ||
        !data.has("binding") || !data.isNull("binding") || data.optJSONArray("capabilities")?.length() != 0) return null
    val scope = data.optJSONObject("scope") ?: return null
    if (workspace.isBlank() || scope.opt("workspace_id") != workspace || scope.opt("conversation_id") != conversation ||
        !scope.has("project_id") || (if (scope.isNull("project_id")) null else scope.opt("project_id")) != project ||
        integer(scope.opt("generation")) != generation || !scope.has("agent_id") || !scope.isNull("agent_id")) return null
    val original = data.optJSONObject("original_request") ?: return null
    if (original.opt("request_id") != request || !original.has("intent_id") || !original.isNull("intent_id")) return null
    val child = (original.opt("request_conversation_id") as? String)?.takeIf { it.isNotBlank() } ?: return null
    val fact = data.optJSONObject("observation") ?: return null
    val status = if (fact.has("status") && fact.isNull("status")) null else (fact.opt("status") as? String) ?: return null
    if (status != null && status !in setOf("prepared", "reserved", "unknown", "tool_pending", "tool_consumed", "completed", "failed", "cancelled", "pending")) return null
    val execution = fact.opt("execution_status") as? String ?: return null
    val expectedExecution = when (status) { "completed", "failed", "cancelled", "unknown" -> status; else -> "unavailable" }
    if (execution != expectedExecution) return null
    fun cost(key: String): String? = (fact.opt(key) as? String)?.takeIf {
        it.length <= 20 && it.matches(Regex("0|[1-9][0-9]*")) && it.toULongOrNull() != null
    }
    val cancellation = fact.opt("cancellation_status") as? String ?: return null
    if (cancellation !in setOf("confirmed_cancelled", "intent_recorded_outcome_unknown", "unavailable") ||
        (cancellation == "confirmed_cancelled" && status != "cancelled")) return null
    // Unknown/native ledger default zero is not proof of an actual settlement.
    val settled = status == "completed" && fact.opt("attempted") == true
    return ReadOnlySnapshot(request, child, status, execution, cost("reserved_micro_cny"),
        if (settled) cost("charged_micro_cny") else null, cancellation, settled)
}
