package com.mightyoung.muyon.product.chat.persistence

import com.mightyoung.muyon.product.agents.setup.BotSetupDraft
import org.json.JSONObject

/** Private Service port. Arguments come from the current host lease/registry,
 * never model fields. Verification is a release gate, not a native success claim. */
interface ProductLocalDraftPort {
    val verified: Boolean
    fun resolve(conversation: String, project: String?): JSONObject
    fun read(conversation: String, project: String?, namespace: String, draft: String, generation: String, revision: String): JSONObject
    fun save(conversation: String, project: String?, namespace: String, draft: String, generation: String, revision: String,
        attempt: String, exportedMemoryRevision: String, archive: ByteArray): JSONObject
    fun lookup(conversation: String, project: String?, namespace: String, draft: String, attempt: String): JSONObject
}

/** One mounted editor. Unknown results retain the original export and attempt;
 * reopening is not receipt recovery. No account ACL or execution authority. */
class HostLocalDraftSession private constructor(private val port: ProductLocalDraftPort, val lease: DraftViewLease,
    private val hostScope: String, private var record: RegisteredLocalDraft, var draft: BotSetupDraft) {
    private var saves = HostDraftSaveState(record, draft, lease)
    private var original: PreparedLocalSave? = null
    private var archivePresent = false
    private var restoreRequired = false
    companion object {
        fun open(port: ProductLocalDraftPort, lease: DraftViewLease, hostScope: String): HostLocalDraftSession {
            check(port.verified)
            val descriptor = NativeLocalDraftCodec.resolve(port.resolve(lease.conversationId, lease.projectId), lease)
            return HostLocalDraftSession(port, lease, hostScope, descriptor.record,
                BotSetupDraft(hostScope, descriptor.record.draftId)).also { it.archivePresent = descriptor.archivePresent; it.restoreRequired = descriptor.archivePresent }
        }
    }
    fun view(localRevision: Long) = saves.view(draft, lease, localRevision).let { if (restoreRequired) it.copy(canSave = false) else it }
    fun canRestore() = archivePresent && original == null
    private fun readCurrent(): JSONObject = port.read(lease.conversationId, lease.projectId, record.namespaceId,
        record.draftId, record.registryGeneration.toString(), record.storedRevision.toString())
    /** Before displaying or editing a mounted persistent snapshot, recheck the
     * real project/registry. An outstanding save can only query its original. */
    fun revalidate() {
        check(port.verified)
        val prepared = original
        if (prepared == null) NativeLocalDraftCodec.restore(readCurrent(), lease, record, hostScope)
        else accept(port.lookup(lease.conversationId, lease.projectId, prepared.record.namespaceId,
            prepared.record.draftId, prepared.attemptId), prepared)
    }
    fun restore() {
        check(port.verified && canRestore())
        val restored = checkNotNull(NativeLocalDraftCodec.restore(readCurrent(), lease, record, hostScope))
        draft = restored.draft
        saves = HostDraftSaveState(record, draft, lease)
        restoreRequired = false
    }
    fun save(localRevision: Long) {
        check(port.verified && !restoreRequired)
        if (original != null) { queryOriginal(); return }
        // Revalidate live native workspace/project/registry and canonical semantics
        // before exporting or dispatching. This read does not overwrite the editor.
        NativeLocalDraftCodec.restore(readCurrent(), lease, record, hostScope)
        val prepared = saves.prepare(draft, lease, localRevision)
        // Validate the complete canonical archive, not merely Rust's frame/hash.
        val checked = BotSetupDraft.restoreDraft(prepared.archive, hostScope, record.draftId)
        check(checked.storedRevision == prepared.storedRevision)
        original = prepared
        try {
            accept(port.save(lease.conversationId, lease.projectId, record.namespaceId, record.draftId,
                record.registryGeneration.toString(), record.storedRevision.toString(), prepared.attemptId,
                prepared.exportedMemoryRevision.toString(), prepared.archive), prepared)
        } catch (_: Exception) {
            // A throw or malformed reply after dispatch cannot prove rollback.
            saves.observe(prepared.receipt(LocalSavePhase.UNKNOWN))
            throw IllegalStateException("local_draft_original_outcome_required")
        }
    }
    fun queryOriginal() {
        check(port.verified)
        val prepared = checkNotNull(original)
        try {
            accept(port.lookup(lease.conversationId, lease.projectId, prepared.record.namespaceId,
                prepared.record.draftId, prepared.attemptId), prepared)
        } catch (_: Exception) {
            saves.observe(prepared.receipt(LocalSavePhase.UNKNOWN))
            throw IllegalStateException("local_draft_original_outcome_required")
        }
    }
    private fun accept(value: JSONObject, prepared: PreparedLocalSave) {
        val receipt = NativeLocalDraftCodec.committed(value, lease, prepared)
        check(saves.observe(receipt))
        record = record.copy(storedRevision = receipt.storedRevision)
        archivePresent = true
        original = null
    }
}
