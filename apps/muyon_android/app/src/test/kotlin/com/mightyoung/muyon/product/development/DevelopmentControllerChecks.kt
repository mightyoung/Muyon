package com.mightyoung.muyon.product.chat

import com.mightyoung.muyon.product.development.DevelopmentDraftHandle
import com.mightyoung.muyon.product.development.DevelopmentDraftPort
import org.json.JSONObject
import java.lang.reflect.Proxy
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

private class DraftFixture : DevelopmentDraftPort {
    var opened = 0
    var closed = 0
    var mutations = 0
    var confirms = 0
    var previews = 0
    private val names = mutableMapOf<String, String>()
    override fun open(session: String, conversation: String, project: String?, draftId: String?, create: Boolean): DevelopmentDraftHandle {
        check(create || draftId in names)
        var id = draftId ?: "draft-${++opened}"
        names.putIfAbsent(id, "")
        return object : DevelopmentDraftHandle {
            var revision = 0L
            var revoked = false
            var prepared = false
            var dispatched = false
            override fun snapshot(): JSONObject {
                check(!revoked)
                return JSONObject().put("draft_ref", JSONObject().put("draft_id", id).put("revision", "storage-baseline")
                    .put("scope", JSONObject().put("scope", JSONObject().put("project_id", project ?: JSONObject.NULL))))
                    .put("content", JSONObject().put("conversation_id", conversation).put("edit_revision", revision.toString()).put("project_name", JSONObject().put("text", names[id])))
            }
            fun update(expected: String): JSONObject {
                check(!revoked && expected == revision.toString())
                revision++; mutations++
                return snapshot()
            }
            override fun setProjectName(name: String, expectedRevision: String): JSONObject {
                update(expectedRevision); names[id] = name; return snapshot()
            }
            override fun addItem(kind: String, text: String, expectedRevision: String) = update(expectedRevision)
            override fun editItem(itemId: String, text: String, expectedRevision: String) = update(expectedRevision)
            override fun chooseNewProject(expectedRevision: String) = update(expectedRevision)
            override fun prepareProject(): JSONObject { check(!revoked); prepared = true; return JSONObject().put("plan", JSONObject().put("plan_id", "original-plan-$revision")).put("binding_digest", "binding-$revision") }
            override fun confirmProject(planId: String, digest: String): JSONObject {
                check(!revoked && prepared && planId == "original-plan-$revision" && digest == "binding-$revision")
                if (!dispatched) { confirms++; dispatched = true }
                return recoverOriginal()
            }
            override fun recoverOriginal(): JSONObject { check(!revoked); return JSONObject().put("intent_id", "original-intent").put("status", "unknown") }
            override fun recoverProposal(request: String): JSONObject {
                id = "proposal-draft"; names[id] = "Recovered proposal"
                return JSONObject().put("status", "saved").put("draft_id", id).put("request_id", request).put("snapshot", snapshot())
            }
            override fun previewProposal(request: String, session: String, generation: String): JSONObject { check(!revoked); previews++; return JSONObject().put("review_digest", "review").put("request_id", request) }
            override fun acceptProposal(request: String, session: String, generation: String, digest: String): JSONObject {
                id = "proposal-draft"; names[id] = "Model proposal"; revision = 0
                return JSONObject().put("draft_id", id).put("request_id", request).put("snapshot", snapshot())
            }
            override fun rejectProposal(request: String, session: String, generation: String, digest: String) = JSONObject().put("rejected", true)
            override fun close() { if (!revoked) closed++; revoked = true }
        }
    }
}

