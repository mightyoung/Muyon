package com.mightyoung.muyon.product.documents.host

/** Retained ACTUAL native owner, never an active UI permission. Created by Service
 * while its original owner exists; lifetime is exact native identity, not scope. */
internal class ReaderAdministrativeOwner internal constructor(
    internal val domain: ReaderDocumentBatchDomain,
    val serviceEpoch: String, val serviceSession: String,
    private val originalClientGone: () -> Boolean,
    private val originalNativeOwnerPresent: () -> Boolean,
) {
    init { require(serviceEpoch.isNotBlank() && serviceSession.isNotBlank()) }
    internal fun requireDisconnected() { check(originalClientGone()) }
    internal fun isRetained() = try { originalNativeOwnerPresent() } catch (_: Exception) { false }
}

/** Separate type: this cannot authorize business, create grants or open bytes. */
internal class ReaderAdministrativePermit internal constructor(private val owner: ReaderAdministrativeOwner) {
    private var thread: Thread? = null
    internal fun enter() { check(thread == null); thread = Thread.currentThread() }
    internal fun exit() { thread = null }
    fun requireDisconnected(expected: ReaderAdministrativeOwner, domain: ReaderDocumentBatchDomain) {
        requireOwner(expected, domain); owner.requireDisconnected()
    }
    fun requireOwner(expected: ReaderAdministrativeOwner, domain: ReaderDocumentBatchDomain) {
        check(expected === owner && owner.domain === domain && thread === Thread.currentThread() &&
            Thread.holdsLock(domain.lock) && domain.inBatch && owner.isRetained())
    }
}

/** Cleanup is admitted after background/scope/Binder release or domain poison.
 * Never reuse withReaderPrincipal/business permit; never reopen current native.
 * Operation failure is UNKNOWN, not success. Drain still runs. Its real global
 * invalidation is routed globally; ordinary old-A cleanup does not stop B. */
internal fun <T : Any> ReaderDocumentBatchDomain.runAdministrativeBatch(owner: ReaderAdministrativeOwner,
    operation: (ReaderAdministrativePermit) -> T, drainNeedsGlobalClear: (ReaderAdministrativePermit) -> Boolean,
    clearAllOutputs: () -> Unit): T = synchronized(lock) {
    check(!inBatch && owner.domain === this && owner.isRetained())
    val permit = ReaderAdministrativePermit(owner)
    inBatch = true; permit.enter()
    var value: T? = null
    var failed = false
    try {
        try { value = operation(permit) } catch (_: Exception) { failed = true }
        val clearAll = try { drainNeedsGlobalClear(permit) } catch (_: Exception) { true }
        if (clearAll) {
            poisoned = true; active?.stop()
            try { clearAllOutputs() } catch (_: Exception) { failed = true }
            failed = true
        }
        if (failed) error("reader_administration_unknown")
        checkNotNull(value)
    } finally { permit.exit(); inBatch = false }
}
