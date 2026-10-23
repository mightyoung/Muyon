package com.mightyoung.muyon.product.services.documents

/** Offline declared values only; this is not a resolved model or search capability. */
data class VectorDescriptor(
    val modelVersion: String,
    val tokenizerVersion: String,
    val dimensions: Int,
    val chunkVersion: String,
)

/** Candidate fields, not an existing storage schema, ResultRef or permission grant. */
data class LegacyIndexEntry(
    val documentId: String?,
    val resultId: String?,
    val model: VectorDescriptor?,
)

/**
 * Compares declared scalar-string values only, with Rust 1.93.1 trim-empty rules.
 * Does not trim/normalize versions or attest actual vectors/model availability.
 * Unpaired UTF16 is outside the shared Rust String domain: input precondition
 * failure throws rather than inventing a shared Boolean verdict or codec policy.
 */
fun validateCompatibility(index: VectorDescriptor, query: VectorDescriptor): Boolean {
    val versions = listOf(index.modelVersion, index.tokenizerVersion, index.chunkVersion,
        query.modelVersion, query.tokenizerVersion, query.chunkVersion)
    versions.forEach(::requireScalarString)
    return index.dimensions > 0 && query.dimensions > 0 &&
        versions.all { version -> version.any { !rustWhitespace(it) } } && index == query
}

/**
 * Shape-only necessary conditions for later host resolution, NEVER authority.
 * True does not prove existence, scope/grant/revision, source readability or
 * query permission. No legacy paper ID inference and no trusted-resolution API.
 * Inputs must belong to the shared Unicode scalar-string domain (see above).
 */
fun hasPublicReferenceCandidate(entry: LegacyIndexEntry): Boolean {
    entry.documentId?.let(::requireScalarString)
    entry.resultId?.let(::requireScalarString)
    val document = entry.documentId ?: return false
    val result = entry.resultId ?: return false
    val model = entry.model ?: return false
    return document.isNotEmpty() && document.length <= 128 && document.all {
        it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it in "_.:-"
    } && result.isNotEmpty() && '\u0000' !in result && result.toByteArray(Charsets.UTF_8).size <= 128 &&
        validateCompatibility(model, model)
}

// Fixed Rust White_Space property, not Java/Kotlin platform default whitespace.
private fun rustWhitespace(c: Char): Boolean = c in '\u0009'..'\u000D' || c == ' ' ||
    c == '\u0085' || c == '\u00A0' || c == '\u1680' || c in '\u2000'..'\u200A' ||
    c == '\u2028' || c == '\u2029' || c == '\u202F' || c == '\u205F' || c == '\u3000'

private fun requireScalarString(raw: String) {
    var at = 0
    while (at < raw.length) {
        val c = raw[at++]
        if (c in '\uD800'..'\uDBFF') {
            require(at < raw.length && raw[at] in '\uDC00'..'\uDFFF') { "outside Unicode scalar-string input domain" }
            at++
        } else require(c !in '\uDC00'..'\uDFFF') { "outside Unicode scalar-string input domain" }
    }
}
