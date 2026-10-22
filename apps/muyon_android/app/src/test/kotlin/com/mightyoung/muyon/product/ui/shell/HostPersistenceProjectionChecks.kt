package com.mightyoung.muyon.product.ui.shell

import com.mightyoung.muyon.product.agents.setup.BotSetupDraft
import com.mightyoung.muyon.product.chat.*
import com.mightyoung.muyon.product.chat.persistence.ProductLocalDraftPort
import org.json.JSONObject
import java.lang.reflect.Proxy
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Exact synthetic boundary records only; actual Runtime/codec/reducer create the UI projection. */
private class ColdProjectionPort : ProductLocalDraftPort {
    override val verified = true // test port only; actual Service remains false
    val conversation = "084847dc-b08c-45e5-8391-93fcc2b3ba2c"
    val draftId = "868cbac8-4d86-4f0d-91cd-324f8cc80d33"
    val attempt = "9369e56d-f3ba-4ab9-b5bd-ed26285c60e6"
    var lookups = 0
    private val archive = BotSetupDraft("old-instance", draftId).exportDraft(1, 0)
    private val digest = MessageDigest.getInstance("SHA-256").digest(archive).joinToString("") { "%02x".format(it) }
    private fun common() = JSONObject().put("schema", 1).put("owner_kind", "local_workspace")
        .put("namespace_id", "a684fd32-935b-4b80-ac47-1df28cf57da3").put("workspace_id", "w")
        .put("conversation_id", conversation).put("project_id", "p").put("draft_id", draftId).put("registry_generation", "1")
    private fun pointer() = common().put("attempt_id", attempt).put("expected_stored_revision", "0")
        .put("next_stored_revision", "1").put("exported_memory_revision", "0").put("host_editor_revision", "0")
        .put("archive_digest", digest).put("state", "committed")
    private fun descriptor() = common().put("stored_revision", "1").put("lifecycle", "editing_only")
        .put("archive_present", true).put("save_attempt", pointer())
    override fun resolve(conversation: String, project: String?) = descriptor()
    override fun read(conversation: String, project: String?, namespace: String, draft: String, generation: String, revision: String) =
        descriptor().put("status", "stored").put("archive_hex", archive.joinToString("") { "%02x".format(it) }).put("archive_digest", digest)
    override fun prepare(conversation: String, project: String?, namespace: String, draft: String, generation: String, revision: String,
        attempt: String, exportedMemoryRevision: String, hostEditorRevision: String, archive: ByteArray): JSONObject = error("PREPARE FORBIDDEN")
    override fun save(conversation: String, project: String?, namespace: String, draft: String, generation: String, revision: String,
        attempt: String, exportedMemoryRevision: String, archive: ByteArray): JSONObject = error("SAVE FORBIDDEN")
    override fun lookup(conversation: String, project: String?, namespace: String, draft: String, attempt: String): JSONObject {
        check(attempt == this.attempt); lookups++
        return descriptor().also { it.remove("save_attempt") }.put("status", "committed_local_storage")
            .put("expected_stored_revision", "0").put("attempt_id", attempt).put("exported_memory_revision", "0")
            .put("host_editor_revision", "0").put("archive_digest", digest)
    }
}

