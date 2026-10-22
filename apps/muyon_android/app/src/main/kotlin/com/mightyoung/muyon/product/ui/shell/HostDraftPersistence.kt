package com.mightyoung.muyon.product.ui.shell

import org.json.JSONObject
import java.util.UUID

/** Passive host facts only. This model cannot authorize prepare/save/lookup/restore. */
data class HostSaveOutcome(val status: String, val attempt: String, val expectedStored: Long,
    val proposedStored: Long, val committedStored: Long?, val exportedMemory: Long,
    val hostEditor: Long, val coldRecovered: Boolean, val acknowledgesCurrent: Boolean)
data class HostDraftPersistence(val status: String, val owner: String, val storedRevision: Long?,
    val originalAttempt: String?, val outcome: HostSaveOutcome?, val reportedSaved: Boolean,
    val reportedCanSave: Boolean, val canRestore: Boolean)
internal val persistentSetupOperations = setOf("save", "restore", "query_original_save")

private fun decimal(value: Any?): Long? = (value as? String)?.takeIf {
    it.matches(Regex("0|[1-9][0-9]{0,18}"))
}?.toLongOrNull()?.takeIf { it >= 0 }
private fun canonicalUuid(value: Any?): String? = (value as? String)?.takeIf {
    try { UUID.fromString(it).toString() == it && it != "00000000-0000-0000-0000-000000000000" } catch (_: IllegalArgumentException) { false }
}

fun decodeHostPersistence(data: JSONObject, localRevision: Long, memoryRevision: Long,
    cancelled: Boolean, operations: Set<String>): HostDraftPersistence? {
    val required = setOf("persistence_status", "persistent_owner_status", "stored_revision",
        "original_save_attempt_id", "original_save_outcome", "can_restore", "saved", "can_save")
    if (required.any { !data.has(it) }) return null
    val status = data.opt("persistence_status") as? String ?: return null
    val owner = data.opt("persistent_owner_status") as? String ?: return null
    val saved = data.opt("saved") as? Boolean ?: return null
    val canSave = data.opt("can_save") as? Boolean ?: return null
    val canRestore = data.opt("can_restore") as? Boolean ?: return null
    val stored = if (data.isNull("stored_revision")) null else decimal(data.opt("stored_revision")) ?: return null
    val attempt = if (data.isNull("original_save_attempt_id")) null else canonicalUuid(data.opt("original_save_attempt_id")) ?: return null
    val outcome = if (data.isNull("original_save_outcome")) null else {
        val raw = data.optJSONObject("original_save_outcome") ?: return null
        val keys = setOf("status", "attempt_id", "expected_stored_revision", "proposed_stored_revision",
            "committed_stored_revision", "exported_memory_revision", "host_editor_revision", "historical",
            "cold_recovered", "acknowledges_current_editor")
        if (raw.keys().asSequence().toSet() != keys || raw.opt("historical") != true) return null
        val phase = raw.opt("status") as? String ?: return null
        val original = canonicalUuid(raw.opt("attempt_id")) ?: return null
        val base = decimal(raw.opt("expected_stored_revision")) ?: return null
        val proposed = decimal(raw.opt("proposed_stored_revision")) ?: return null
        val committed = if (raw.isNull("committed_stored_revision")) null else decimal(raw.opt("committed_stored_revision")) ?: return null
        val memory = decimal(raw.opt("exported_memory_revision")) ?: return null
        val editor = decimal(raw.opt("host_editor_revision")) ?: return null
        val cold = raw.opt("cold_recovered") as? Boolean ?: return null
        val acknowledges = raw.opt("acknowledges_current_editor") as? Boolean ?: return null
        if (base == Long.MAX_VALUE || proposed != base + 1 || stored == null || base > stored) return null
        when (phase) {
            "committed_local_storage" -> if (committed != proposed || committed > stored) return null
            "not_committed_local_storage" -> if (committed != null || acknowledges) return null
            else -> return null
        }
        if (acknowledges && (cold || cancelled || phase != "committed_local_storage" || committed != stored ||
                memory != memoryRevision || editor != localRevision || attempt != null)) return null
        HostSaveOutcome(phase, original, base, proposed, committed, memory, editor, cold, acknowledges)
    }
    if (attempt != null && outcome?.attempt == attempt) return null // one original cannot be both pending and terminal
    if (canRestore && (stored == null || stored == 0L)) return null
    if (canSave != ("save" in operations) || canRestore != ("restore" in operations)) return null
    when (status) {
        "unavailable" -> if (owner != "unavailable" || stored != null || attempt != null || outcome != null ||
            saved || canSave || canRestore || operations.any { it in persistentSetupOperations }) return null
        "editing", "unknown", "saved" -> {
            if (owner != "local_workspace" || stored == null || canonicalUuid(data.opt("local_draft_id")) == null) return null
            if ((status == "unknown") != (attempt != null) || ("query_original_save" in operations) != (attempt != null && !cancelled)) return null
            if (attempt != null && (canSave || canRestore || saved)) return null
            if (saved != (status == "saved") || saved != (outcome?.acknowledgesCurrent == true)) return null
            if (saved && (canSave || cancelled)) return null
        }
        else -> return null
    }
    return HostDraftPersistence(status, owner, stored, attempt, outcome, saved, canSave, canRestore)
}

