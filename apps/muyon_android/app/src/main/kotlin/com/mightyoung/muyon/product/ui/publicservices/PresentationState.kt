package com.mightyoung.muyon.product.ui.publicservices

import java.util.Collections

data class UiState(val surfaceId: String, val planRevision: String,
    val uiStateRevision: String, val viewState: Map<String, String>, val draftStateRef: String?)
data class BusinessSnapshot(val ref: SnapshotRef, val sourceRefs: List<SourceBinding>)
data class PresentationAccess(val scopeGeneration: String, val readAllowed: Boolean, val actionAllowed: Boolean)

/** Current display projection only; never an authorization token or business state. */
class PresentationProjection internal constructor(val plan: ValidatedPlan?, val state: UiState?,
    val snapshot: BusinessSnapshot?, val domainActionsEnabled: Boolean)

/** Clears only the current returned projection, not caller-owned historical data. */
fun projectPresentation(plan: ValidatedPlan, state: UiState, snapshot: BusinessSnapshot,
    access: PresentationAccess): PresentationProjection = try {
    require(u2ReadAccess(plan, access))
    val frozen = u2FrozenState(state)
    require(frozen.surfaceId == plan.plan.surfaceId && frozen.planRevision == plan.plan.planRevision)
    val sources = Collections.unmodifiableList(ArrayList(snapshot.sourceRefs))
    require(snapshot.ref == plan.plan.snapshotRef && sources.all { it in plan.context.sources.values })
    PresentationProjection(plan, frozen, snapshot.copy(sourceRefs = sources),
        access.actionAllowed && plan.context.actionAllowed)
} catch (_: IllegalArgumentException) { PresentationProjection(null, null, null, false) }

internal fun u2ReadAccess(plan: ValidatedPlan, access: PresentationAccess): Boolean = try {
    parseRevision(access.scopeGeneration)
    access.readAllowed && plan.context.readAllowed && access.scopeGeneration == plan.context.scopeGeneration
} catch (_: IllegalArgumentException) { false }

internal fun u2FrozenState(state: UiState): UiState {
    parsePublicId(state.surfaceId); parseRevision(state.planRevision); parseRevision(state.uiStateRevision)
    state.draftStateRef?.let(::parsePublicId)
    val values = LinkedHashMap(state.viewState)
    require(values.size <= 256) { "state_entry_limit" }
    var bytes = 0L
    for ((key, value) in values) {
        parsePublicId(key); require(validUnicode(value))
        bytes += value.toByteArray(Charsets.UTF_8).size
        require(bytes <= 65536) { "state_text_limit" }
    }
    return state.copy(viewState = Collections.unmodifiableMap(values))
}
