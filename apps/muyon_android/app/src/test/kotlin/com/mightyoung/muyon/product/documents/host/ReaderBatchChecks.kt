package com.mightyoung.muyon.product.documents.host

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

fun readerBatchChecks() {
    // Revocation during native work blocks more business calls but MUST NOT drop
    // the original administrative drain or exact output disposal.
    run {
        var alive = true
        val owner = LocalWorkspaceReaderPrincipal("workspace", "epoch", "session", "project", 1, Any()) { alive }
        val registry = ReaderAdmissionRegistry(owner, ReaderDocumentBatchDomain())
        val selected = registry.acceptSelection(owner, 1, ExactReaderSource("workspace", "project", "doc", "1", "pdf", "a".repeat(64)))
        var drained = 0; var cleared = 0; var discarded = 0
        check(runCatching { registry.runNativeDocumentBatch(owner, selected, { permit ->
            permit.requireBusiness(owner); alive = false
            check(runCatching { permit.requireBusiness(owner) }.isFailure)
            "synthetic-native-result"
        }, { permit -> permit.requireAdministrative(); drained++; ReaderBatchInvalidation.CLEAN },
            { check(it === selected); cleared++ }, { error("unexpected_global_clear") }, { discarded++ }) }.isFailure)
        check(drained == 1 && cleared == 1 && discarded == 1)
    }
    // A native transport permit cannot escape its serialized operation+drain batch.
    run {
        val owner = LocalWorkspaceReaderPrincipal("workspace", "epoch", "session", "project", 1, Any()) { true }
        val registry = ReaderAdmissionRegistry(owner, ReaderDocumentBatchDomain())
        val selected = registry.acceptSelection(owner, 1, ExactReaderSource("workspace", "project", "doc", "1", "pdf", "a".repeat(64)))
        var captured: ReaderNativeBatchPermit? = null
        registry.runNativeDocumentBatch(owner, selected, { permit ->
            permit.requireBusiness(owner)
            permit.requireSource(selected.source)
            check(runCatching { permit.requireSource(selected.source.copy(documentId = "foreign")) }.isFailure)
            check(runCatching { permit.requireAdministrative(ReaderDocumentBatchDomain()) }.isFailure)
            val offThread = java.util.concurrent.atomic.AtomicBoolean(false)
            val thread = Thread { offThread.set(runCatching { permit.requireBusiness(owner) }.isFailure) }
            thread.start(); thread.join(1000); check(!thread.isAlive && offThread.get())
            captured = permit; "fixture"
        }, { permit -> permit.requireAdministrative(); ReaderBatchInvalidation.CLEAN }, {}, {}, {})
        check(runCatching { checkNotNull(captured).requireBusiness(owner) }.isFailure)
        check(runCatching { checkNotNull(captured).requireAdministrative() }.isFailure)
        check(registry.isCurrent(owner, selected))
    }

    fun interleave(globalClear: Boolean) {
        val domain = ReaderDocumentBatchDomain()
        val a = LocalWorkspaceReaderPrincipal("w", "epoch", "A", "p", 1, Any()) { true }
        val b = LocalWorkspaceReaderPrincipal("w", "epoch", "B", "p", 1, Any()) { true }
        val ra = ReaderAdmissionRegistry(a, domain); val rb = ReaderAdmissionRegistry(b, domain)
        val source = ExactReaderSource("w", "p", "doc", "1", "pdf", "a".repeat(64))
        val sa = ra.acceptSelection(a, 1, source)
        val entered = CountDownLatch(1); val finish = CountDownLatch(1); val bDone = CountDownLatch(1)
        val events = java.util.Collections.synchronizedList(mutableListOf<String>())
        val failure = AtomicReference<Throwable?>()
        var sb: ReaderSelectionLease? = null
        val ta = Thread {
            try {
                val result = runCatching { ra.runDocumentBatch(a, sa,
                    { events.add("A.operation"); entered.countDown(); check(finish.await(5, TimeUnit.SECONDS)); "A.output" },
                    { events.add("A.drain"); if (globalClear) ReaderBatchInvalidation.CLEAR_ALL else ReaderBatchInvalidation.CLEAN },
                    { error("unexpected selective clear") }, { events.add("A.clear_all") }, { events.add("A.discard_exact") }) }
                check(result.isSuccess != globalClear)
            } catch (error: Throwable) { failure.set(error) }
        }
        val tb = Thread {
            try {
                check(entered.await(5, TimeUnit.SECONDS))
                val result = runCatching {
                    sb = rb.acceptSelection(b, 1, source)
                    rb.runDocumentBatch(b, checkNotNull(sb), { events.add("B.operation"); "B.output" },
                        { events.add("B.drain"); ReaderBatchInvalidation.CLEAN }, {}, {}, {})
                }
                check(result.isSuccess != globalClear)
            } catch (error: Throwable) { failure.set(error) } finally { bDone.countDown() }
        }
        ta.start(); tb.start()
        check(entered.await(5, TimeUnit.SECONDS))
        check(!bDone.await(100, TimeUnit.MILLISECONDS)) // B cannot enter between operation and drain
        finish.countDown(); ta.join(5000); tb.join(5000)
        check(!ta.isAlive && !tb.isAlive); failure.get()?.let { throw it }
        if (globalClear) {
            check("B.operation" !in events && "A.clear_all" in events && "A.discard_exact" in events)
        } else {
            check(events.indexOf("B.operation") > events.indexOf("A.drain"))
            check(!ra.isCurrent(a, sa) && rb.isCurrent(b, checkNotNull(sb)))
            var staleCalls = 0
            check(runCatching { ra.runDocumentBatch(a, sa, { staleCalls++; "late" },
                { staleCalls++; ReaderBatchInvalidation.CLEAR_ALL }, {}, { staleCalls++ }, {}) }.isFailure)
            check(staleCalls == 0 && rb.isCurrent(b, checkNotNull(sb)))
        }
    }
    interleave(false); interleave(true)
    val p = LocalWorkspaceReaderPrincipal("w", "epoch", "A", "p", 1, Any()) { true }
    val domain = ReaderDocumentBatchDomain(); val r = ReaderAdmissionRegistry(p, domain)
    val selection = r.acceptSelection(p, 1, ExactReaderSource("w", "p", "doc", "1", "pdf", "a".repeat(64)))
    var drained = 0; var cleared = 0
    check(runCatching { r.runDocumentBatch(p, selection, { error("simulated stale native callback error") },
        { drained++; ReaderBatchInvalidation.CLEAN }, { cleared++ }, { cleared++ }, {}) }.isFailure)
    check(drained == 1 && cleared == 0 && r.isCurrent(p, selection))
    check(runCatching { r.runDocumentBatch(p, selection, { "owned-result" },
        { drained++; error("simulated administrative transport loss") }, { cleared++ }, { cleared++ }, {}) }.isFailure)
    check(drained == 2 && cleared == 1 && !r.isCurrent(p, selection))
    var alive = true
    val livePrincipal = LocalWorkspaceReaderPrincipal("w", "epoch", "live", "p", 1, Any()) { alive }
    val tailRegistry = ReaderAdmissionRegistry(livePrincipal, ReaderDocumentBatchDomain())
    val tailSelection = tailRegistry.acceptSelection(livePrincipal, 1, ExactReaderSource("w", "p", "doc", "1", "pdf", "a".repeat(64)))
    var exactClears = 0; var exactDiscards = 0
    check(runCatching { tailRegistry.runDocumentBatch(livePrincipal, tailSelection, { alive = false; "new-result" },
        { ReaderBatchInvalidation.CLEAN }, { check(it === tailSelection); exactClears++ }, { error("must not global-clear B") }, { exactDiscards++ }) }.isFailure)
    check(exactClears == 1 && exactDiscards == 1)
    println("PASS reader batch: shared Service domain serializes A op/drain before B; stale A zero calls/no B clear; errors still drain; unknown drain poisons/clears; fixture faults are not native/device evidence")
}
