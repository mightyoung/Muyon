package com.mightyoung.muyon.product.chat.persistence

import com.mightyoung.muyon.product.agents.setup.BotSetupDraft
import org.json.JSONObject

/** Private Service port. No model fields or local ownership -> account ACL inference. */
interface ProductLocalDraftPort {
    val verified: Boolean
    fun resolve(conversation: String, project: String?): JSONObject
    fun read(conversation: String, project: String?, namespace: String, draft: String, generation: String, revision: String): JSONObject
    fun prepare(conversation: String, project: String?, namespace: String, draft: String, generation: String, revision: String,
        attempt: String, exportedMemoryRevision: String, hostEditorRevision: String, archive: ByteArray): JSONObject
    fun save(conversation: String, project: String?, namespace: String, draft: String, generation: String, revision: String,
        attempt: String, exportedMemoryRevision: String, archive: ByteArray): JSONObject
    /** Explicit original reconciliation; may atomically fence an uncommitted attempt. */
    fun lookup(conversation: String, project: String?, namespace: String, draft: String, attempt: String): JSONObject
}

data class ReconciledLocalSave(val original: NativeSaveAttempt, val phase: LocalSavePhase, val recovered: Boolean)

/** Serialized mounted editor. Only its exact live export may acknowledge saved.
 * Cold pointer recovery never reconstructs that old reducer identity or dispatches it. */
