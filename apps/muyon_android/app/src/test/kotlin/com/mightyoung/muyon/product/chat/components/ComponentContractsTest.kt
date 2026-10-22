package com.mightyoung.muyon.product.chat.components

private var passed = 0
private fun test(name: String, body: () -> Unit) {
    body(); passed++; println("PASS $name")
}
private fun rejected(body: () -> Unit) {
    try { body() } catch (_: IllegalArgumentException) { return }
    error("Expected rejection")
}
private val scope = ComponentScope("workspace", "conversation", "project", "agent", 7)
private fun wire() = mapOf<String, Any?>(
    "schema_version" to 1, "component_id" to "card", "message_id" to "message",
    "kind" to "native_choices", "revision" to 3, "text" to "Choose",
    "actions" to listOf(
        mapOf("action_id" to "choose", "type" to "local_edit", "label" to "Choose", "field" to "answer"),
        mapOf("action_id" to "save", "type" to "submit_local", "label" to "Save"),
        mapOf("action_id" to "compose", "type" to "compose_message", "label" to "Draft", "text" to "Delete everything"),
        mapOf("action_id" to "host", "type" to "request_host_action", "label" to "Review")
    )
)
private fun component(raw: Map<String, Any?> = wire()) = ComponentDecoder.decode(raw, scope)
private fun ledger() = ComponentLedger(component(), "attempt-1")
private fun edited(): ComponentLedger = ledger().also { it.edit(scope, 3, 0, "choose", "A") }
private fun begin(l: ComponentLedger, intent: String = "intent-1") =
    l.submit(scope, 3, l.snapshot().stateRevision, "save", intent).submission
private fun receipt(p: PendingSubmission, status: ReceiptStatus = ReceiptStatus.COMMITTED) = OriginalReceipt(
    protocolVersion = 1, identity = p.identity, status = status,
    receiptRef = if (status == ReceiptStatus.COMMITTED) "receipt-1" else null,
    committed = status == ReceiptStatus.COMMITTED, occurredAt = "2026-10-22T00:00:00Z",
    heldMicroCny = 2620, actualMicroCny = null
)

