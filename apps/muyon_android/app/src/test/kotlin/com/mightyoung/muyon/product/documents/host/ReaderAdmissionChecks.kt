package com.mightyoung.muyon.product.documents.host

fun main() {
    val binder = Any()
    val principal = LocalWorkspaceReaderPrincipal("workspace", "service-epoch", "session", "project", 1, binder) { true }
    val fresh = LocalWorkspaceReaderPrincipal("workspace", "service-epoch", "session", "project", 1, binder) { true }
    val domain = ReaderDocumentBatchDomain()
    val registry = ReaderAdmissionRegistry(principal, domain)
    val a = ExactReaderSource("workspace", "project", "doc-A", "1", "pdf", "a".repeat(64))
    val b = a.copy(documentId = "doc-B")
    val selectionA = registry.acceptSelection(fresh, 1, a)
    val selectionB = registry.acceptSelection(fresh, 2, b)
    var calls = 0
    check(runCatching { batch(registry, fresh, selectionA) { calls++; "wrong" } }.isFailure)
    check(!registry.stopIfCurrent(fresh, selectionA) && registry.isCurrent(fresh, selectionB))
    check(calls == 0) // stale A refused before a destructive native open
    check(batch(registry, fresh, selectionB) { calls++; "B" } == "B" && calls == 1)
    check(runCatching { registry.acceptSelection(fresh, 1, a) }.isFailure)
    val selectionA3 = registry.acceptSelection(fresh, 3, a)
    check(runCatching { batch(registry, fresh, selectionA) { calls++ } }.isFailure)
    check(batch(registry, fresh, selectionA3) { "A3" } == "A3")
    val foreign = LocalWorkspaceReaderPrincipal("workspace", "service-epoch", "session", "project", 1, Any()) { true }
    check(runCatching { batch(registry, foreign, selectionA3) { calls++ } }.isFailure)
    val scopeChanged = LocalWorkspaceReaderPrincipal("workspace", "service-epoch", "session", "project", 2, binder) { true }
    check(runCatching { batch(registry, scopeChanged, selectionA3) { calls++ } }.isFailure)
    check(runCatching { registry.acceptSelection(fresh, 3, b) }.isFailure)
    val forged = ReaderSelectionLease(a, 3)
    check(runCatching { batch(registry, fresh, forged) { calls++ } }.isFailure)
    var alive = true
    val revocable = LocalWorkspaceReaderPrincipal("workspace", "service-epoch", "session", "project", 1, binder) { alive }
    val revocableRegistry = ReaderAdmissionRegistry(revocable, ReaderDocumentBatchDomain())
    val old = revocableRegistry.acceptSelection(revocable, 1, a)
    alive = false
    check(!revocableRegistry.isCurrent(revocable, old))
    alive = true
    check(runCatching { batch(revocableRegistry, revocable, old) { calls++ } }.isFailure)
    registry.stop()
    check(runCatching { batch(registry, fresh, selectionA3) { calls++ } }.isFailure)
    check(runCatching { registry.acceptSelection(fresh, 4, a) }.isFailure)
    check(calls == 1)
    readerBatchChecks()
    println("PASS reader admission: exact actual-owner/scope identity; stale A rejected BEFORE native callback; ABA, cross-owner/generation, duplicate-conflict and terminal stop; no authority or native grant fabricated")
}

private fun <T : Any> batch(registry: ReaderAdmissionRegistry, principal: LocalWorkspaceReaderPrincipal,
    selection: ReaderSelectionLease, operation: () -> T): T = registry.runDocumentBatch(principal, selection,
    operation, { ReaderBatchInvalidation.CLEAN }, {}, {}, {})
