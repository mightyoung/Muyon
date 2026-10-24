package com.mightyoung.muyon.product.development

internal fun developmentScopeKey(conversation: String, project: String?): String =
    "${conversation.length}:$conversation:${project?.let { "${it.length}:$it" } ?: "none"}"

internal fun developmentKindLabel(kind: String): String = when (kind) {
    "requirement" -> "需求"
    "bug" -> "Bug"
    "question" -> "问题"
    else -> "未知类型"
}

internal fun developmentScopeGeneration(value: Any?): Long? = when (value) {
    is Int -> value.toLong().takeIf { it >= 0 }
    is Long -> value.takeIf { it >= 0 }
    else -> null
}

/** Identity frozen from the exact displayed command and native binding digest. */
internal data class DevelopmentProjectReview(
    val planId: String,
    val bindingDigest: String,
    val scopeGeneration: Long,
    val draftId: String,
    val editRevision: String,
) {
    fun canConfirm(generation: Long?, draft: String, revision: String?): Boolean =
        planId.isNotBlank() && bindingDigest.isNotBlank() && scopeGeneration >= 0 &&
            generation == scopeGeneration && draft == draftId && revision == editRevision
}

/** Callbacks may only change the mounted editor and exact draft selection. */
internal class DevelopmentCallbackScope {
    private data class Selection(val conversation: String, val project: String?, val draft: String, val scopeGeneration: Long?)
    private var selected: Selection? = null
    private var generation = 0L
    private var closed = false
    fun select(conversation: String, project: String?, draftId: String, scopeGeneration: Long? = null) {
        val next = Selection(conversation, project, draftId, scopeGeneration)
        if (next != selected) { selected = next; generation++ }
    }
    fun capture(): Long = generation
    fun accepts(token: Long): Boolean = !closed && token == generation
    fun close() { closed = true; generation++ }
}