/** Storage-only observations may change at one memory CAS; editing content remains immutable. */
fun acceptsHostStorageObservation(old: HostSetupSnapshot, next: HostSetupSnapshot): Boolean {
    val left = old.persistence
    val right = next.persistence
    if (left.owner != right.owner || (left.storedRevision != null &&
            (right.storedRevision == null || right.storedRevision < left.storedRevision))) return false
    if (left.originalAttempt != null && right.originalAttempt != left.originalAttempt &&
        (right.originalAttempt != null || right.outcome?.attempt != left.originalAttempt)) return false
    val previous = left.outcome
    val observed = right.outcome
    if (previous != null && observed == null) return false
    if (previous != null && observed?.attempt == previous.attempt &&
        previous.copy(acknowledgesCurrent = false) != observed.copy(acknowledgesCurrent = false)) return false
    if (old.revision == next.revision) {
        return old.copy(persistence = next.persistence, operations = old.operations - persistentSetupOperations) ==
            next.copy(operations = next.operations - persistentSetupOperations)
    }
    return true
}

fun visibleEditorSaved(snapshot: HostSetupSnapshot, name: String, purpose: String, role: String): Boolean =
    snapshot.persistence.reportedSaved && snapshot.persistence.outcome?.acknowledgesCurrent == true &&
        name == snapshot.name && purpose == snapshot.purpose && role == snapshot.role

fun hostPersistenceMessages(snapshot: HostSetupSnapshot, name: String, purpose: String, role: String): List<String> {
    val storage = snapshot.persistence
    return buildList {
        add(when (storage.status) {
            "unavailable" -> "持久保存暂不可用；当前仅内存草稿。"
            "unknown" -> "原保存结果待核查；不会自动重试。"
            "saved" -> if (visibleEditorSaved(snapshot, name, purpose, role)) "当前编辑已由宿主确认保存。"
                else "宿主已确认草稿版本；未提交文本尚未保存。"
            else -> "当前编辑尚未确认保存。"
        })
        storage.storedRevision?.let { add(if (it == 0L) "尚无已提交存储版本。" else "已知存储版本：$it") }
        storage.originalAttempt?.let { add("待核查原保存：$it") }
        storage.outcome?.let {
            add(if (it.status == "committed_local_storage") "历史保存结果：已提交至本机存储（版本 ${it.committedStored}）。"
                else "历史保存结果：已确认未提交；计划版本 ${it.proposedStored} 不代表已保存。")
            if (it.coldRecovered) add("冷恢复历史仅供核对，不代表当前编辑已保存。")
        }
    }
}
