package com.mightyoung.muyon.product.documents.host

/** Host selection identity only; NOT a native token, grant or presentation. */
internal class ReaderSelectionLease internal constructor(val source: ExactReaderSource, val sequence: Long)
/** Ephemeral in-process native-call admission; never serializable or a grant. */
internal class ReaderNativeBatchPermit internal constructor(
    private val domain: ReaderDocumentBatchDomain, private val owner: LocalWorkspaceReaderPrincipal,
    private val source: ExactReaderSource, private val businessCurrent: () -> Boolean,
) {
    private var thread: Thread? = null
    internal fun enter() { check(thread == null); thread = Thread.currentThread() }
    internal fun exit() { thread = null }
    fun requireAdministrative(expectedDomain: ReaderDocumentBatchDomain = domain) {
        check(expectedDomain === domain && thread === Thread.currentThread() && Thread.holdsLock(domain.lock) && domain.inBatch)
    }
    fun requireSource(expectedSource: ExactReaderSource) { requireAdministrative(); check(source == expectedSource && businessCurrent()) }
    fun requireBusiness(principal: LocalWorkspaceReaderPrincipal, expectedDomain: ReaderDocumentBatchDomain = domain) {
        requireAdministrative(expectedDomain)
        check(owner.sameOwnerScope(principal) && businessCurrent())
    }
}
internal enum class ReaderBatchInvalidation { CLEAN, CURRENT_TERMINAL, CLEAR_ALL }

/** ONE instance per actual Service/native owner, shared by every reader surface.
 * Administrative clear_all has no watermark: operation+drain+publication admission
 * must hold this same lock, including across different Binder owners. */
internal class ReaderDocumentBatchDomain {
    internal val lock = Any()
    internal var active: ReaderAdmissionRegistry? = null
    internal var inBatch = false
    internal var poisoned = false
}

/** Trusted surface event admission, not a policy authorizer. Production callers
 * obtain fresh identity from Service, fresh Activity evidence from its real adapter,
 * and actual native policy separately. No model/JSON route or default allow exists. */
internal class ReaderAdmissionRegistry(private val owner: LocalWorkspaceReaderPrincipal, private val domain: ReaderDocumentBatchDomain) {
    private var current: ReaderSelectionLease? = null
    private var stopped = false
    private fun stopLocal() { stopped = true; current = null; if (domain.active === this) domain.active = null }
    private fun live(): Boolean {
        if (!owner.isLive()) stopLocal()
        return !stopped && !domain.poisoned
    }
    private fun current(principal: LocalWorkspaceReaderPrincipal, selection: ReaderSelectionLease) =
        live() && domain.active === this && owner.sameOwnerScope(principal) && current === selection
    fun acceptSelection(principal: LocalWorkspaceReaderPrincipal, sequence: Long, source: ExactReaderSource): ReaderSelectionLease = synchronized(domain.lock) {
        check(!domain.inBatch && live() && owner.sameOwnerScope(principal))
        require(sequence > 0 && source.workspaceId == owner.workspaceId && source.projectId == owner.projectId)
        current?.let {
            require(sequence >= it.sequence)
            if (sequence == it.sequence) { require(source == it.source); return@synchronized it }
        }
        // Replaced surfaces stay terminal; a delayed old surface cannot reclaim B.
        if (domain.active !== this) domain.active?.stopLocal()
        domain.active = this
        ReaderSelectionLease(source, sequence).also { current = it }
    }
    fun isCurrent(principal: LocalWorkspaceReaderPrincipal, selection: ReaderSelectionLease): Boolean =
        synchronized(domain.lock) { current(principal, selection) }

    /** No check-then-queue gap. Begin/open is provided only by a future real native
     * adapter; it must use5488 native token and original frame, not this Host seq.
     * Drain runs after BOTH success and error. Stale local requests call neither.
     * Renderer publication must later recheck this identity AND actual native frame. */
    fun <T : Any> runDocumentBatch(principal: LocalWorkspaceReaderPrincipal, selection: ReaderSelectionLease,
        operation: () -> T, drain: () -> ReaderBatchInvalidation,
        clearSelectionOutput: (ReaderSelectionLease) -> Unit, clearAllOutputs: () -> Unit,
        discardExactResult: (T) -> Unit): T = synchronized(domain.lock) {
        check(!domain.inBatch && current(principal, selection))
        domain.inBatch = true
        var value: T? = null
        var failed = false
        try {
            try { value = operation() } catch (_: Exception) { failed = true }
            val invalidation = try { drain() } catch (_: Exception) { ReaderBatchInvalidation.CLEAR_ALL }
            try {
                when (invalidation) {
                    ReaderBatchInvalidation.CLEAN -> Unit
                    ReaderBatchInvalidation.CURRENT_TERMINAL -> { stopLocal(); clearSelectionOutput(selection) }
                    ReaderBatchInvalidation.CLEAR_ALL -> {
                        domain.poisoned = true
                        domain.active?.stopLocal()
                        clearAllOutputs()
                    }
                }
            } catch (_: Exception) { domain.poisoned = true; stopLocal(); failed = true }
            val stillCurrent = current(principal, selection)
            if (!stillCurrent && invalidation == ReaderBatchInvalidation.CLEAN) {
                // Identity may expire DURING native work. Clear the original
                // selection while holding the shared batch lock, before B enters.
                try { clearSelectionOutput(selection) }
                catch (_: Exception) { domain.poisoned = true; stopLocal(); failed = true }
            }
            if (failed || !stillCurrent) {
                value?.let { try { discardExactResult(it) } catch (_: Exception) { domain.poisoned = true; stopLocal() } }
                error("reader_batch_unavailable")
            }
            checkNotNull(value)
        } finally { domain.inBatch = false }
    }
    /** The actual generated-binding transport requires this ephemeral permit.
     * Administrative drain remains admitted after scope loss during the operation. */
    fun <T : Any> runNativeDocumentBatch(principal: LocalWorkspaceReaderPrincipal, selection: ReaderSelectionLease,
        operation: (ReaderNativeBatchPermit) -> T, drain: (ReaderNativeBatchPermit) -> ReaderBatchInvalidation,
        clearSelectionOutput: (ReaderSelectionLease) -> Unit, clearAllOutputs: () -> Unit,
        discardExactResult: (T) -> Unit): T {
        val permit = ReaderNativeBatchPermit(domain, owner, selection.source) { current(principal, selection) }
        return try {
            runDocumentBatch(principal, selection, { permit.enter(); operation(permit) }, { drain(permit) },
                clearSelectionOutput, clearAllOutputs, discardExactResult)
        } finally { permit.exit() }
    }
    /** Old callback cannot terminate a newer selection. Never “close current”. */
    fun stopIfCurrent(principal: LocalWorkspaceReaderPrincipal, selection: ReaderSelectionLease): Boolean = synchronized(domain.lock) {
        if (!current(principal, selection)) false else { stopLocal(); true }
    }
    /** Actual owner lifecycle/policy terminal event, not an arbitrary page callback. */
    fun stop() = synchronized(domain.lock) { stopLocal() }
}
