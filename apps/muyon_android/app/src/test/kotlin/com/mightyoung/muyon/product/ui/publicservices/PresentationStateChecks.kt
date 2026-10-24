package com.mightyoung.muyon.product.ui.publicservices

private var passed = 0
private var failed = 0
private fun checkCase(name: String, body: () -> Unit) {
    try { body(); passed++; println("PASS U2 $name") }
    catch (error: Exception) { failed++; println("FAIL U2 $name: ${error.message}") }
}
private val snap = SnapshotRef("snapshot:1", "9007199254740993")
private val answer = AnswerRef("answer:1", "9223372036854775808")
private val request = PresentationRequest("request:1", answer, snap, "supplement", "1", "capability:1")
private val source = SourceBinding("result:1", "doc:1", snap.revision, "a".repeat(64), "0", "4", 0)
private val bindings = listOf(EventBinding(EventKind.LocalView, "view:expand"),
    EventBinding(EventKind.DraftEdit, "edit:form"), EventBinding(EventKind.DomainRequest, "act:submit"))
private fun root() = Node("form", ComponentType.FormCard,
    Props.Form(listOf("title", "amount"), mapOf("title" to "text", "amount" to "decimal"), mapOf("title" to "old"), emptyMap()),
    emptyList(), listOf("message", "progress", "source", "receipt", "draft"), bindings)
private fun context() = ValidationContext(snap, "18446744073709551615", bindings.map { it.actionRef }.toSet(), mapOf("source:1" to source), true, true)
private fun input() = UIPlan(1, "surface:1", "9223372036854775808", snap, "form", listOf(root(),
    Node("message", ComponentType.MessageBlock, Props.Message("original answer", answer), emptyList(), emptyList(), emptyList()),
    Node("progress", ComponentType.TaskProgressCard, Props.Progress("job:1", "unknown", "0", null), emptyList(), emptyList(), emptyList()),
    Node("source", ComponentType.SourceCard, Props.Source(source, "AAA", "unassessed"), listOf("source:1"), emptyList(), emptyList()),
    Node("receipt", ComponentType.ReceiptCard, Props.Receipt("intent:1", null), emptyList(), emptyList(), emptyList()),
    Node("draft", ComponentType.DraftArtifactCard, Props.DraftArtifact("draft:1", "unsaved", "unsaved"), emptyList(), emptyList(), emptyList())))
private fun validated(p: UIPlan = input(), c: ValidationContext = context()): ValidatedPlan = checkNotNull(validatePlan(request, p, c).plan)
private fun state() = UiState("surface:1", input().planRevision, "18446744073709551615", mapOf("view:expand" to "false"), "draft:1")
private fun access() = PresentationAccess(context().scopeGeneration, true, true)
private fun event(kind: EventKind = EventKind.LocalView, payload: EventPayload = EventPayload.View("view:expand", "true")) =
    UiEvent("event:1", "surface:1", "form", input().planRevision, state().uiStateRevision, kind, payload)
private fun outcome(e: UiEvent = event(), s: UiState = state(), a: PresentationAccess = access(), seen: Set<String> = emptySet(), p: ValidatedPlan = validated()) = projectEvent(p, s, e, a, seen)
private fun hidden(p: PresentationProjection) = check(p.plan == null && p.state == null && p.snapshot == null && !p.domainActionsEnabled)

