package com.mightyoung.muyon.product.documents.host

/** Service-derived identity facts, NOT document permission or an account ACL.
 * Production construction belongs only to ProductService's current Binder/scope callback. */
internal class LocalWorkspaceReaderPrincipal internal constructor(
    val workspaceId: String, val serviceEpoch: String, val serviceSession: String,
    val projectId: String, val scopeGeneration: Long, private val binderOwner: Any, private val ownerIsLive: () -> Boolean,
) {
    init { require(listOf(workspaceId, serviceEpoch, serviceSession, projectId).all { it.isNotBlank() && it.length <= 128 }); require(scopeGeneration > 0) }
    internal fun isLive(): Boolean = try { ownerIsLive() } catch (_: Exception) { false }
    internal fun sameOwnerScope(other: LocalWorkspaceReaderPrincipal) = isLive() && other.isLive() && binderOwner === other.binderOwner &&
        workspaceId == other.workspaceId && serviceEpoch == other.serviceEpoch && serviceSession == other.serviceSession &&
        projectId == other.projectId && scopeGeneration == other.scopeGeneration
}

/** Selected immutable source facts. They remain an intent until native policy validates them. */
internal data class ExactReaderSource(val workspaceId: String, val projectId: String, val documentId: String,
    val revision: String, val format: String, val sourceDigest: String) {
    init {
        require(listOf(workspaceId, projectId, documentId).all { it.matches(Regex("[A-Za-z0-9_.:-]{1,128}")) })
        require(revision.matches(Regex("0|[1-9][0-9]{0,19}")) && (revision.length < 20 || revision <= "18446744073709551615"))
        require(format in setOf("text", "pdf", "docx", "pptx", "xlsx", "doc", "ppt", "xls", "unknown"))
        require(sourceDigest.matches(Regex("[0-9a-f]{64}")))
    }
}
