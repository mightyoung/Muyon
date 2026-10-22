package com.mightyoung.muyon.product.chat.persistence

import com.mightyoung.muyon.product.agents.setup.BotSetupDraft

fun main() {
    val lease = DraftViewLease("workspace", "conversation", "project", "binder-session", 4)
    val record = RegisteredLocalDraft("registered-namespace", "workspace", "conversation", "project", "registered-draft", 2, 0, LocalDraftLifecycle.EDITING_ONLY)
    val draft = BotSetupDraft("live-scope", record.draftId)
    draft.editName("原编辑")
    val state = HostDraftSaveState(record, draft, lease)
    val a = state.prepare(draft, lease, 1)
    check(state.prepare(draft, lease, 1).attemptId == a.attemptId) // duplicate retains exact original
    check(!state.view(draft, lease, 1).saved && !state.view(draft, lease, 1).canSave)
    val body = a.archive; body.fill(0)
    check(a.archive.any { it != 0.toByte() }) // output cannot corrupt retained original
    check(!state.observe(a.receipt(LocalSavePhase.COMMITTED).copy(draftId = "foreign")))
    check(!state.observe(a.receipt(LocalSavePhase.COMMITTED).copy(storedRevision = 99)))
    val valid = a.receipt(LocalSavePhase.COMMITTED)
    listOf(valid.copy(namespaceId = "other"), valid.copy(workspaceId = "other"),
        valid.copy(conversationId = "other"), valid.copy(projectId = null), valid.copy(registryGeneration = 3),
        valid.copy(attemptId = "other"), valid.copy(exportedMemoryRevision = 77), valid.copy(archiveDigest = "wrong")).forEach {
        check(!state.observe(it))
    }
    draft.editName("较新编辑")
    check(state.observe(a.receipt(LocalSavePhase.COMMITTED)))
    check(!state.view(draft, lease, 2).saved) // late ack never acknowledges newer editing
    check(state.view(draft, lease, 2).storedRevision == 1L)
    val b = state.prepare(draft, lease, 2)
    check(b.attemptId != a.attemptId && b.storedRevision == 2L)
    check(state.observe(a.receipt(LocalSavePhase.COMMITTED))) // duplicate A cannot mutate B
    check(state.view(draft, lease, 2).originalAttemptId == b.attemptId)
    check(state.observe(b.receipt(LocalSavePhase.UNKNOWN)))
    check(state.prepare(draft, lease, 2).attemptId == b.attemptId)
    check(state.view(draft, lease, 2).queryOriginalOnly)
    check(!state.view(draft, lease.copy(generation = 5), 2).canSave)
    check(!state.view(draft, lease.copy(conversationId = "other"), 2).saved)
    listOf(lease.copy(workspaceId = "other"), lease.copy(sessionId = "other"), lease.copy(projectId = null)).forEach {
        val foreign = state.view(draft, it, 2)
        check(!foreign.saved && !foreign.canSave && !foreign.queryOriginalOnly && foreign.originalAttemptId == null && foreign.storedRevision == null)
    }
    check(!state.view(BotSetupDraft("new-instance", record.draftId), lease, 2).saved)
    check(state.observe(b.receipt(LocalSavePhase.COMMITTED)))
    check(state.view(draft, lease, 2).saved)
    check(!state.view(draft, lease, 3).saved) // local view generation is also captured
    val c = state.prepare(draft, lease, 3)
    check(state.observe(c.receipt(LocalSavePhase.REJECTED)))
    check(state.view(draft, lease, 3).canSave && !state.view(draft, lease, 3).saved)
    val wrong = lease.copy(projectId = "foreign")
    check(runCatching { state.prepare(draft, wrong, 3) }.isFailure)
    check(runCatching { HostDraftSaveState(record.copy(draftId = "wrong"), draft, lease) }.isFailure)
    check(runCatching { HostDraftSaveState(record.copy(lifecycle = LocalDraftLifecycle.BLOCKED), draft, lease) }.isFailure)
    val exhausted = HostDraftSaveState(record.copy(storedRevision = Long.MAX_VALUE), draft, lease)
    check(runCatching { exhausted.prepare(draft, lease, 3) }.isFailure)
    check(!exhausted.view(draft, lease, 3).canSave)
    val restore = BotSetupDraft.restoreDraft(b.archive, "new-live-scope", record.draftId)
    check(restore.draft.snapshot().draftId == record.draftId && restore.draft.snapshot().revision == 0L)
    check(restore.draft.snapshot().name.value == "较新编辑" && restore.draft.choices().selectedCapabilityIds.isEmpty())
    check(restore.draft.snapshot().creation.intentId == null && restore.draft.snapshot().suggestion == null)
    val pendingDraft = BotSetupDraft("live-scope", record.draftId)
    pendingDraft.editName("pending"); pendingDraft.editPurpose("purpose"); pendingDraft.editRole("role")
    repeat(3) { pendingDraft.next() }
    val frozen = HostDraftSaveState(record, pendingDraft, lease)
    val beforeCreate = frozen.prepare(pendingDraft, lease, 1)
    pendingDraft.observePendingCreation("original-create", pendingDraft.snapshot().revision)
    check(frozen.observe(beforeCreate.receipt(LocalSavePhase.COMMITTED)))
    check(!frozen.view(pendingDraft, lease, 1).saved && !frozen.view(pendingDraft, lease, 1).canSave)
    pendingDraft.observeCreationResult("original-create", com.mightyoung.muyon.product.agents.setup.CreationStatus.UNKNOWN)
    check(runCatching { frozen.prepare(pendingDraft, lease, 1) }.isFailure)
    check(pendingDraft.snapshot().creation.intentId == "original-create")
    println("PASS save consumer: original/repeat/foreign/late ack/new edits/unknown/exact receipt/lease/MAX/restore reset; no backend calls")
}