class HostLocalDraftSession private constructor(private val port: ProductLocalDraftPort, val lease: DraftViewLease,
    private val hostScope: String, private var record: RegisteredLocalDraft, var draft: BotSetupDraft) {
    private var saves = HostDraftSaveState(record, draft, lease)
    var lastOutcome: ReconciledLocalSave? = null
        private set
    private var original: PreparedLocalSave? = null
    private var originalState = "prepared"
    private var recovered: NativeSaveAttempt? = null
    private var knownTerminal: NativeSaveAttempt? = null
    private var archivePresent = false
    private var restoreRequired = false
    companion object {
        fun open(port: ProductLocalDraftPort, lease: DraftViewLease, hostScope: String): HostLocalDraftSession {
            check(port.verified)
            val descriptor = NativeLocalDraftCodec.resolve(port.resolve(lease.conversationId, lease.projectId), lease)
            return HostLocalDraftSession(port, lease, hostScope, descriptor.record,
                BotSetupDraft(hostScope, descriptor.record.draftId)).also {
                it.archivePresent = descriptor.archivePresent; it.restoreRequired = descriptor.archivePresent
                it.recovered = descriptor.saveAttempt // discovery only, no lookup/fence/replay on open
            }
        }
    }
    fun view(localRevision: Long): LocalSaveView {
        recovered?.let { return LocalSaveView(false, false, true, it.attemptId, record.storedRevision) }
        return saves.view(draft, lease, localRevision).let { if (restoreRequired) it.copy(canSave = false) else it }
    }
    fun canRestore() = archivePresent && original == null && recovered == null
    private fun readCurrent(): JSONObject = port.read(lease.conversationId, lease.projectId, record.namespaceId,
        record.draftId, record.registryGeneration.toString(), record.storedRevision.toString())
    /** Resolve validates real current scope; it never performs the mutating outcome
     * lookup. Ordinary open/read/edit must not fence a queued original save. */
    private fun observeDescriptor(current: NativeDraftDescriptor) {
        check(current.record.copy(storedRevision = record.storedRevision) == record)
        val pending = original?.let { NativeLocalDraftCodec.fromExport(it).copy(state = originalState) } ?: recovered
        if (pending != null) {
            val pointer = checkNotNull(current.saveAttempt)
            check(pointer.copy(state = "prepared") == pending.copy(state = "prepared"))
            check(pending.state == "prepared" || pointer.state == pending.state)
            if (original != null) originalState = pointer.state else recovered = pointer
        } else {
            check(current.record == record)
            current.saveAttempt?.let {
                if (it.attemptId == knownTerminal?.attemptId) check(it == knownTerminal)
                else recovered = it
            }
        }
    }
    private fun validatedRead(): JSONObject {
        val value = readCurrent()
        observeDescriptor(NativeLocalDraftCodec.readDescriptor(value, lease))
        return value
    }
    fun revalidate() {
        check(port.verified)
        observeDescriptor(NativeLocalDraftCodec.resolve(port.resolve(lease.conversationId, lease.projectId), lease))
        if (original == null && recovered == null) {
            val value = validatedRead() // read may discover a pointer absent at resolve
            if (original == null && recovered == null) NativeLocalDraftCodec.restore(value, lease, record, hostScope)
        }
    }
    fun restore() {
        check(port.verified)
        revalidate()
        check(canRestore())
        val value = validatedRead()
        check(canRestore()) // a pointer discovered by this read fences restore too
        val restored = checkNotNull(NativeLocalDraftCodec.restore(value, lease, record, hostScope))
        draft = restored.draft
        saves = HostDraftSaveState(record, draft, lease)
        restoreRequired = false
    }
    fun save(localRevision: Long) {
        check(port.verified && !restoreRequired && original == null && recovered == null)
        revalidate()
        check(original == null && recovered == null && !saves.view(draft, lease, localRevision).saved)
        val prepared = saves.prepare(draft, lease, localRevision)
        val checked = BotSetupDraft.restoreDraft(prepared.archive, hostScope, record.draftId)
        check(checked.storedRevision == prepared.storedRevision)
        original = prepared
        originalState = "prepared"
        try {
            // Must await an exact durable preparation acknowledgement first. A throw,
            // malformed reply or foreign binding here means ZERO save dispatches.
            NativeLocalDraftCodec.prepared(port.prepare(lease.conversationId, lease.projectId, record.namespaceId,
                record.draftId, record.registryGeneration.toString(), record.storedRevision.toString(), prepared.attemptId,
                prepared.exportedMemoryRevision.toString(), prepared.exportedLocalRevision.toString(), prepared.archive), lease, prepared)
            val reply = port.save(lease.conversationId, lease.projectId, record.namespaceId, record.draftId,
                record.registryGeneration.toString(), record.storedRevision.toString(), prepared.attemptId,
                prepared.exportedMemoryRevision.toString(), prepared.archive)
            check(reply.opt("status") == "committed_local_storage")
            accept(reply, NativeLocalDraftCodec.fromExport(prepared))
        } catch (_: Exception) {
            saves.observe(prepared.receipt(LocalSavePhase.UNKNOWN))
            throw IllegalStateException("local_draft_original_outcome_required")
        }
    }
    /** Explicit user/host reconciliation. The native lookup is an outcome fence,
     * not a pure read. Never called implicitly by open/read/save/revalidate. */
    fun queryOriginal() {
        check(port.verified)
        val attempt = original?.let { NativeLocalDraftCodec.fromExport(it).copy(state = originalState) } ?: checkNotNull(recovered)
        try {
            accept(port.lookup(lease.conversationId, lease.projectId, attempt.record.namespaceId,
                attempt.record.draftId, attempt.attemptId), attempt)
        } catch (_: Exception) {
            original?.let { saves.observe(it.receipt(LocalSavePhase.UNKNOWN)) }
            throw IllegalStateException("local_draft_original_outcome_required")
        }
    }
    private fun accept(value: JSONObject, attempt: NativeSaveAttempt) {
        val receipt = NativeLocalDraftCodec.outcome(value, lease, attempt)
        val live = original
        if (live != null) {
            check(NativeLocalDraftCodec.fromExport(live) == attempt.copy(state = "prepared"))
            check(saves.observe(receipt))
        } else check(recovered == attempt)
        if (receipt.phase == LocalSavePhase.COMMITTED) {
            record = record.copy(storedRevision = maxOf(record.storedRevision, receipt.storedRevision))
            archivePresent = true
        }
        if (live == null) {
            // Even equal numeric editor/reducer revisions do NOT restore instance
            // identity. Cold result only releases hold; explicit restore stays separate.
            saves = HostDraftSaveState(record, draft, lease)
            restoreRequired = archivePresent
        }
        lastOutcome = ReconciledLocalSave(attempt, receipt.phase, live == null)
        knownTerminal = attempt.copy(state = if (receipt.phase == LocalSavePhase.COMMITTED) "committed" else "not_committed")
        original = null; recovered = null
    }
}
