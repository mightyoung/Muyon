package com.mightyoung.muyon.product.chat.persistence

import com.mightyoung.muyon.product.agents.setup.BotSetupDraft
import com.mightyoung.muyon.product.agents.setup.CreationStatus
import java.security.MessageDigest
import java.util.UUID

/** Live view lease only; never persisted as owner identity. */
data class DraftViewLease(val workspaceId: String, val conversationId: String, val projectId: String?, val sessionId: String, val generation: Long)
enum class LocalDraftLifecycle { EDITING_ONLY, BLOCKED }
/** Normalized trusted local_workspace descriptor. No wire/API parser is assumed here. */
data class RegisteredLocalDraft(val namespaceId: String, val workspaceId: String, val conversationId: String,
    val projectId: String?, val draftId: String, val registryGeneration: Long, val storedRevision: Long, val lifecycle: LocalDraftLifecycle)
enum class LocalSavePhase { COMMITTED, REJECTED, UNKNOWN }
data class LocalSaveReceipt(val namespaceId: String, val workspaceId: String, val conversationId: String,
    val projectId: String?, val draftId: String, val registryGeneration: Long, val attemptId: String,
    val storedRevision: Long, val exportedMemoryRevision: Long, val archiveDigest: String, val phase: LocalSavePhase)
class PreparedLocalSave internal constructor(val record: RegisteredLocalDraft, val attemptId: String,
    val storedRevision: Long, val exportedMemoryRevision: Long, val exportedLocalRevision: Long, archive: ByteArray) {
    private val bytes = archive.copyOf()
    val archive: ByteArray get() = bytes.copyOf()
    val archiveDigest: String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    /** Pure normalization helper, not a receipt producer or authorization. */
    fun receipt(phase: LocalSavePhase) = LocalSaveReceipt(record.namespaceId, record.workspaceId,
        record.conversationId, record.projectId, record.draftId, record.registryGeneration,
        attemptId, storedRevision, exportedMemoryRevision, archiveDigest, phase)
}
data class LocalSaveView(val saved: Boolean, val canSave: Boolean, val queryOriginalOnly: Boolean,
    val originalAttemptId: String?, val storedRevision: Long?)

/** Serialized local consumer, not connected to Service until the fixed Rust bridge exists.
 * Receipt inputs must come from the trusted adapter, never rendered/model JSON.
 * A receipt acknowledges an export, never permission or current backend lifecycle. */
class HostDraftSaveState(private val record: RegisteredLocalDraft, private val reducer: BotSetupDraft,
    private val lease: DraftViewLease) {
    private var storedRevision = record.storedRevision
    private var pending: PreparedLocalSave? = null
    private var unknown = false
    private var lastCommitted: LocalSaveReceipt? = null
    private var acknowledgedLocalRevision: Long? = null
    init {
        require(record.lifecycle == LocalDraftLifecycle.EDITING_ONLY)
        require(listOfNotNull(record.namespaceId, record.workspaceId, record.conversationId, record.projectId,
            record.draftId, lease.sessionId).all { it.isNotBlank() && it.length <= 1024 })
        require(record.registryGeneration >= 0 && record.storedRevision >= 0 && lease.generation >= 0)
        require(matches(reducer, lease))
    }
    private fun matches(draft: BotSetupDraft, current: DraftViewLease) = draft === reducer && current == lease &&
        record.draftId == draft.snapshot().draftId && record.workspaceId == current.workspaceId &&
        record.conversationId == current.conversationId && record.projectId == current.projectId
    private fun editable() = reducer.snapshot().creation.status in setOf(CreationStatus.NOT_REQUESTED, CreationStatus.REJECTED)

    @Synchronized fun prepare(draft: BotSetupDraft, current: DraftViewLease, localRevision: Long): PreparedLocalSave {
        require(matches(draft, current) && localRevision >= 0 && editable())
        pending?.let { return it } // unknown/duplicate keeps exact original, never exports latest
        require(storedRevision < Long.MAX_VALUE)
        val snapshot = reducer.snapshot()
        val next = Math.addExact(storedRevision, 1L)
        val archive = reducer.exportDraft(next, snapshot.revision)
        return PreparedLocalSave(record.copy(storedRevision = storedRevision), UUID.randomUUID().toString(), next,
            snapshot.revision, localRevision, archive).also { pending = it; unknown = false }
    }
    @Synchronized fun observe(receipt: LocalSaveReceipt): Boolean {
        // Duplicate history may acknowledge itself but must never clear a newer attempt.
        if (receipt == lastCommitted) return true
        val original = pending ?: return false
        if (receipt.copy(phase = LocalSavePhase.COMMITTED) != original.receipt(LocalSavePhase.COMMITTED)) return false
        when (receipt.phase) {
            LocalSavePhase.UNKNOWN -> unknown = true
            LocalSavePhase.REJECTED -> { pending = null; unknown = false }
            LocalSavePhase.COMMITTED -> {
                storedRevision = receipt.storedRevision
                acknowledgedLocalRevision = original.exportedLocalRevision
                lastCommitted = receipt
                pending = null; unknown = false
            }
        }
        return true
    }
    @Synchronized fun view(draft: BotSetupDraft, current: DraftViewLease, localRevision: Long): LocalSaveView {
        val mounted = matches(draft, current) && localRevision >= 0
        val saved = mounted && editable() && lastCommitted?.exportedMemoryRevision == reducer.snapshot().revision &&
            acknowledgedLocalRevision == localRevision
        return LocalSaveView(saved, mounted && pending == null && editable() && storedRevision < Long.MAX_VALUE,
            mounted && unknown, if (mounted) pending?.attemptId else null, if (mounted) storedRevision else null)
    }
}