fun main() {
    checkCase("local view and draft edits are pure outcomes; domain requires confirmation") {
        check(outcome() == UiEventOutcome.AppliedLocal)
        check(outcome(event(EventKind.DraftEdit, EventPayload.Edit("draft:1", "title", "new"))) == UiEventOutcome.DraftUpdated("draft:1"))
        check(outcome(event(EventKind.DomainRequest, EventPayload.Request("act:submit"))) == UiEventOutcome.RequiresConfirmation("act:submit"))
    }
    checkCase("old observed plan and UI state revisions are stale without numeric conversion") {
        for (e in listOf(event().copy(observedPlanRevision = "1"), event().copy(observedUiStateRevision = "9007199254740993")))
            check(outcome(e) == UiEventOutcome.Stale)
        check(outcome(s = state().copy(planRevision = "1")) == UiEventOutcome.Stale)
        check(outcome() == UiEventOutcome.AppliedLocal)
    }
    checkCase("event identity surface and node mismatches reject before duplicate handling") {
        for (e in listOf(event().copy(eventId = ""), event().copy(surfaceId = "other"), event().copy(nodeId = "missing")))
            check(outcome(e, seen = setOf(e.eventId)) == UiEventOutcome.Rejected)
        check(outcome(s = state().copy(surfaceId = "other")) == UiEventOutcome.Rejected)
        check(outcome(event().copy(observedPlanRevision = "01")) == UiEventOutcome.Rejected)
    }
    checkCase("bound valid event replay is duplicate for every event family") {
        for (e in listOf(event(), event(EventKind.DraftEdit, EventPayload.Edit("draft:1", "title", "new")), event(EventKind.DomainRequest, EventPayload.Request("act:submit"))))
            check(outcome(e, seen = setOf("event:1")) == UiEventOutcome.Duplicate)
    }
    checkCase("kind payload action and local key are closed to the validated node bindings") {
        for (e in listOf(event(payload = EventPayload.Request("act:submit")),
            event(EventKind.DomainRequest, EventPayload.View("view:expand", "true")),
            event(EventKind.DomainRequest, EventPayload.Request("unknown")),
            event(EventKind.DomainRequest, EventPayload.Request("view:expand")),
            event(payload = EventPayload.View("unknown", "true")), event().copy(nodeId = "message")))
            check(outcome(e) == UiEventOutcome.Rejected)
    }
    checkCase("draft binding requires current draft and a declared form field") {
        for (e in listOf(event(EventKind.DraftEdit, EventPayload.Edit("other", "title", "new")),
            event(EventKind.DraftEdit, EventPayload.Edit("draft:1", "unknown", "new")),
            event(EventKind.DraftEdit, EventPayload.Edit("draft:1", "title", "new")).copy(nodeId = "message")))
            check(outcome(e) == UiEventOutcome.Rejected)
        check(outcome(event(EventKind.DraftEdit, EventPayload.Edit("draft:1", "title", "new")), s = state().copy(draftStateRef = null)) == UiEventOutcome.Rejected)
        // Partial decimal editing remains a local draft, not monetary validation.
        check(outcome(event(EventKind.DraftEdit, EventPayload.Edit("draft:1", "amount", "1."))) == UiEventOutcome.DraftUpdated("draft:1"))
    }
    checkCase("payload Unicode and byte limits reject malformed or oversized text") {
        for (bad in listOf("\uD800", "甲".repeat(21846))) {
            check(outcome(event(payload = EventPayload.View("view:expand", bad))) == UiEventOutcome.Rejected)
            check(outcome(event(EventKind.DraftEdit, EventPayload.Edit("draft:1", "title", bad))) == UiEventOutcome.Rejected)
        }
        check(outcome(event(payload = EventPayload.View("view:expand", "x".repeat(65536)))) == UiEventOutcome.AppliedLocal)
    }
    checkCase("read and scope revocation clear this display projection and reject all events") {
        for (a in listOf(access().copy(readAllowed = false), access().copy(scopeGeneration = "1"), access().copy(scopeGeneration = "01"))) {
            hidden(projectPresentation(validated(), state(), BusinessSnapshot(snap, listOf(source)), a))
            for (e in listOf(event(), event(EventKind.DraftEdit, EventPayload.Edit("draft:1", "title", "new")), event(EventKind.DomainRequest, EventPayload.Request("act:submit"))))
                check(outcome(e, a = a, seen = setOf(e.eventId)) == UiEventOutcome.Rejected)
        }
    }
    checkCase("action revocation preserves readable content and local editing only") {
        val a = access().copy(actionAllowed = false)
        val p = projectPresentation(validated(), state(), BusinessSnapshot(snap, listOf(source)), a)
        check(p.plan != null && p.state != null && p.snapshot != null && !p.domainActionsEnabled)
        check(outcome(a = a) == UiEventOutcome.AppliedLocal)
        check(outcome(event(EventKind.DraftEdit, EventPayload.Edit("draft:1", "title", "new")), a = a) == UiEventOutcome.DraftUpdated("draft:1"))
        check(outcome(event(EventKind.DomainRequest, EventPayload.Request("act:submit")), a = a) == UiEventOutcome.Rejected)
    }
    checkCase("presentation snapshots copy mutable inputs and preserve independent axes") {
        val map = linkedMapOf("view:expand" to "false")
        val sources = mutableListOf(source)
        val p = projectPresentation(validated(), state().copy(viewState = map), BusinessSnapshot(snap, sources), access())
        map.clear(); sources.clear()
        check(checkNotNull(p.state).viewState["view:expand"] == "false")
        check(checkNotNull(p.snapshot).sourceRefs == listOf(source))
        check(runCatching { (p.state!!.viewState as MutableMap<String,String>).clear() }.isFailure)
        check(runCatching { (p.snapshot!!.sourceRefs as MutableList<SourceBinding>).clear() }.isFailure)
        check(p.state!!.draftStateRef == "draft:1")
        val nodes = checkNotNull(p.plan).plan.nodes
        check((nodes.first { it.id == "message" }.typedProps as Props.Message).answerRef == answer)
        check((nodes.first { it.id == "progress" }.typedProps as Props.Progress).total == null)
        check((nodes.first { it.id == "receipt" }.typedProps as Props.Receipt).originalIntentId == "intent:1")
        check((nodes.first { it.id == "source" }.typedProps as Props.Source).quote == "AAA") // Not proof of verbatim source text.
    }
    checkCase("stale snapshot state and unknown source cannot be displayed") {
        hidden(projectPresentation(validated(), state().copy(planRevision = "1"), BusinessSnapshot(snap, listOf(source)), access()))
        hidden(projectPresentation(validated(), state(), BusinessSnapshot(snap.copy(revision = "1"), listOf(source)), access()))
        hidden(projectPresentation(validated(), state(), BusinessSnapshot(snap, listOf(source.copy(revision = "1"))), access()))
        hidden(projectPresentation(validated(), state().copy(uiStateRevision = "01"), BusinessSnapshot(snap, listOf(source)), access()))
    }
    checkCase("validated plan remains immutable after caller mutation") {
        val actionSet = context().allowedActions.toMutableSet()
        val nodeList = input().nodes.toMutableList()
        val p = validated(input().copy(nodes = nodeList), context().copy(allowedActions = actionSet))
        nodeList.clear(); actionSet.clear()
        check(outcome(p = p) == UiEventOutcome.AppliedLocal)
        check(outcome(event(EventKind.DomainRequest, EventPayload.Request("act:submit")), p = p) == UiEventOutcome.RequiresConfirmation("act:submit"))
    }
    checkCase("U1 unresolved trusted references remain unavailable to U2") {
        for ((kind, props) in listOf(ComponentType.ConfirmationCard to Props.Confirmation("prepared:1"),
            ComponentType.ReceiptCard to Props.Receipt("intent:1", "receipt:1"),
            ComponentType.AttachmentCard to Props.Attachment("doc:1", listOf("coverage:1")),
            ComponentType.DraftArtifactCard to Props.DraftArtifact("draft:1", "content", "saved"))) {
            val n = Node("root", kind, props, emptyList(), emptyList(), emptyList())
            val result = validatePlan(request, input().copy(root = "root", nodes = listOf(n)), context())
            check(result.decision == Decision.TextOnly && result.plan == null)
        }
    }
    checkCase("projection never mutates state seen IDs or produces Accepted") {
        val map = linkedMapOf("view:expand" to "false")
        val ids = linkedSetOf<String>()
        val s = state().copy(viewState = map)
        val events = listOf(event(), event(EventKind.DraftEdit, EventPayload.Edit("draft:1", "title", "new")), event(EventKind.DomainRequest, EventPayload.Request("act:submit")))
        for (e in events) check(projectEvent(validated(), s, e, access(), ids) !is UiEventOutcome.Accepted)
        check(map == mapOf("view:expand" to "false") && ids.isEmpty() && s.uiStateRevision == state().uiStateRevision)
    }
    println("SUMMARY U2 $passed passed / $failed failed; pure state/event only")
    check(failed == 0) { "U2 checks failed" }
}