fun main() {
    val fixture = DraftFixture()
    val calls = mutableListOf<String>()
    val port = Proxy.newProxyInstance(ProductChatPort::class.java.classLoader, arrayOf(ProductChatPort::class.java)) { _, method, args ->
        calls.add(method.name)
        when (method.name) {
            "configure" -> JSONObject().put("id", "configuration")
            "prepareDevelopmentScoped" -> JSONObject().put("request_id", "request-development").put("conversation_id", args!![0])
                .put("configuration_id", "configuration").put("send_allowed", false).put("blocked_reason", "pricing_proof_unavailable")
            "bindScope" -> Unit
            "failureCode" -> null
            "cancel" -> JSONObject().put("status", "cancelled")
            else -> error("unexpected native call ${method.name}")
        }
    } as ProductChatPort
    val runtime = ProductChatRuntime(port, ProductChatExchange { _, _, _, _, _ -> error("NETWORK FORBIDDEN") }, developmentPort = fixture)
    fun call(action: ((JSONObject) -> Unit) -> Unit): JSONObject {
        val done = CountDownLatch(1); var result: JSONObject? = null
        action { result = it; done.countDown() }; check(done.await(5, TimeUnit.SECONDS)); return checkNotNull(result)
    }
    var viewGeneration = 0L
    fun scope(project: String?): JSONObject = call { runtime.updateScope("owner", project, it) }.also { viewGeneration = it.getLong("scope_generation") }
    fun input(id: String? = null) = JSONObject().put("conversation_id", "conversation").put("project_id", JSONObject.NULL)
        .put("scope_generation", viewGeneration)
        .also { if (id != null) it.put("draft_id", id) }
    fun dev(method: String, data: JSONObject, session: String = "owner") = call { runtime.development(session, method, data, it) }
    fun denied(data: JSONObject) { check(data.optString("status") == "unavailable") }
    fun update(id: String, revision: Any) = input(id).put("action", "set_name").put("text", "Project").put("expected_revision", revision)
    try {
        scope(null)
        val opened = dev("development_open", input().put("create", true))
        val id = opened.getJSONObject("snapshot").getJSONObject("draft_ref").getString("draft_id")
        dev("development_open", input().put("create", true)); check(fixture.opened == 1)
        denied(dev("development_update", update(id, 0.5)))
        denied(dev("development_update", update(id, "0").put("owner", "forged")))
        check(fixture.mutations == 0)
        val changed = dev("development_update", update(id, "0"))
        check(changed.getJSONObject("snapshot").getJSONObject("content").getString("edit_revision") == "1")
        denied(dev("development_update", update(id, "0"))); check(fixture.mutations == 1)
        denied(dev("development_update", update(id, "1"), session = "foreign"))
        denied(dev("development_update", update(id, "1").put("conversation_id", "foreign")))
        val prepared = dev("development_prepare_project", input(id))
        check(prepared.getJSONObject("plan").getString("plan_id") == "original-plan-1")
        fun confirmInput(draft: String, prepared: JSONObject) = input(draft).put("plan_id", prepared.getJSONObject("plan").getString("plan_id")).put("binding_digest", prepared.getString("binding_digest"))
        denied(dev("development_confirm_project", confirmInput(id, prepared).put("binding_digest", "forged")))
        repeat(2) { check(dev("development_confirm_project", confirmInput(id, prepared)).getJSONObject("original").getString("intent_id") == "original-intent") }
        dev("development_lookup_original", input(id)); check(fixture.confirms == 1)
        val other = dev("development_open", input("explicit-draft").put("create", true))
        check(other.getJSONObject("snapshot").getJSONObject("draft_ref").getString("draft_id") == "explicit-draft")
        denied(dev("development_update", update(id, "1"))) // only explicit open switches selected handle
        val reviewA = dev("development_prepare_project", input("explicit-draft"))
        dev("development_update", update("explicit-draft", "0"))
        val reviewB = dev("development_prepare_project", input("explicit-draft"))
        check(reviewA.getString("binding_digest") != reviewB.getString("binding_digest"))
        denied(dev("development_confirm_project", confirmInput("explicit-draft", reviewA)))
        check(fixture.confirms == 1)
        val staleOpen = input(id).put("create", false)
        val staleUpdate = update(id, "1")
        scope("other"); scope(null); check(fixture.closed == 2)
        denied(dev("development_open", staleOpen))
        denied(dev("development_update", update(id, "1")))
        val restored = dev("development_open", input(id).put("create", false))
        denied(dev("development_update", staleUpdate))
        denied(dev("development_update", update(id, "0").put("scope_generation", viewGeneration.toDouble())))
        denied(dev("development_update", update(id, "0").also { it.remove("scope_generation") }))
        check(restored.getJSONObject("snapshot").getJSONObject("content").getJSONObject("project_name").getString("text") == "Project")
        check(call { runtime.currentScope("owner", null, it) }.getLong("scope_generation") == viewGeneration)
        denied(call { runtime.currentScope("owner", "stale-project", it) })
        call { runtime.configure("owner", "a".repeat(20).toCharArray(), "100", "1", true, false, it) }
        denied(call { runtime.prepareDevelopment("owner", "conversation", "Old view", null, staleOpen.getLong("scope_generation"), it) })
        val plan = call { runtime.prepareDevelopment("owner", "conversation", "Draft a project", null, viewGeneration, it) }
        check(plan.getString("request_id") == "request-development")
        check("prepare" !in calls && "prepareScoped" !in calls && "confirm" !in calls && "claim" !in calls)
        denied(call { runtime.confirm("owner", "request-development", it) })
        fun proposal(session: String, conversation: String = "conversation") = call {
            runtime.developmentProposal(session, "development_preview_proposal", input().put("conversation_id", conversation).put("request_id", "request-development"), it)
        }
        denied(proposal("foreign")); denied(proposal("owner", "foreign"))
        check(proposal("owner").getString("review_digest") == "review")
        val accepted = call { runtime.developmentProposal("owner", "development_accept_proposal", input(id).put("request_id", "request-development").put("review_digest", "review"), it) }
        check(accepted.getString("draft_id") == "proposal-draft")
        denied(dev("development_update", update(id, "0")))
        check(dev("development_update", update("proposal-draft", "0")).getJSONObject("snapshot").getJSONObject("content").getString("edit_revision") == "1")
        scope("other"); scope(null); denied(proposal("owner"))
        dev("development_open", input(id).put("create", false))
        val recovered = dev("development_lookup_proposal", input(id).put("request_id", "request-development"))
        check(recovered.getString("status") == "saved")
        check(dev("development_update", update("proposal-draft", "0")).getJSONObject("snapshot").getJSONObject("content").getString("edit_revision") == "1")
        check(fixture.previews == 1)
        runtime.releaseSession("owner")
        scope(null)
        denied(dev("development_lookup_original", input(id)))
        check("confirm" !in calls && "claim" !in calls)
        println("PASS development controller/runtime: CAS, exact draft selection, scope/session revocation, original-only recovery, restricted prepare, proposal ownership, zero sends")
    } finally { runtime.close(); check(runtime.awaitDrain(5000)) }
}
