package com.mightyoung.muyon.product.ui.shell

import org.json.JSONObject

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
        !sameRequestObservation(candidate.optJSONObject("observation"), source.optJSONObject("observation"))) return null
    if (!candidate.has("configuration_id")) return null
    val configuration = if (candidate.isNull("configuration_id")) null else
        (candidate.opt("configuration_id") as? String)?.takeIf { it.isNotBlank() && it.length <= 256 && '\u0000' !in it } ?: return null
    return RequestCandidate(snapshot, configuration)
}

/** Schema1 observations are finite flat JSON facts. Compare every key, including facts not displayed.
 * Only Android JSONObject APIs are used; missing differs from explicit NULL and scalar types stay exact.
 * Unexpected structured values fail closed rather than expanding this finite projection schema.
 */
internal fun sameRequestObservation(left: JSONObject?, right: JSONObject?): Boolean {
    if (left == null || right == null || left.length() > 64 || left.length() != right.length()) return false
    val keys = left.keys()
    while (keys.hasNext()) {
        val key = keys.next() as? String ?: return false
        if (!right.has(key)) return false
        val a = left.opt(key)
        val b = right.opt(key)
        if (a === JSONObject.NULL) {
            if (b !== JSONObject.NULL) return false
        } else {
            if (a !is String && a !is Boolean && a !is Int && a !is Long && a !is Double) return false
            if (b == null || a.javaClass != b.javaClass || a != b) return false
        }
    }
    return true
}
