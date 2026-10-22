package com.mightyoung.muyon.product.chat.persistence

import org.json.JSONObject
import java.security.MessageDigest

private class SyntheticLocalPort : ProductLocalDraftPort {
    override var verified = true
    val lease = DraftViewLease("workspace", "084847dc-b08c-45e5-8391-93fcc2b3ba2c", "project", "session", 2)
    var revision = "0"
    var archive: ByteArray? = null
    var receipt: JSONObject? = null
    var preparation: JSONObject? = null
    var prepareCalls = 0
    var losePrepareReply = false
    var corruptPrepareReply = false
    var corruptLookupReply = false
    var foreignPreparationOnRead = false
    var lookupOverride: JSONObject? = null
    var resolves = 0
    var saves = 0
    var lookups = 0
    var loseReply = false
    var rejectScope = false
    fun descriptor() = JSONObject().put("schema", 1).put("owner_kind", "local_workspace")
        .put("namespace_id", "9369e56d-f3ba-4ab9-b5bd-ed26285c60e6").put("workspace_id", lease.workspaceId)
        .put("conversation_id", lease.conversationId).put("project_id", lease.projectId)
        .put("draft_id", "868cbac8-4d86-4f0d-91cd-324f8cc80d33").put("registry_generation", "1")
        .put("stored_revision", revision).put("lifecycle", "editing_only").put("archive_present", archive != null)
        .put("save_attempt", preparation ?: JSONObject.NULL)
    override fun resolve(conversation: String, project: String?): JSONObject { check(!rejectScope); resolves++; return descriptor() }
    override fun read(conversation: String, project: String?, namespace: String, draft: String, generation: String, revision: String): JSONObject {
        check(!rejectScope && revision == this.revision)
        if (foreignPreparationOnRead) {
            foreignPreparationOnRead = false
            val bytes = com.mightyoung.muyon.product.agents.setup.BotSetupDraft("foreign-process", draft).exportDraft(revision.toLong() + 1, 0)
            preparation = descriptor().also { it.remove("save_attempt"); it.remove("stored_revision"); it.remove("archive_present"); it.remove("lifecycle") }
                .put("attempt_id", java.util.UUID.randomUUID().toString()).put("expected_stored_revision", revision)
                .put("next_stored_revision", (revision.toLong() + 1).toString()).put("exported_memory_revision", "0")
                .put("host_editor_revision", "0").put("archive_digest", digest(bytes)).put("state", "prepared")
        }
        return descriptor().put("status", if (archive == null) "not_saved" else "stored")
            .put("archive_hex", archive?.joinToString("") { "%02x".format(it) } ?: JSONObject.NULL)
            .put("archive_digest", archive?.let { digest(it) } ?: JSONObject.NULL)
    }
    override fun prepare(original: PreparedLocalSave): JSONObject {
        val revision = original.record.storedRevision.toString()
        val attempt = original.attemptId
        val exportedMemoryRevision = original.exportedMemoryRevision.toString()
        val hostEditorRevision = original.exportedLocalRevision.toString()
        val archive = original.archive
        check(original.record.namespaceId == descriptor().getString("namespace_id") && original.record.draftId == descriptor().getString("draft_id"))
        check(original.record.workspaceId == lease.workspaceId && original.record.projectId == lease.projectId &&
            original.record.conversationId == lease.conversationId && original.record.registryGeneration == 1L)
        check(original.storedRevision == original.record.storedRevision + 1)
        check(!rejectScope && revision == this.revision && preparation?.optString("state") != "prepared")
        prepareCalls++
        preparation = descriptor().also { it.remove("save_attempt"); it.remove("stored_revision"); it.remove("archive_present"); it.remove("lifecycle") }
            .put("attempt_id", attempt).put("expected_stored_revision", revision).put("next_stored_revision", (revision.toLong() + 1).toString())
            .put("exported_memory_revision", exportedMemoryRevision).put("host_editor_revision", hostEditorRevision)
            .put("archive_digest", digest(archive)).put("state", "prepared")
        if (losePrepareReply) error("synthetic lost preparation reply")
        return JSONObject(preparation.toString()).also { if (corruptPrepareReply) it.put("host_editor_revision", "999") }
    }
    override fun save(conversation: String, project: String?, namespace: String, draft: String, generation: String, revision: String,
        attempt: String, exportedMemoryRevision: String, archive: ByteArray): JSONObject {
        check(!rejectScope && revision == this.revision)
        check(preparation!!.getString("attempt_id") == attempt && preparation!!.getString("state") == "prepared")
        check(preparation!!.getString("archive_digest") == digest(archive))
        saves++
        this.revision = (revision.toLong() + 1).toString()
        this.archive = archive.copyOf()
        preparation!!.put("state", "committed")
        receipt = descriptor().also { it.remove("save_attempt") }.put("status", "committed_local_storage").put("expected_stored_revision", revision)
            .put("attempt_id", attempt).put("exported_memory_revision", exportedMemoryRevision)
            .put("host_editor_revision", preparation!!.getString("host_editor_revision")).put("archive_digest", digest(archive))
        if (loseReply) error("synthetic lost reply after commit")
        return JSONObject(receipt.toString())
    }
    override fun lookup(conversation: String, project: String?, namespace: String, draft: String, attempt: String): JSONObject {
        lookups++
        check(!rejectScope && attempt == preparation!!.getString("attempt_id"))
        lookupOverride?.let { return JSONObject(it.toString()) }
        if (preparation!!.getString("state") == "committed") return JSONObject(receipt.toString())
        preparation!!.put("state", "not_committed") // native atomic fence, never replay
        return JSONObject(preparation.toString()).put("status", "not_committed_local_storage")
            .also { if (corruptLookupReply) it.remove("archive_digest") }
    }
    private fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
}
fun main() {
    val port = SyntheticLocalPort()
    port.verified = false
    check(runCatching { HostLocalDraftSession.open(port, port.lease, "live") }.isFailure)
    check(port.saves == 0 && port.resolves == 0)
    port.verified = true
    val session = HostLocalDraftSession.open(port, port.lease, "live")
    session.draft.editName("one"); session.draft.editName("two"); session.draft.editPurpose("purpose")
    port.loseReply = true
    check(runCatching { session.save(3) }.isFailure)
    check(port.saves == 1 && session.view(3).queryOriginalOnly && !session.view(3).saved)
    check(port.receipt!!.getString("exported_memory_revision") == "3" && port.revision == "1")
    session.draft.editName("later")
    check(runCatching { session.save(4) }.isFailure) // no implicit fencing query on save
    session.queryOriginal()
    check(port.saves == 1 && port.lookups == 1 && !session.view(4).saved && session.view(4).canSave)
    check(session.draft.snapshot().name.value == "later")
    port.loseReply = false
    session.save(4)
    check(port.saves == 2 && session.view(4).saved && port.revision == "2")
    val reopened = HostLocalDraftSession.open(port, port.lease.copy(sessionId = "new-session", generation = 4), "new-live")
    check(!reopened.view(0).saved && reopened.draft.snapshot().name.value == "" && !reopened.canRestore())
    val beforeLookup = port.lookups
    reopened.revalidate()
    check(port.lookups == beforeLookup) // ordinary read never fences a preparation
    reopened.queryOriginal()
    check(reopened.canRestore() && !reopened.view(0).saved)
    check(!reopened.view(0).canSave && runCatching { reopened.save(0) }.isFailure)
    reopened.restore()
    check(reopened.draft.snapshot().name.value == "later" && reopened.draft.snapshot().revision == 0L)
    check(!reopened.view(0).saved && reopened.draft.snapshot().creation.intentId == null)
    port.rejectScope = true
    check(runCatching { reopened.save(0) }.isFailure && port.saves == 2)
    check(runCatching { reopened.restore() }.isFailure)
    check(runCatching { reopened.revalidate() }.isFailure)
    val preparedPort = SyntheticLocalPort().also { it.losePrepareReply = true }
    val prior = HostLocalDraftSession.open(preparedPort, preparedPort.lease, "prior")
    prior.draft.editName("must not be replayed")
    check(runCatching { prior.save(1) }.isFailure && preparedPort.saves == 0)
    val pointer = preparedPort.preparation!!.getString("attempt_id")
    val cold = HostLocalDraftSession.open(preparedPort, preparedPort.lease.copy(sessionId = "restart"), "restart")
    check(cold.view(0).queryOriginalOnly && !cold.view(0).canSave && preparedPort.lookups == 0)
    cold.revalidate()
    check(preparedPort.lookups == 0 && preparedPort.saves == 0)
    preparedPort.corruptLookupReply = true
    check(runCatching { cold.queryOriginal() }.isFailure && cold.view(0).queryOriginalOnly && !cold.view(0).canSave)
    preparedPort.corruptLookupReply = false
    cold.queryOriginal()
    check(preparedPort.preparation!!.getString("state") == "not_committed" && preparedPort.saves == 0)
    check(cold.view(0).canSave && !cold.view(0).saved && pointer == preparedPort.preparation!!.getString("attempt_id"))
    check(runCatching { preparedPort.save(preparedPort.lease.conversationId, "project", preparedPort.descriptor().getString("namespace_id"),
        preparedPort.descriptor().getString("draft_id"), "1", "0", pointer, "1", prior.draft.exportDraft(1, 1)) }.isFailure)
    check(preparedPort.saves == 0)
    preparedPort.losePrepareReply = false
    cold.draft.editName("new explicit snapshot")
    cold.save(1)
    check(preparedPort.saves == 1 && preparedPort.prepareCalls == 2 && pointer != preparedPort.preparation!!.getString("attempt_id"))
    val zeroPort = SyntheticLocalPort()
    val zeroPrior = HostLocalDraftSession.open(zeroPort, zeroPort.lease, "old-zero")
    zeroPrior.save(0) // captured memory/editor0/0, exactly reused by a fresh reducer
    check(runCatching { zeroPrior.save(0) }.isFailure && zeroPort.saves == 1 && zeroPort.prepareCalls == 1)
    val zeroCold = HostLocalDraftSession.open(zeroPort, zeroPort.lease.copy(sessionId = "new-zero"), "new-zero")
    check(zeroCold.draft.snapshot().revision == 0L && zeroCold.view(0).queryOriginalOnly)
    val zeroOriginalId = zeroCold.view(0).originalAttemptId
    zeroPort.lookupOverride = JSONObject(zeroPort.preparation.toString()).put("state", "not_committed").put("status", "not_committed_local_storage")
    check(runCatching { zeroCold.queryOriginal() }.isFailure)
    check(zeroCold.view(0).queryOriginalOnly && !zeroCold.view(0).canSave && zeroCold.view(0).originalAttemptId == zeroOriginalId)
    zeroPort.lookupOverride = null
    zeroCold.queryOriginal()
    check(!zeroCold.view(0).saved && zeroCold.canRestore() && !zeroCold.view(0).canSave)
    check(zeroCold.lastOutcome!!.recovered && zeroCold.lastOutcome!!.phase == LocalSavePhase.COMMITTED)
    zeroCold.restore()
    check(!zeroCold.view(0).saved && zeroCold.draft.snapshot().revision == 0L)
    val wrongReply = SyntheticLocalPort().also { it.corruptPrepareReply = true }
    val wrongSession = HostLocalDraftSession.open(wrongReply, wrongReply.lease, "live")
    check(runCatching { wrongSession.save(0) }.isFailure && wrongReply.saves == 0)
    check(wrongSession.view(0).queryOriginalOnly && !wrongSession.view(0).canSave)
    wrongSession.queryOriginal()
    check(wrongSession.view(0).canSave && !wrongSession.view(0).saved && wrongReply.saves == 0)
    val readRacePort = SyntheticLocalPort()
    val readRace = HostLocalDraftSession.open(readRacePort, readRacePort.lease, "live")
    readRacePort.foreignPreparationOnRead = true
    check(runCatching { readRace.save(0) }.isFailure)
    check(readRace.view(0).queryOriginalOnly && readRace.view(0).originalAttemptId == readRacePort.preparation!!.getString("attempt_id"))
    check(readRacePort.prepareCalls == 0 && readRacePort.saves == 0 && readRacePort.lookups == 0)
    zeroCold.draft.editName("retain local editor")
    zeroPort.foreignPreparationOnRead = true
    check(runCatching { zeroCold.restore() }.isFailure)
    check(zeroCold.view(1).queryOriginalOnly && zeroCold.draft.snapshot().name.value == "retain local editor" && zeroPort.saves == 1)
    val recordPort = SyntheticLocalPort()
    val recordSession = HostLocalDraftSession.open(recordPort, recordPort.lease, "record-scope")
    recordSession.draft.editName("distinct counters")
    recordSession.save(42)
    check(recordPort.preparation!!.getString("exported_memory_revision") == "1")
    check(recordPort.preparation!!.getString("host_editor_revision") == "42")
    check(recordPort.preparation!!.getString("expected_stored_revision") == "0" && recordPort.preparation!!.getString("next_stored_revision") == "1")
    check(recordSession.view(42).saved && !recordSession.view(43).saved)
    runtimeIntegrationChecks()
    println("PASS host native session: verification gate; real stored vs memory revisions; original unknown lookup; late edit not saved; restart semantic restore; revoked scope no write")
}

