package com.mightyoung.muyon.product.ui.publicservices

data class UiState(val surfaceId: String, val planRevision: String,
    val uiStateRevision: String, val viewState: Map<String, String>, val draftStateRef: String?)
data class BusinessSnapshot(val ref: SnapshotRef, val sourceRefs: List<SourceBinding>)
data class PresentationAccess(val scopeGeneration: String, val readAllowed: Boolean, val actionAllowed: Boolean)

/** Current display projection only; never an authorization token or business state. */
class PresentationProjection internal constructor(val plan: ValidatedPlan?, val state: UiState?,
    val snapshot: BusinessSnapshot?, val domainActionsEnabled: Boolean)

@Suppress("UNUSED_PARAMETER")
fun projectPresentation(plan: ValidatedPlan, state: UiState, snapshot: BusinessSnapshot,
    access: PresentationAccess): PresentationProjection = PresentationProjection(null, null, null, false)
