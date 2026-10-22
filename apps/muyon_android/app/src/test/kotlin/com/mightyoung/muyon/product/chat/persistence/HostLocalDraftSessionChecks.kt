package com.mightyoung.muyon.product.chat.persistence

import org.json.JSONObject
import java.security.MessageDigest

private class SyntheticLocalPort : ProductLocalDraftPort {
    override var verified = true
    val lease = DraftViewLease("workspace", "084847dc-b08c-45e5-8391-93fcc2b3ba2c", "project", "session", 2)
    var revision = "0"
    var archive: ByteArray? = null
    var receipt: JSONObject? = null
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
    override fun resolve(conversation: String, project: String?): JSONObject { resolves++; return descriptor() }
    override fun read(conversation: String, project: String?, namespace: String, draft: String, generation: String, revision: String): JSONObject {
        check(!rejectScope && revision == this.revision)
        return descriptor().put("status", if (archive == null) "not_saved" else "stored")
            .put("archive_hex", archive?.joinToString("") { "%02x".format(it) } ?: JSONObject.NULL)
            .put("archive_digest", archive?.let { digest(it) } ?: JSONObject.NULL)
    }
    override fun save(conversation: String, project: String?, namespace: String, draft: String, generation: String, revision: String,
        attempt: String, exportedMemoryRevision: String, archive: ByteArray): JSONObject {
        check(!rejectScope && revision == this.revision)
        saves++
        this.revision = (revision.toLong() + 1).toString()
        this.archive = archive.copyOf()
        receipt = descriptor().put("status", "committed_local_storage").put("expected_stored_revision", revision)
            .put("attempt_id", attempt).put("exported_memory_revision", exportedMemoryRevision).put("archive_digest", digest(archive))
        if (loseReply) error("synthetic lost reply after commit")
        return JSONObject(receipt.toString())
    }
    override fun lookup(conversation: String, project: String?, namespace: String, draft: String, attempt: String): JSONObject {
        lookups++
        check(!rejectScope && attempt == receipt!!.getString("attempt_id"))
        return JSONObject(receipt.toString())
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
    session.save(4) // repeated save recovers original; does not export later editor
    check(port.saves == 1 && port.lookups == 1 && !session.view(4).saved && session.view(4).canSave)
    check(session.draft.snapshot().name.value == "later")
    port.loseReply = false
    session.save(4)
    check(port.saves == 2 && session.view(4).saved && port.revision == "2")
    val reopened = HostLocalDraftSession.open(port, port.lease.copy(sessionId = "new-session", generation = 4), "new-live")
    check(!reopened.view(0).saved && reopened.draft.snapshot().name.value == "" && reopened.canRestore())
    check(!reopened.view(0).canSave && runCatching { reopened.save(0) }.isFailure)
    reopened.restore()
    check(reopened.draft.snapshot().name.value == "later" && reopened.draft.snapshot().revision == 0L)
    check(!reopened.view(0).saved && reopened.draft.snapshot().creation.intentId == null)
    port.rejectScope = true
    check(runCatching { reopened.save(0) }.isFailure && port.saves == 2)
    check(runCatching { reopened.restore() }.isFailure)
    check(runCatching { reopened.revalidate() }.isFailure)
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
    } finally { runtime.close() }
}
