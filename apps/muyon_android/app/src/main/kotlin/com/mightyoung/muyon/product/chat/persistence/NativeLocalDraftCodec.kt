package com.mightyoung.muyon.product.chat.persistence

import com.mightyoung.muyon.product.agents.setup.BotSetupDraft
import com.mightyoung.muyon.product.agents.setup.RestoredBotSetupDraft
import org.json.JSONObject
import java.security.MessageDigest
import java.util.UUID

data class NativeDraftDescriptor(val record: RegisteredLocalDraft, val archivePresent: Boolean)

/** Strict adapter for fixed provider7ca2 schema1. JSON never supplies owner authority;
 * caller has already bound workspace/conversation/project from the live private host. */
object NativeLocalDraftCodec {
    private val fields = setOf("schema", "owner_kind", "namespace_id", "workspace_id", "conversation_id", "project_id",
        "draft_id", "registry_generation", "stored_revision", "lifecycle", "archive_present")
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
    private fun descriptor(value: JSONObject, lease: DraftViewLease, extra: Set<String>): NativeDraftDescriptor {
        require(value.keys().asSequence().toSet() == fields + extra)
        require(value.opt("schema") is Int && value.getInt("schema") == 1)
        require(text(value, "owner_kind") == "local_workspace" && text(value, "lifecycle") == "editing_only")
        require(text(value, "workspace_id") == lease.workspaceId && uuid(text(value, "conversation_id")) == lease.conversationId)
        val project = value.opt("project_id")
        require(project === JSONObject.NULL || project is String)
        require((project as? String) == lease.projectId)
        val generation = number(value, "registry_generation").also { require(it > 0) }
        val present = value.opt("archive_present") as? Boolean ?: error("draft_wire_invalid")
        val storedRevision = number(value, "stored_revision")
        require(present == (storedRevision > 0L))
        return NativeDraftDescriptor(RegisteredLocalDraft(uuid(text(value, "namespace_id")), lease.workspaceId,
            lease.conversationId, lease.projectId, uuid(text(value, "draft_id")), generation, storedRevision,
            LocalDraftLifecycle.EDITING_ONLY), present)
    }
    fun resolve(value: JSONObject, lease: DraftViewLease) = descriptor(value, lease, emptySet())

    fun restore(value: JSONObject, lease: DraftViewLease, expected: RegisteredLocalDraft,
        currentHostScope: String): RestoredBotSetupDraft? {
        val parsed = descriptor(value, lease, setOf("status", "archive_hex", "archive_digest"))
        require(parsed.record == expected)
        if (!parsed.archivePresent) {
            require(text(value, "status") == "not_saved" && parsed.record.storedRevision == 0L &&
                value.opt("archive_hex") === JSONObject.NULL && value.opt("archive_digest") === JSONObject.NULL)
            return null
        }
        require(text(value, "status") == "stored")
        val hex = text(value, "archive_hex")
        require(hex.length in 2..65536 && hex.length % 2 == 0 && hex.all { it in '0'..'9' || it in 'a'..'f' })
        val bytes = ByteArray(hex.length / 2) { hex.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        require(text(value, "archive_digest") == digest)
        return BotSetupDraft.restoreDraft(bytes, currentHostScope, expected.draftId).also {
            require(it.storedRevision == expected.storedRevision)
        }
    }
    fun committed(value: JSONObject, lease: DraftViewLease, original: PreparedLocalSave): LocalSaveReceipt {
        val parsed = descriptor(value, lease, setOf("expected_stored_revision", "attempt_id", "exported_memory_revision", "archive_digest", "status"))
        require(parsed.archivePresent && parsed.record == original.record.copy(storedRevision = original.storedRevision))
        require(text(value, "status") == "committed_local_storage")
        require(number(value, "expected_stored_revision") == original.record.storedRevision)
        require(uuid(text(value, "attempt_id")) == original.attemptId)
        require(number(value, "exported_memory_revision") == original.exportedMemoryRevision)
        require(text(value, "archive_digest") == original.archiveDigest)
        return original.receipt(LocalSavePhase.COMMITTED)
    }
}