fun main() {
    test("strict schema and finite kinds") {
        for (version in listOf(null, "1", 1.5, -1, 0, 2)) rejected { component(wire() + ("schema_version" to version)) }
        for (kind in listOf(null, "html", "javascript:tool", "unknown")) rejected { component(wire() + ("kind" to kind)) }
        for (revision in listOf(null, "3", -1, 3.5)) rejected { component(wire() + ("revision" to revision)) }
        rejected { component(wire() + ("component_id" to "")) }
        rejected { component(wire() + ("text" to "x".repeat(4097))) }
        rejected { component(wire() + ("ipc_method" to "chat_confirm")) }
    }
    test("unknown and disguised actions fail closed") {
        for (type in listOf("chat_confirm", "approve", "reaction", "local_edit ", "javascript:run")) {
            rejected { component(wire() + ("actions" to listOf(mapOf("action_id" to "x", "type" to type, "label" to "Run")))) }
        }
        val action = mapOf("action_id" to "x", "type" to "submit_local", "label" to "Save")
        rejected { component(wire() + ("actions" to listOf(action, action))) }
        rejected { component(wire() + ("actions" to List(33) { action })) }
        rejected { component(wire() + ("actions" to listOf(action + ("approved" to true)))) }
        rejected { component(wire() + ("actions" to listOf(mapOf("action_id" to "open", "type" to "open_source", "label" to "Open", "source_id" to "javascript:run", "source_revision" to 1, "page" to 1)))) }
        rejected { component(wire() + ("actions" to listOf(action + ("intent_id" to "model-chosen")))) }
    }
    test("ordinary selection and compose never grant business authority") {
        val l = edited()
        check(l.snapshot().draft == mapOf("answer" to "A"))
        check(l.snapshot().committed.isEmpty() && l.snapshot().pending == null)
        check(l.propose(scope, 3, "compose") == ActionProposal.ComposeDraft("Delete everything"))
        check(l.propose(scope, 3, "host") == ActionProposal.TrustedHostReviewRequired)
        rejected { l.submit(scope, 3, 1, "host", "intent") }
        rejected { l.submit(scope, 3, 1, "choose", "intent") }
    }
    test("scope binds conversation project agent workspace and mounted generation") {
        val l = ledger()
        for (other in listOf(scope.copy(conversationId = "other"), scope.copy(projectId = null),
            scope.copy(agentId = "other"), scope.copy(workspaceId = "other"), scope.copy(generation = 8))) {
            rejected { l.edit(other, 3, 0, "choose", "B") }
            rejected { l.propose(other, 3, "host") }
            rejected { l.submit(other, 3, 0, "save", "intent") }
        }
        check(l.snapshot().stateRevision == 0L)
    }
    test("old component and state revisions cannot overwrite draft") {
        val l = edited()
        rejected { l.edit(scope, 2, 1, "choose", "B") }
        rejected { l.edit(scope, 3, 0, "choose", "B") }
        rejected { l.submit(scope, 3, 0, "save", "intent") }
        rejected { l.edit(scope, 3, 1, "missing", "B") }
        rejected { l.edit(scope, 3, 1, "choose", "x".repeat(4097)) }
        check(l.snapshot().draft["answer"] == "A")
    }
    test("double click returns original identity; pending is not committed") {
        val l = edited(); val first = begin(l)
        val second = begin(l, "new-random-id")
        check(first == second && first.identity.intentId == "intent-1")
        check(l.snapshot().pending == first && l.snapshot().committed.isEmpty())
        rejected { l.edit(scope, 3, l.snapshot().stateRevision, "choose", "B") }
    }
    test("unknown and cancel request keep identity held cost and lookup only") {
        val l = edited(); val first = begin(l)
        l.observe(scope, receipt(first, ReceiptStatus.UNKNOWN))
        check(l.snapshot().pending?.phase == PendingPhase.UNKNOWN)
        check(l.recovery(scope) == Recovery.LookupOriginal(first.identity))
        check(l.submit(scope, 3, l.snapshot().stateRevision, "save", "retry") is SubmitDecision.LookupOriginal)
        l.requestCancel(scope, first.identity, l.snapshot().stateRevision)
        check(l.snapshot().pending?.phase == PendingPhase.CANCEL_REQUESTED)
        check(l.snapshot().committed.isEmpty())
        check(l.snapshot().heldMicroCny == 2620L && l.snapshot().actualMicroCny == null)
        check(l.recovery(scope) == Recovery.LookupOriginal(first.identity))
        check(l.submit(scope, 3, l.snapshot().stateRevision, "save", "retry-after-cancel") is SubmitDecision.LookupOriginal)
    }
    test("only exact original authoritative receipt can commit") {
        val l = edited(); val first = begin(l); val good = receipt(first)
        val id = first.identity
        for (bad in listOf(good.copy(protocolVersion = 2), good.copy(committed = false),
            good.copy(receiptRef = null), good.copy(identity = id.copy(intentId = "other")),
            good.copy(identity = id.copy(paramsDigest = "0".repeat(64))),
            good.copy(identity = id.copy(scope = scope.copy(projectId = "other"))),
            good.copy(identity = id.copy(componentRevision = 2)),
            good.copy(identity = id.copy(attemptId = "other")),
            good.copy(identity = id.copy(actionId = "host")), good.copy(heldMicroCny = -1))) {
            rejected { l.observe(scope, bad) }
        }
        rejected { l.observe(scope.copy(conversationId = "other"), good) }
        check(l.snapshot().committed.isEmpty())
        l.observe(scope, good)
        check(l.snapshot().committed == mapOf("answer" to "A"))
        check(l.snapshot().history.single() == good)
        l.observe(scope, good)
        check(l.snapshot().history.size == 1)
        check(l.recovery(scope) == Recovery.HistoricalReceipt(good))
        check(begin(l, "double-after-result").identity == id)
        rejected { l.observe(scope, good.copy(status = ReceiptStatus.UNKNOWN, committed = false, receiptRef = null)) }
    }
    test("confirmed cancellation and rejection are not success and preserve draft") {
        for (status in listOf(ReceiptStatus.CANCELLED, ReceiptStatus.REJECTED, ReceiptStatus.NOT_SUBMITTED)) {
            val l = edited(); val p = begin(l); l.requestCancel(scope, p.identity, l.snapshot().stateRevision)
            val result = receipt(p, status); l.observe(scope, result)
            check(l.snapshot().pending == null && l.snapshot().committed.isEmpty())
            check(l.snapshot().draft["answer"] == "A")
            check(l.recovery(scope) == Recovery.HistoricalReceipt(result))
        }
    }
    test("redo uses a fresh attempt and retains old receipts") {
        val l = edited(); val p = begin(l); l.observe(scope, receipt(p))
        rejected { l.redo(scope, "attempt-1") }
        l.redo(scope, "attempt-2")
        check(l.snapshot().history.size == 1 && l.snapshot().draft["answer"] == "A")
        rejected { begin(l, "intent-1") }
        l.edit(scope, 3, l.snapshot().stateRevision, "choose", "B")
        val next = begin(l, "intent-2")
        check(next.identity.attemptId == "attempt-2" && next.identity.paramsDigest != p.identity.paramsDigest)
        rejected { l.observe(scope, receipt(p)) }
        rejected { l.redo(scope, "attempt-3") }
    }
    test("snapshot restore retains unresolved identity without resubmission") {
        val l = edited(); val p = begin(l); l.observe(scope, receipt(p, ReceiptStatus.UNKNOWN))
        val restored = ComponentLedger.restore(component(), l.snapshot())
        check(restored.recovery(scope) == Recovery.LookupOriginal(p.identity))
        check(restored.submit(scope, 3, restored.snapshot().stateRevision, "save", "retry") is SubmitDecision.LookupOriginal)
        rejected { ComponentLedger.restore(component(), l.snapshot().copy(scope = scope.copy(generation = 9))) }
    }
    test("source references are typed, versioned, and never executable URLs") {
        val raw = wire() + ("actions" to listOf(mapOf("action_id" to "open", "type" to "open_source", "label" to "Open", "source_id" to "pdf-1", "source_revision" to 4, "page" to 2)))
        val l = ComponentLedger(component(raw), "attempt")
        check(l.propose(scope, 3, "open") == ActionProposal.OpenSource(SourceRef("pdf-1", 4, 2)))
        rejected { l.propose(scope, 3, "missing") }
    }
    test("submission decisions distinguish new, duplicate, unknown and historical outcomes") {
        val l = edited()
        val first = l.submit(scope, 3, 1, "save", "intent")
        check(first is SubmitDecision.NewPending)
        check(l.submit(scope, 3, 1, "save", "double") is SubmitDecision.ExistingPending)
        l.observe(scope, receipt(first.submission, ReceiptStatus.UNKNOWN))
        check(l.submit(scope, 3, l.snapshot().stateRevision, "save", "retry") is SubmitDecision.LookupOriginal)
        l.observe(scope, receipt(first.submission))
        val historical = l.submit(scope, 3, l.snapshot().stateRevision, "save", "again")
        check(historical is SubmitDecision.HistoricalReceipt && historical.receipt.committed)
    }
    test("damaged restored pending identity and values cannot become authority") {
        val l = edited(); val p = begin(l); val s = l.snapshot()
        val corrupt = p.copy(identity = p.identity.copy(scope = scope.copy(conversationId = "other")))
        rejected { ComponentLedger.restore(component(), s.copy(pending = corrupt, lastSubmission = corrupt)) }
        rejected { ComponentLedger.restore(component(), s.copy(pending = p.copy(values = mapOf("answer" to "B")))) }
        rejected { ComponentLedger.restore(component(), s.copy(lastSubmission = null)) }
        rejected { ComponentLedger.restore(component(), s.copy(attempts = listOf("attempt-1", "attempt-1"))) }
        rejected { ComponentLedger.restore(component(), s.copy(committed = mapOf("answer" to "B"))) }
        l.observe(scope, receipt(p))
        rejected { ComponentLedger.restore(component(), l.snapshot().copy(committed = mapOf("answer" to "B"))) }
        l.redo(scope, "attempt-2")
        val next = begin(l, "intent-2"); val current = l.snapshot()
        val reused = next.copy(identity = next.identity.copy(intentId = "intent-1"))
        rejected { ComponentLedger.restore(component(), current.copy(pending = reused, lastSubmission = reused)) }
    }
    test("simultaneous double click records one identity and one state transition") {
        val l = edited()
        val results = java.util.Collections.synchronizedList(mutableListOf<PendingSubmission>())
        val failures = java.util.Collections.synchronizedList(mutableListOf<Throwable>())
        val start = java.util.concurrent.CountDownLatch(1)
        val workers = (1..16).map { index -> Thread {
            start.await()
            try { results.add(l.submit(scope, 3, 1, "save", "intent-$index").submission) }
            catch (failure: Throwable) { failures.add(failure) }
        }.apply { start() } }
        start.countDown(); workers.forEach { it.join() }
        check(failures.isEmpty() && results.size == 16)
        check(results.map { it.identity }.distinct().size == 1)
        check(l.snapshot().stateRevision == 2L && l.snapshot().history.isEmpty())
    }
    test("malformed Unicode cannot alias a different value digest") {
        val l = ledger()
        for (value in listOf("\uD800", "\uD801", "\uDC00", "x\uD800z")) {
            rejected { l.edit(scope, 3, 0, "choose", value) }
            rejected { component(wire() + ("text" to value)) }
        }
        l.edit(scope, 3, 0, "choose", "Valid \uD83D\uDE00")
        check(l.snapshot().draft["answer"] == "Valid \uD83D\uDE00")
    }
    test("late cancellation from attempt A must not mutate pending attempt B") {
        val l = edited(); val a = begin(l)
        val capturedScope = scope
        val capturedIdentity = a.identity
        val capturedRevision = l.snapshot().stateRevision
        l.observe(scope, receipt(a)); l.redo(scope, "attempt-B")
        l.edit(scope, 3, l.snapshot().stateRevision, "choose", "B")
        val b = begin(l, "intent-B"); val before = l.snapshot()
        rejected { l.requestCancel(capturedScope, capturedIdentity, capturedRevision) }
        // Matching B's current CAS token must not make A's identity eligible either.
        rejected { l.requestCancel(capturedScope, capturedIdentity, before.stateRevision) }
        val after = l.snapshot()
        println("late-cancel probe: original=${a.identity.intentId} current=${b.identity.intentId} before=${before.pending?.phase} after=${after.pending?.phase}")
        check(after == before) { "Late cancellation for A mutated pending B" }
    }
    test("normal and repeated cancellation require exact pending identity and current CAS") {
        val l = edited(); val p = begin(l); val before = l.snapshot()
        val cancelled = l.requestCancel(scope, p.identity, before.stateRevision)
        val after = l.snapshot()
        check(cancelled.identity == p.identity && cancelled.phase == PendingPhase.CANCEL_REQUESTED)
        check(after.stateRevision == before.stateRevision + 1 && after.pending == cancelled)
        check(after.history == before.history && after.committed == before.committed && after.draft == before.draft)
        check(l.requestCancel(scope, p.identity, after.stateRevision) == cancelled)
        check(l.snapshot() == after) // Idempotent current-revision duplicate.
        rejected { l.requestCancel(scope, p.identity, before.stateRevision) }
        check(l.snapshot() == after) // Stale duplicate must not silently refresh its CAS.
        check(l.recovery(scope) == Recovery.LookupOriginal(p.identity))
        l.observe(scope, receipt(p, ReceiptStatus.CANCELLED))
        val terminal = l.snapshot()
        rejected { l.requestCancel(scope, p.identity, terminal.stateRevision) }
        check(l.snapshot() == terminal && terminal.committed.isEmpty())
    }
    test("cancellation rejects stale revision and every altered identity field without mutation") {
        val l = edited(); val p = begin(l); val before = l.snapshot(); val id = p.identity
        for (bad in listOf(id.copy(intentId = "other"), id.copy(attemptId = "other"),
            id.copy(componentId = "other"), id.copy(messageId = "other"), id.copy(actionId = "other"),
            id.copy(componentRevision = 2), id.copy(stateRevision = id.stateRevision + 1),
            id.copy(paramsDigest = "0".repeat(64)), id.copy(scope = scope.copy(conversationId = "other")))) {
            rejected { l.requestCancel(scope, bad, before.stateRevision) }
            check(l.snapshot() == before)
        }
        for (revision in listOf(-1L, before.stateRevision - 1, before.stateRevision + 1)) {
            rejected { l.requestCancel(scope, id, revision) }; check(l.snapshot() == before)
        }
        for (other in listOf(scope.copy(conversationId = "other"), scope.copy(projectId = null),
            scope.copy(agentId = "other"), scope.copy(workspaceId = "other"), scope.copy(generation = 8))) {
            rejected { l.requestCancel(other, id, before.stateRevision) }; check(l.snapshot() == before)
            rejected { l.requestCancel(other, id.copy(scope = other), before.stateRevision) }; check(l.snapshot() == before)
        }
    }
    test("unknown cancellation preserves original identity costs and lookup-only recovery") {
        val l = edited(); val p = begin(l); val captured = l.snapshot().stateRevision
        l.observe(scope, receipt(p, ReceiptStatus.UNKNOWN)); val unknown = l.snapshot()
        rejected { l.requestCancel(scope, p.identity, captured) }
        check(l.snapshot() == unknown)
        l.requestCancel(scope, p.identity, unknown.stateRevision); val cancelled = l.snapshot()
        check(cancelled.pending?.phase == PendingPhase.CANCEL_REQUESTED && cancelled.pending.identity == p.identity)
        check(cancelled.heldMicroCny == unknown.heldMicroCny && cancelled.actualMicroCny == null)
        check(cancelled.committed == unknown.committed && cancelled.history == unknown.history)
        check(l.recovery(scope) == Recovery.LookupOriginal(p.identity))
        check(l.submit(scope, 3, cancelled.stateRevision, "save", "retry") is SubmitDecision.LookupOriginal)
    }
    println("PASS $passed offline contract groups; no network/provider/IPC code invoked")
}