fun main() {
    val port = ColdProjectionPort()
    val native = Proxy.newProxyInstance(ProductChatPort::class.java.classLoader, arrayOf(ProductChatPort::class.java)) { _, method, _ ->
        error("native business forbidden: ${method.name}")
    } as ProductChatPort
    val runtime = ProductChatRuntime(native, ProductChatExchange { _, _, _, _, _ -> error("NETWORK FORBIDDEN") }, port)
    fun call(block: ((JSONObject) -> Unit) -> Unit): JSONObject {
        val done = CountDownLatch(1); var result: JSONObject? = null
        block { result = it; done.countDown() }; check(done.await(5, TimeUnit.SECONDS)); return checkNotNull(result)
    }
    try {
        val generation = call { runtime.updateScope("session", "p", it) }.getLong("scope_generation")
        val scope = HostSetupScope("w", port.conversation, "p", generation)
        fun setup(operation: JSONObject) = call { runtime.setupDraft("session", "w", port.conversation, "p", generation, operation, it) }
        val opened = setup(JSONObject().put("action", "open"))
        check(decodeHostSetup(opened, scope) != null) { "real cold unknown projection must decode without enabling persistence" }
        check(port.lookups == 0)
        val route: (String, JSONObject, (JSONObject) -> Unit) -> Unit = { method, payload, callback ->
            check(method == "chat_setup_draft")
            val response = setup(payload.getJSONObject("operation"))
            callback(JSONObject().put("status", "ok").put("data", response))
        }
        val controller = HostSetupController(scope, route, {})
        controller.open(); controller.readOriginal()
        val displayed = checkNotNull(controller.snapshot)
        check(port.lookups == 0 && !controller.busy)
        for (action in listOf("save", "restore", "query_original_save")) check(!controller.mutate(displayed, action))
        check(port.lookups == 0) // even synthetic verified host cannot bypass the shell's release gate
        val terminal = setup(JSONObject().put("action", "query_original_save").put("local_draft_id", port.draftId)
            .put("expected_local_revision", displayed.revision)) // explicit fixture-only reconciliation
        check(terminal.getLong("local_revision") == displayed.revision && !terminal.getBoolean("saved"))
        check(terminal.getJSONObject("original_save_outcome").getBoolean("cold_recovered"))
        val historyView = checkNotNull(decodeHostSetup(terminal, scope))
        check(historyView.persistence.storedRevision == 1L && historyView.persistence.outcome?.coldRecovered == true)
        check(!visibleEditorSaved(historyView, historyView.name, historyView.purpose, historyView.role))
        check(hostPersistenceMessages(historyView, historyView.name, historyView.purpose, historyView.role).any { "不代表当前编辑已保存" in it })
        controller.readOriginal() // same-CAS storage-only observation, never another lookup
        check(!controller.needsRead && controller.snapshot != displayed && port.lookups == 1)
        fun wrong(change: (JSONObject) -> Unit): JSONObject = JSONObject(terminal.toString()).apply(change)
        check(decodeHostSetup(wrong { it.put("saved", true) }, scope) == null)
        check(decodeHostSetup(wrong { it.getJSONObject("original_save_outcome").put("acknowledges_current_editor", true) }, scope) == null)
        check(decodeHostSetup(wrong { it.put("stored_revision", 1) }, scope) == null)
        check(decodeHostSetup(wrong { it.put("stored_revision", "01") }, scope) == null)
        check(decodeHostSetup(wrong { it.remove("original_save_outcome") }, scope) == null)
        check(decodeHostSetup(wrong { it.getJSONObject("original_save_outcome").put("committed_stored_revision", "0") }, scope) == null)
        check(decodeHostSetup(wrong { it.getJSONObject("original_save_outcome").put("historical", false) }, scope) == null)
        check(decodeHostSetup(wrong { it.put("can_save", true) }, scope) == null) // must agree with operations
        check(decodeHostSetup(wrong { it.getJSONObject("original_save_outcome").put("host_editor_revision", "-1") }, scope) == null)
        val contradictory = JSONObject(opened.toString()).put("original_save_outcome", JSONObject(terminal.getJSONObject("original_save_outcome").toString()))
        check(decodeHostSetup(contradictory, scope) == null) { "same attempt cannot remain pending and terminal" }
        val live = wrong {
            it.put("saved", true).put("persistence_status", "saved")
            it.getJSONObject("original_save_outcome").put("cold_recovered", false).put("acknowledges_current_editor", true)
        }
        val liveView = checkNotNull(decodeHostSetup(live, scope))
        check(visibleEditorSaved(liveView, liveView.name, liveView.purpose, liveView.role))
        check(!visibleEditorSaved(liveView, "unsent edit", liveView.purpose, liveView.role))
        check(decodeHostSetup(JSONObject(live.toString()).apply {
            getJSONObject("original_save_outcome").put("exported_memory_revision", "1")
        }, scope) == null)
        check(!acceptsHostStorageObservation(historyView, liveView)) // cold history cannot become a live acknowledgement
        val noncommit = wrong {
            it.put("stored_revision", "0").put("can_restore", false)
            val ops = it.getJSONArray("supported_local_operations")
            for (index in ops.length() - 1 downTo 0) if (ops.opt(index) == "restore") ops.remove(index)
            it.getJSONObject("original_save_outcome").put("status", "not_committed_local_storage")
                .put("committed_stored_revision", JSONObject.NULL)
        }
        check(decodeHostSetup(JSONObject(noncommit.toString()).apply {
            put("can_restore", true); getJSONArray("supported_local_operations").put("restore")
        }, scope) == null) // stored0 has no canonical archive to restore
        val noncommitView = checkNotNull(decodeHostSetup(noncommit, scope))
        check(noncommitView.persistence.storedRevision == 0L && noncommitView.persistence.outcome?.committedStored == null)
        check(hostPersistenceMessages(noncommitView, "", "", "").any { "计划版本 1 不代表已保存" in it })
        check(!acceptsHostStorageObservation(historyView, noncommitView)) // terminal cannot reverse or stored cursor regress
        controller.close()
        println("PASS cold shell: actual host unknown/history decode; plain open/read zero lookup; closed persistence actions; same-CAS storage observation; cold0/0 never saved; malformed facts rejected")
    } finally { runtime.close(); check(runtime.awaitDrain(5000)) }
}
