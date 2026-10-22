package com.mightyoung.muyon.product.chat.persistence

import com.mightyoung.muyon.product.agents.setup.BotSetupDraft
import com.mightyoung.muyon.product.agents.setup.RestoredBotSetupDraft
import org.json.JSONObject
import java.security.MessageDigest
import java.util.UUID

data class NativeSaveAttempt(val record: RegisteredLocalDraft, val attemptId: String, val nextStoredRevision: Long,
    val exportedMemoryRevision: Long, val hostEditorRevision: Long, val archiveDigest: String, val state: String)
data class NativeDraftDescriptor(val record: RegisteredLocalDraft, val archivePresent: Boolean, val saveAttempt: NativeSaveAttempt?)

/** Fixed five-method schema. JSON never supplies owner authority: live host scope
 * and real provider identity must already match. No legacy receipt is re-bound. */
object NativeLocalDraftCodec {
    private val common = setOf("schema", "owner_kind", "namespace_id", "workspace_id", "conversation_id", "project_id", "draft_id", "registry_generation")
    private val descriptorFields = common + setOf("stored_revision", "lifecycle", "archive_present")
    private val attemptFields = common + setOf("attempt_id", "expected_stored_revision", "next_stored_revision", "exported_memory_revision", "host_editor_revision", "archive_digest", "state")
    private fun text(value: JSONObject, key: String) = value.opt(key) as? String ?: error("draft_wire_invalid")
    private fun number(value: JSONObject, key: String): Long {
        val raw = text(value, key)
        require(raw.matches(Regex("0|[1-9][0-9]{0,18}")))
        return requireNotNull(raw.toLongOrNull()).also { require(it >= 0) }
    }
    private fun uuid(raw: String): String {
        require(UUID.fromString(raw).toString() == raw && raw != "00000000-0000-0000-0000-000000000000")
        return raw
    }
    private fun digest(value: JSONObject) = text(value, "archive_digest").also { require(it.matches(Regex("[0-9a-f]{64}"))) }
    private fun owner(value: JSONObject, lease: DraftViewLease, revision: Long): RegisteredLocalDraft {
        require(value.opt("schema") is Int && value.getInt("schema") == 1 && text(value, "owner_kind") == "local_workspace")
        require(text(value, "workspace_id") == lease.workspaceId && uuid(text(value, "conversation_id")) == lease.conversationId)
        val project = value.opt("project_id")
        require(project === JSONObject.NULL || project is String)
        require((project as? String) == lease.projectId)
        return RegisteredLocalDraft(uuid(text(value, "namespace_id")), lease.workspaceId, lease.conversationId, lease.projectId,
            uuid(text(value, "draft_id")), number(value, "registry_generation").also { require(it > 0) }, revision, LocalDraftLifecycle.EDITING_ONLY)
    }
    private fun descriptor(value: JSONObject, lease: DraftViewLease, extra: Set<String>, pointer: Boolean): NativeDraftDescriptor {
        require(value.keys().asSequence().toSet() == descriptorFields + extra + if (pointer) setOf("save_attempt") else emptySet())
        require(text(value, "lifecycle") == "editing_only")
        val stored = number(value, "stored_revision")
        val present = value.opt("archive_present") as? Boolean ?: error("draft_wire_invalid")
        require(present == (stored > 0L))
        val record = owner(value, lease, stored)
        val attempt = if (pointer && value.opt("save_attempt") !== JSONObject.NULL)
            attempt(value.getJSONObject("save_attempt"), lease) else null
        if (attempt != null) {
            require(attempt.record.copy(storedRevision = stored) == record && attempt.record.storedRevision <= stored)
            require(attempt.state != "prepared" || attempt.record.storedRevision == stored)
            require(attempt.state != "committed" || attempt.nextStoredRevision <= stored)
        }
        return NativeDraftDescriptor(record, present, attempt)
    }
    fun resolve(value: JSONObject, lease: DraftViewLease) = descriptor(value, lease, emptySet(), true)
    fun readDescriptor(value: JSONObject, lease: DraftViewLease) = descriptor(value, lease, setOf("status", "archive_hex", "archive_digest"), true)
    private fun attempt(value: JSONObject, lease: DraftViewLease, extra: Set<String> = emptySet()): NativeSaveAttempt {
        require(value.keys().asSequence().toSet() == attemptFields + extra)
        val base = number(value, "expected_stored_revision")
        val next = number(value, "next_stored_revision")
        require(base < Long.MAX_VALUE && next == base + 1)
        val state = text(value, "state").also { require(it in setOf("prepared", "committed", "not_committed")) }
        return NativeSaveAttempt(owner(value, lease, base), uuid(text(value, "attempt_id")), next,
            number(value, "exported_memory_revision"), number(value, "host_editor_revision"), digest(value), state)
    }
    fun fromExport(original: PreparedLocalSave) = NativeSaveAttempt(original.record, original.attemptId, original.storedRevision,
        original.exportedMemoryRevision, original.exportedLocalRevision, original.archiveDigest, "prepared")
    private fun sameBinding(left: NativeSaveAttempt, right: NativeSaveAttempt) = left.copy(state = "prepared") == right.copy(state = "prepared")
    fun prepared(value: JSONObject, lease: DraftViewLease, original: PreparedLocalSave): NativeSaveAttempt = attempt(value, lease).also {
        require(it.state == "prepared" && it == fromExport(original))
    }
    fun restore(value: JSONObject, lease: DraftViewLease, expected: RegisteredLocalDraft, currentHostScope: String): RestoredBotSetupDraft? {
        val parsed = readDescriptor(value, lease)
        require(parsed.record == expected)
        if (!parsed.archivePresent) {
            require(text(value, "status") == "not_saved" && expected.storedRevision == 0L &&
                value.opt("archive_hex") === JSONObject.NULL && value.opt("archive_digest") === JSONObject.NULL)
            return null
        }
        require(text(value, "status") == "stored")
        val hex = text(value, "archive_hex")
        require(hex.length in 2..65536 && hex.length % 2 == 0 && hex.all { it in '0'..'9' || it in 'a'..'f' })
        val bytes = ByteArray(hex.length / 2) { hex.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
        val actual = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        require(digest(value) == actual)
        return BotSetupDraft.restoreDraft(bytes, currentHostScope, expected.draftId).also { require(it.storedRevision == expected.storedRevision) }
    }
    fun outcome(value: JSONObject, lease: DraftViewLease, original: NativeSaveAttempt): LocalSaveReceipt {
        val phase = if (text(value, "status") == "not_committed_local_storage") {
            val terminal = attempt(value, lease, setOf("status"))
            require(terminal.state == "not_committed" && sameBinding(terminal, original))
            LocalSavePhase.REJECTED // definite native outcome fence, never a missing-receipt inference
        } else {
            val parsed = descriptor(value, lease, setOf("expected_stored_revision", "attempt_id", "exported_memory_revision", "host_editor_revision", "archive_digest", "status"), false)
            require(text(value, "status") == "committed_local_storage" && parsed.archivePresent)
            require(parsed.record == original.record.copy(storedRevision = original.nextStoredRevision))
            require(number(value, "expected_stored_revision") == original.record.storedRevision && uuid(text(value, "attempt_id")) == original.attemptId)
            require(number(value, "exported_memory_revision") == original.exportedMemoryRevision && number(value, "host_editor_revision") == original.hostEditorRevision)
            require(digest(value) == original.archiveDigest)
            LocalSavePhase.COMMITTED
        }
        require(original.state == "prepared" || original.state == "committed" && phase == LocalSavePhase.COMMITTED ||
            original.state == "not_committed" && phase == LocalSavePhase.REJECTED)
        return LocalSaveReceipt(original.record.namespaceId, original.record.workspaceId, original.record.conversationId,
            original.record.projectId, original.record.draftId, original.record.registryGeneration, original.attemptId,
            original.nextStoredRevision, original.exportedMemoryRevision, original.archiveDigest, phase)
    }
    fun committed(value: JSONObject, lease: DraftViewLease, original: PreparedLocalSave): LocalSaveReceipt =
        outcome(value, lease, fromExport(original)).also { require(it.phase == LocalSavePhase.COMMITTED) }
}
