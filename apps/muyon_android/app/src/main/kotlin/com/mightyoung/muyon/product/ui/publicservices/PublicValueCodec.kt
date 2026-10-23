package com.mightyoung.muyon.product.ui.publicservices

import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

private const val U64_MAX = "18446744073709551615"
internal fun decimalAtMost(raw: String, maximum: String): Boolean = raw.isNotEmpty() &&
    raw.all { it in '0'..'9' } && (raw.length == 1 || raw[0] != '0') &&
    (raw.length < maximum.length || raw.length == maximum.length && raw <= maximum)
fun parseRevision(raw: String): String {
    require(decimalAtMost(raw, U64_MAX)) { "invalid revision" }; return raw
}
fun parseUnixMs(raw: String): String {
    val negative = raw.startsWith('-')
    val digits = if (negative) raw.substring(1) else raw
    require(decimalAtMost(digits, if (negative) "9223372036854775808" else "9223372036854775807") &&
        !(negative && digits == "0")) { "invalid UnixMs" }
    return raw
}
fun toLegacyRevision(raw: String): Long? = parseRevision(raw).let {
    if (decimalAtMost(it, "9223372036854775807")) it.toLong() else null
}
fun toPublicPageIndex(page: Int): Int { require(page > 0) { "invalid legacy page" }; return page - 1 }
internal fun validUnicode(raw: String): Boolean {
    var i = 0
    while (i < raw.length) {
        val c = raw[i++]
        if (c.isHighSurrogate()) {
            if (i == raw.length || !raw[i++].isLowSurrogate()) return false
        } else if (c.isLowSurrogate()) return false
    }
    return true
}
fun parsePublicId(raw: String): String {
    require(validUnicode(raw) && raw.isNotEmpty() && raw.toByteArray(Charsets.UTF_8).size <= 128 && '\u0000' !in raw) { "invalid public ID" }
    return raw
}
fun parsePublicDigest(raw: String): String {
    require(raw.length == 64 && raw.all { it in '0'..'9' || it in 'a'..'f' }) { "invalid digest" }; return raw
}

/** Bounded grammar check BEFORE org.json can coerce values or overwrite duplicate keys. */
internal fun strictObject(raw: String): JSONObject {
    require(validUnicode(raw) && raw.toByteArray(Charsets.UTF_8).size <= 1_048_576) { "invalid transport size/Unicode" }
    try { JsonGrammar(raw).check(); return JSONObject(raw) }
    catch (e: Exception) { throw IllegalArgumentException("invalid JSON", e) }
}
private class JsonGrammar(private val raw: String) {
    private var at = 0
    fun check() { value(0); space(); require(at == raw.length) }
    private fun space() { while (at < raw.length && raw[at] in " \r\n\t") at++ }
    private fun take(c: Char): Boolean { space(); return if (at < raw.length && raw[at] == c) { at++; true } else false }
    private fun value(depth: Int) {
        require(depth < 128); space(); require(at < raw.length)
        when (raw[at]) {
            '{' -> {
                at++; val keys = HashSet<String>()
                if (!take('}')) do {
                    space(); val key = string(); require(keys.add(key)); require(take(':')); value(depth + 1)
                    if (take('}')) break
                    require(take(','))
                } while (true)
            }
            '[' -> {
                at++
                if (!take(']')) do {
                    value(depth + 1)
                    if (take(']')) break
                    require(take(','))
                } while (true)
            }
            '"' -> string()
            't' -> literal("true")
            'f' -> literal("false")
            'n' -> literal("null")
            else -> {
                val start = at
                while (at < raw.length && raw[at] !in " \r\n\t,]}") at++
                require(raw.substring(start, at).matches(Regex("-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?")))
            }
        }
    }
    private fun literal(word: String) { require(raw.startsWith(word, at)); at += word.length }
    private fun string(): String {
        val start = at; require(at < raw.length && raw[at++] == '"')
        while (at < raw.length) {
            val c = raw[at++]
            if (c == '"') {
                val decoded = JSONTokener(raw.substring(start, at)).nextValue() as? String
                require(decoded != null && validUnicode(decoded)); return decoded
            }
            require(c >= ' ')
            if (c == '\\') {
                require(at < raw.length)
                val escape = raw[at++]
                if (escape == 'u') {
                    require(at + 4 <= raw.length && raw.substring(at, at + 4).all { it in "0123456789abcdefABCDEF" }); at += 4
                } else require(escape in "\"\\/bfnrt")
            }
        }
        throw IllegalArgumentException("unterminated string")
    }
}
internal fun fields(o: JSONObject, required: Set<String>, optional: Set<String> = emptySet()) {
    val keys = o.keys().asSequence().toSet()
    require(keys.containsAll(required) && keys.all { it in required || it in optional }) { "unknown/missing field" }
}
internal fun text(o: JSONObject, key: String): String = (o.get(key) as? String)
    ?: throw IllegalArgumentException("expected string: $key")
