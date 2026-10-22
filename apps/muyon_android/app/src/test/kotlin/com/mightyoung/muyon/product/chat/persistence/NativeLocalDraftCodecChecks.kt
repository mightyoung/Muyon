package com.mightyoung.muyon.product.chat.persistence

import com.mightyoung.muyon.product.agents.setup.BotSetupDraft
import org.json.JSONObject

fun main() {
    val lease = DraftViewLease("workspace", "084847dc-b08c-45e5-8391-93fcc2b3ba2c", "project", "session", 2)
    val base = JSONObject().put("schema", 1).put("owner_kind", "local_workspace")
        .put("namespace_id", "9369e56d-f3ba-4ab9-b5bd-ed26285c60e6").put("workspace_id", lease.workspaceId)
        .put("conversation_id", lease.conversationId).put("project_id", lease.projectId)
        .put("draft_id", "868cbac8-4d86-4f0d-91cd-324f8cc80d33").put("registry_generation", "1")
        .put("stored_revision", "0").put("lifecycle", "editing_only").put("archive_present", false).put("save_attempt", JSONObject.NULL)
    fun copy() = JSONObject(base.toString())
    val descriptor = NativeLocalDraftCodec.resolve(base, lease)
    listOf(copy().put("schema", 1.0), copy().put("owner_kind", "account"), copy().put("workspace_id", "foreign"),
        copy().put("registry_generation", "0"), copy().put("stored_revision", "9223372036854775808"),
        copy().put("project_id", "foreign"), copy().put("lifecycle", "pending_creation"), copy().put("account_id", "fake"),
        copy().put("archive_present", "false"), copy().put("archive_present", true), copy().put("stored_revision", "1")).forEach { check(runCatching { NativeLocalDraftCodec.resolve(it, lease) }.isFailure) }
    val blank = copy().put("status", "not_saved").put("archive_hex", JSONObject.NULL).put("archive_digest", JSONObject.NULL)
    check(NativeLocalDraftCodec.restore(blank, lease, descriptor.record, "current-live-scope") == null)
    val draft = BotSetupDraft("current-live-scope", descriptor.record.draftId)
    draft.editName("仅编辑数据")
    val state = HostDraftSaveState(descriptor.record, draft, lease)
    val prepared = state.prepare(draft, lease, 3)
    check(prepared.storedRevision == 1L && prepared.exportedMemoryRevision == 1L)
    val pointer = JSONObject().put("schema", 1).put("owner_kind", "local_workspace")
        .put("namespace_id", descriptor.record.namespaceId).put("workspace_id", lease.workspaceId)
        .put("conversation_id", lease.conversationId).put("project_id", lease.projectId).put("draft_id", descriptor.record.draftId)
        .put("registry_generation", "1").put("expected_stored_revision", "0").put("next_stored_revision", "1")
        .put("attempt_id", prepared.attemptId).put("exported_memory_revision", "1").put("host_editor_revision", "3")
        .put("archive_digest", prepared.archiveDigest).put("state", "prepared")
    check(NativeLocalDraftCodec.prepared(pointer, lease, prepared) == NativeLocalDraftCodec.fromExport(prepared))
    listOf("namespace_id" to "9369e56d-f3ba-4ab9-b5bd-ed26285c60e7", "project_id" to "foreign",
        "host_editor_revision" to "4", "exported_memory_revision" to "2", "next_stored_revision" to "2",
        "archive_digest" to "0".repeat(64), "state" to "committed", "unexpected" to "field").forEach { (key, value) ->
        check(runCatching { NativeLocalDraftCodec.prepared(JSONObject(pointer.toString()).put(key, value), lease, prepared) }.isFailure)
    }
    check(NativeLocalDraftCodec.resolve(copy().put("save_attempt", pointer), lease).saveAttempt!!.attemptId == prepared.attemptId)
    check(runCatching { NativeLocalDraftCodec.resolve(copy().put("save_attempt", JSONObject(pointer.toString()).put("state", "committed")), lease) }.isFailure)
    val fenced = JSONObject(pointer.toString()).put("state", "not_committed").put("status", "not_committed_local_storage")
    check(NativeLocalDraftCodec.outcome(fenced, lease, NativeLocalDraftCodec.fromExport(prepared)).phase == LocalSavePhase.REJECTED)
    check(runCatching { NativeLocalDraftCodec.outcome(JSONObject(fenced.toString()).put("status", "attempt_not_found"), lease,
        NativeLocalDraftCodec.fromExport(prepared)) }.isFailure)
    val receipt = copy().also { it.remove("save_attempt") }.put("archive_present", true).put("stored_revision", "1").put("expected_stored_revision", "0")
        .put("attempt_id", prepared.attemptId).put("exported_memory_revision", "1").put("host_editor_revision", "3").put("archive_digest", prepared.archiveDigest)
        .put("status", "committed_local_storage")
    check(runCatching { NativeLocalDraftCodec.outcome(fenced, lease,
        NativeLocalDraftCodec.fromExport(prepared).copy(state = "committed")) }.isFailure)
    check(runCatching { NativeLocalDraftCodec.outcome(receipt, lease,
        NativeLocalDraftCodec.fromExport(prepared).copy(state = "not_committed")) }.isFailure)
    check(state.observe(NativeLocalDraftCodec.committed(receipt, lease, prepared)))
    check(state.view(draft, lease, 3).saved)
    val mismatched = JSONObject(receipt.toString()).put("exported_memory_revision", "2")
    check(runCatching { NativeLocalDraftCodec.committed(mismatched, lease, prepared) }.isFailure)
    val stored = copy().put("stored_revision", "1").put("archive_present", true).put("status", "stored")
        .put("archive_hex", prepared.archive.joinToString("") { "%02x".format(it) }).put("archive_digest", prepared.archiveDigest)
    val restored = NativeLocalDraftCodec.restore(stored, lease, descriptor.record.copy(storedRevision = 1), "new-live-scope")!!
    check(restored.storedRevision == 1L && restored.draft.snapshot().revision == 0L)
    check(restored.draft.snapshot().name.value == "仅编辑数据" && restored.draft.snapshot().creation.intentId == null)
    check(runCatching { NativeLocalDraftCodec.restore(stored, lease, descriptor.record, "new-live-scope") }.isFailure)
    check(runCatching { NativeLocalDraftCodec.restore(JSONObject(stored.toString()).put("archive_digest", "0".repeat(64)), lease,
        descriptor.record.copy(storedRevision = 1), "new-live-scope") }.isFailure)
    println("PASS fixed native codec: schema/owner/scope/Long bounds/lifecycle/real original receipt/canonical restore; no backend calls")
}
