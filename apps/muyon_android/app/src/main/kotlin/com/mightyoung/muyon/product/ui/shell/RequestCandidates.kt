package com.mightyoung.muyon.product.ui.shell

import org.json.JSONArray
import org.json.JSONObject
import java.math.BigDecimal

data class RequestCandidate(val snapshot: ReadOnlySnapshot, val configurationId: String?)

/** Finite read-only candidate, with no invented typed-card binding or action identity. */
fun decodeRequestCandidate(data: JSONObject, workspace: String, conversation: String,
    project: String?, generation: Long, request: String): RequestCandidate? {
    val schema = data.opt("schema_version")
    if ((schema !is Int && schema !is Long) || (schema as Number).toLong() != 1L ||
        data.opt("status") != "read_only" || data.opt("projection_type") != "card_candidates") return null
    val source = data.optJSONObject("request_snapshot") ?: return null
    val snapshot = decodeReadOnlySnapshot(source, workspace, conversation, project, generation, request) ?: return null
    val candidates = data.optJSONArray("candidates") ?: return null
    if (candidates.length() != 1) return null // schema1 publishes one finite request observation
    val candidate = candidates.optJSONObject(0) ?: return null
    if (candidate.opt("kind") != "request_observation" || candidate.opt("request_id") != request ||
        candidate.opt("request_conversation_id") != snapshot.requestConversation ||
        !candidate.has("binding") || !candidate.isNull("binding") || candidate.opt("can_execute") != false ||
        candidate.opt("can_cancel") != false || candidate.opt("disabled_reason") != "trusted_card_binding_unavailable") return null
    val reads = candidate.optJSONArray("supported_local_reads") ?: return null
    if (reads.length() != 1 || reads.opt(0) != "query_original" ||
        !jsonStructurallyEqual(candidate.optJSONObject("observation"), source.optJSONObject("observation"))) return null
    if (!candidate.has("configuration_id")) return null
    val configuration = if (candidate.isNull("configuration_id")) null else
        (candidate.opt("configuration_id") as? String)?.takeIf { it.isNotBlank() && it.length <= 256 && '\u0000' !in it } ?: return null
    return RequestCandidate(snapshot, configuration)
}

/**
 * Strict structural JSON equality. Android's org.json has no JSONObject.similar (a json.org-only
 * method), so compare explicitly: same key set, same types, same values; a missing side never matches.
 */
internal fun jsonStructurallyEqual(left: Any?, right: Any?): Boolean {
    if (left == null || right == null) return false
    return when {
        left is JSONObject && right is JSONObject -> {
            val keys = left.keys().asSequence().toSet()
            keys == right.keys().asSequence().toSet() &&
                keys.all { key -> jsonValuesEqual(left.opt(key), right.opt(key)) }
        }
        else -> jsonValuesEqual(left, right)
    }
}

private fun jsonValuesEqual(left: Any?, right: Any?): Boolean = when {
    left is JSONObject && right is JSONObject -> jsonStructurallyEqual(left, right)
    left is JSONArray && right is JSONArray -> left.length() == right.length() &&
        (0 until left.length()).all { jsonValuesEqual(left.opt(it), right.opt(it)) }
    left is Number && right is Number -> BigDecimal(left.toString()).compareTo(BigDecimal(right.toString())) == 0
    left == JSONObject.NULL && right == JSONObject.NULL -> true
    left is JSONObject || right is JSONObject || left is JSONArray || right is JSONArray -> false
    else -> left == right
}