internal fun obj(o: JSONObject, key: String): JSONObject = (o.get(key) as? JSONObject)
    ?: throw IllegalArgumentException("expected object: $key")
internal fun array(o: JSONObject, key: String): JSONArray = (o.get(key) as? JSONArray)
    ?: throw IllegalArgumentException("expected array: $key")
internal fun strings(a: JSONArray): List<String> = (0 until a.length()).map {
    a.get(it) as? String ?: throw IllegalArgumentException("expected string item")
}
internal fun unsignedInteger(value: Any, maximum: String): String {
    require(value is Number && value !is Double && value !is Float && value !is java.math.BigDecimal)
    return value.toString().also { require(decimalAtMost(it, maximum)) }
}
private fun nullableText(o: JSONObject, key: String): String? = if (!o.has(key) || o.isNull(key)) null else text(o, key)
private fun scope(o: JSONObject, restricted: Boolean = false) {
    fields(o, setOf("workspace_id"), setOf("project_id"))
    val ids = listOfNotNull(text(o, "workspace_id"), nullableText(o, "project_id"))
    if (restricted) require(ids.all { it.isNotEmpty() && it.length <= 128 && it.all { c -> c in 'a'..'z' || c in 'A'..'Z' || c in '0'..'9' || c in "-_.:" } })
}
private fun scopeRef(o: JSONObject) {
    fields(o, setOf("scope", "scope_generation"), setOf("account_id"))
    scope(obj(o, "scope")); parseRevision(text(o, "scope_generation")); nullableText(o, "account_id")
}
private fun documentRef(o: JSONObject) {
    fields(o, setOf("scope", "document_id", "revision", "format"))
    scope(obj(o, "scope"), true)
    val id = text(o, "document_id")
    require(id.isNotEmpty() && id.length <= 128 && id.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it in "-_.:" })
    parseRevision(text(o, "revision"))
    require(text(o, "format") in setOf("text", "docx", "pptx", "xlsx", "pdf", "doc", "ppt", "xls", "unknown"))
}
/** C1 wire adaptation only: no new shared DTOs, authority or dispatch. */
fun decodePublicValue(kind: String, raw: String): String {
    try {
        val o = strictObject(raw)
        when (kind) {
            "scope" -> scopeRef(o)
            "result" -> {
                fields(o, setOf("result_id", "input_document_ref", "input_result_refs", "content_digest", "producer_version", "parameters_digest"))
                parsePublicId(text(o, "result_id")); documentRef(obj(o, "input_document_ref"))
                strings(array(o, "input_result_refs")).forEach(::parsePublicId)
                parsePublicDigest(text(o, "content_digest")); parsePublicDigest(text(o, "parameters_digest")); text(o, "producer_version")
            }
            "coverage" -> {
                fields(o, setOf("state", "processed", "failed_units"), setOf("total"))
                val state = text(o, "state"); require(state in setOf("complete", "partial", "failed", "unknown"))
                val processed = parseRevision(text(o, "processed"))
                val total = nullableText(o, "total")?.let(::parseRevision)
                val units = array(o, "failed_units")
                for (i in 0 until units.length()) unsignedInteger(units.get(i), "4294967295")
                require(total == null || processed.length < total.length || processed.length == total.length && processed <= total)
                require(state != "complete" || total == processed && units.length() == 0)
            }
            "error" -> {
                fields(o, setOf("code", "phase", "retryability", "effect_knowledge", "safe_message"), setOf("original_intent_id", "details_ref"))
                require(text(o, "code") in setOf("invalid_argument", "unsupported_version", "capability_unavailable", "permission_denied", "stale_revision", "scope_changed", "resource_expired", "partial_result", "cancelled", "unknown_outcome"))
                require(text(o, "retryability") in setOf("never", "after_lookup", "after_reprepare"))
                require(text(o, "effect_knowledge") in setOf("not_started", "confirmed", "unknown"))
                text(o, "phase"); text(o, "safe_message")
                nullableText(o, "original_intent_id")?.let(::parsePublicId); nullableText(o, "details_ref")
            }
            else -> throw IllegalArgumentException("unknown C1 fixture kind")
        }
        return o.toString()
    } catch (e: Exception) { throw IllegalArgumentException("invalid public value", e) }
}
