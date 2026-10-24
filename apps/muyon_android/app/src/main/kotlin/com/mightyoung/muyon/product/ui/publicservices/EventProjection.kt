package com.mightyoung.muyon.product.ui.publicservices

data class UiEvent(val eventId: String, val surfaceId: String, val nodeId: String,
    val observedPlanRevision: String, val observedUiStateRevision: String,
    val eventKind: EventKind, val typedPayload: EventPayload)
sealed interface EventPayload {
    data class View(val key: String, val value: String) : EventPayload
    data class Edit(val draftRef: String, val fieldId: String, val value: String) : EventPayload
    data class Request(val actionRef: String) : EventPayload
}
sealed interface UiEventOutcome {
    data object AppliedLocal : UiEventOutcome
    data class DraftUpdated(val draftRef: String) : UiEventOutcome
    data class RequiresConfirmation(val actionRef: String) : UiEventOutcome
    data class Accepted(val intentId: String, val receiptRef: String?, val jobId: String?) : UiEventOutcome
    data object Rejected : UiEventOutcome
    data object Stale : UiEventOutcome
    data object Duplicate : UiEventOutcome
}
@Suppress("UNUSED_PARAMETER")
fun projectEvent(plan: ValidatedPlan, state: UiState, event: UiEvent,
    access: PresentationAccess, seenEventIds: Set<String>): UiEventOutcome = UiEventOutcome.Rejected
