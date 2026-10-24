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
/**
 * Pure admission projection. It does not apply edits, save drafts, remember IDs,
 * dispatch, subscribe or cancel. Accepted is reserved for a trusted host result.
 */
fun projectEvent(plan: ValidatedPlan, state: UiState, event: UiEvent,
    access: PresentationAccess, seenEventIds: Set<String>): UiEventOutcome = try {
    if (!u2ReadAccess(plan, access)) UiEventOutcome.Rejected
    else checkedEvent(plan, u2FrozenState(state), event, access, seenEventIds.toSet())
} catch (_: IllegalArgumentException) { UiEventOutcome.Rejected }

private fun checkedEvent(plan: ValidatedPlan, state: UiState, event: UiEvent,
    access: PresentationAccess, seen: Set<String>): UiEventOutcome {
    parsePublicId(event.eventId); parsePublicId(event.surfaceId); parsePublicId(event.nodeId)
    parseRevision(event.observedPlanRevision); parseRevision(event.observedUiStateRevision)
    if (state.surfaceId != plan.plan.surfaceId || event.surfaceId != plan.plan.surfaceId) return UiEventOutcome.Rejected
    val node = plan.plan.nodes.singleOrNull { it.id == event.nodeId } ?: return UiEventOutcome.Rejected
    if (state.planRevision != plan.plan.planRevision || event.observedPlanRevision != plan.plan.planRevision ||
        event.observedUiStateRevision != state.uiStateRevision) return UiEventOutcome.Stale
    val bindings = node.eventBindings.filter { it.eventKind == event.eventKind && it.actionRef in plan.context.allowedActions }
    if (bindings.isEmpty()) return UiEventOutcome.Rejected
    val outcome = when (event.eventKind) {
        EventKind.LocalView -> {
            val p = event.typedPayload as? EventPayload.View ?: return UiEventOutcome.Rejected
            parsePublicId(p.key); payloadText(p.value)
            // The first slice has no separate view-key catalogue: use the declared
            // local action key, never an arbitrary callback or generic setter.
            if (bindings.none { it.actionRef == p.key }) return UiEventOutcome.Rejected
            UiEventOutcome.AppliedLocal
        }
        EventKind.DraftEdit -> {
            val p = event.typedPayload as? EventPayload.Edit ?: return UiEventOutcome.Rejected
            parsePublicId(p.draftRef); parsePublicId(p.fieldId); payloadText(p.value)
            val form = node.typedProps as? Props.Form ?: return UiEventOutcome.Rejected
            if (p.draftRef != state.draftStateRef || p.fieldId !in form.fieldIds) return UiEventOutcome.Rejected
            // Partial field values stay local. Domain validation/save is elsewhere.
            UiEventOutcome.DraftUpdated(p.draftRef)
        }
        EventKind.DomainRequest -> {
            val p = event.typedPayload as? EventPayload.Request ?: return UiEventOutcome.Rejected
            parsePublicId(p.actionRef)
            if (!access.actionAllowed || !plan.context.actionAllowed || bindings.none { it.actionRef == p.actionRef })
                return UiEventOutcome.Rejected
            UiEventOutcome.RequiresConfirmation(p.actionRef)
        }
    }
    return if (event.eventId in seen) UiEventOutcome.Duplicate else outcome
}

private fun payloadText(raw: String) {
    require(validUnicode(raw) && raw.toByteArray(Charsets.UTF_8).size <= 65536) { "invalid_event_text" }
}