private fun runtimeIntegrationChecks() {
    val port = SyntheticLocalPort()
    val business = java.lang.reflect.Proxy.newProxyInstance(com.mightyoung.muyon.product.chat.ProductChatPort::class.java.classLoader,
        arrayOf(com.mightyoung.muyon.product.chat.ProductChatPort::class.java)) { _, _, _ -> error("business port forbidden") }
        as com.mightyoung.muyon.product.chat.ProductChatPort
    val runtime = com.mightyoung.muyon.product.chat.ProductChatRuntime(business,
        com.mightyoung.muyon.product.chat.ProductChatExchange { _, _, _, _, _ -> error("network forbidden") }, port)
    fun call(block: ((JSONObject) -> Unit) -> Unit): JSONObject {
        val latch = java.util.concurrent.CountDownLatch(1); var result: JSONObject? = null
        block { result = it; latch.countDown() }
        check(latch.await(5, java.util.concurrent.TimeUnit.SECONDS)); return checkNotNull(result)
    }
    val generation = call { runtime.updateScope("session", "project", it) }.getLong("scope_generation")
    fun setup(op: JSONObject, gen: Long = generation) = call {
        runtime.setupDraft("session", "workspace", port.lease.conversationId, "project", gen, op, it)
    }
    fun operation(state: JSONObject, action: String, value: String? = null) = JSONObject().put("action", action)
        .put("local_draft_id", state.getString("local_draft_id")).put("expected_local_revision", state.getLong("local_revision"))
        .also { if (value != null) it.put("value", value) }
    val blockedPort = SyntheticLocalPort().also { it.verified = false }
    val blocked = com.mightyoung.muyon.product.chat.ProductChatRuntime(business,
        com.mightyoung.muyon.product.chat.ProductChatExchange { _, _, _, _, _ -> error("network forbidden") }, blockedPort)
    try {
        val blockedGen = call { blocked.updateScope("session", "project", it) }.getLong("scope_generation")
        val blockedView = call { blocked.setupDraft("session", "workspace", blockedPort.lease.conversationId, "project", blockedGen,
            JSONObject().put("action", "open"), it) }
        check(!blockedView.getBoolean("can_save") && blockedPort.resolves == 0 && blockedPort.saves == 0)
    } finally { blocked.close() }
    try {
        var state = setup(JSONObject().put("action", "open"))
        check(state.getBoolean("can_save") && !state.getBoolean("can_create"))
        check(state.getString("local_draft_id") == port.descriptor().getString("draft_id"))
        state = setup(operation(state, "edit_name", "host edited"))
        val save = operation(state, "save")
        state = setup(save)
        check(state.getBoolean("saved") && port.saves == 1)
        check(state.getJSONObject("original_save_outcome").getBoolean("acknowledges_current_editor"))
        check(setup(save).getString("status") == "unavailable") // consumed UI CAS
        check(setup(operation(state, "save"), generation + 1).getString("status") == "unavailable")
        check(port.saves == 1)
        state = setup(operation(state, "edit_name", "unknown export"))
        port.loseReply = true
        val uncertain = setup(operation(state, "save"))
        check(uncertain.getString("status") == "unavailable" && !uncertain.has("name"))
        val originalAttempt = port.receipt!!.getString("attempt_id")
        port.rejectScope = true
        val denied = setup(operation(state, "query_original_save"))
        check(denied.getString("status") == "unavailable" && !denied.has("name"))
        check(port.saves == 2 && originalAttempt == port.receipt!!.getString("attempt_id"))
        port.rejectScope = false
        state = setup(operation(state, "query_original_save"))
        check(state.getBoolean("saved") && port.saves == 2)
        state = setup(operation(state, "cancel"))
        check(!state.getBoolean("can_save") && !state.getBoolean("can_restore"))
        val coldRuntime = com.mightyoung.muyon.product.chat.ProductChatRuntime(business,
            com.mightyoung.muyon.product.chat.ProductChatExchange { _, _, _, _, _ -> error("network forbidden") }, port)
        try {
            val coldGeneration = call { coldRuntime.updateScope("cold-session", "project", it) }.getLong("scope_generation")
            fun coldSetup(op: JSONObject) = call { coldRuntime.setupDraft("cold-session", "workspace", port.lease.conversationId,
                "project", coldGeneration, op, it) }
            val lookupBeforeOpen = port.lookups
            val coldOpen = coldSetup(JSONObject().put("action", "open"))
            check(!coldOpen.getBoolean("saved") && !coldOpen.getBoolean("can_save") && port.lookups == lookupBeforeOpen)
            val reconciled = coldSetup(operation(coldOpen, "query_original_save"))
            val history = reconciled.getJSONObject("original_save_outcome")
            check(history.getBoolean("historical") && history.getBoolean("cold_recovered"))
            check(history.getString("status") == "committed_local_storage" && !history.getBoolean("acknowledges_current_editor"))
            check(!reconciled.getBoolean("saved") && reconciled.getBoolean("can_restore"))
            val restored = coldSetup(operation(reconciled, "restore"))
            check(restored.getString("name") == "unknown export" && !restored.getBoolean("saved"))
        } finally { coldRuntime.close() }
    } finally { runtime.close() }
}
