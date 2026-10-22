package com.mightyoung.muyon.product.chat

import org.json.JSONObject
import java.lang.reflect.Proxy
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

fun hostContinuationChecks() {
    var portCalls = 0
    val port = Proxy.newProxyInstance(ProductChatPort::class.java.classLoader, arrayOf(ProductChatPort::class.java)) { _, method, _ ->
        portCalls++
        error("Local setup must never call native port ${method.name}")
    } as ProductChatPort
    val runtime = ProductChatRuntime(port, ProductChatExchange { _, _, _, _, _ -> error("NETWORK FORBIDDEN") })
    fun call(block: ((JSONObject) -> Unit) -> Unit): JSONObject {
        val done = CountDownLatch(1); var result: JSONObject? = null
        block { result = it; done.countDown() }
        check(done.await(5, TimeUnit.SECONDS))
        return checkNotNull(result)
    }
    fun scope(session: String, project: String?) = call { runtime.updateScope(session, project, it) }.getLong("scope_generation")
    val generation = scope("owner", "project")
    fun setup(op: JSONObject, session: String = "owner", conversation: String = "conversation", project: String? = "project", gen: Long = generation) =
        call { runtime.setupDraft(session, "workspace", conversation, project, gen, op, it) }
    fun open() = setup(JSONObject().put("action", "open"))
    fun denied(result: JSONObject) { check(result.getString("status") == "unavailable"); check(!result.has("name")) }
    fun mutation(state: JSONObject, action: String, value: String? = null, token: String? = null): JSONObject =
        JSONObject().put("action", action).put("local_draft_id", state.getString("local_draft_id"))
            .put("expected_local_revision", state.getLong("local_revision"))
            .also { if (value != null) it.put("value", value); if (token != null) it.put("suggestion_request_id", token) }
    fun read(state: JSONObject) = setup(JSONObject().put("action", "read").put("local_draft_id", state.getString("local_draft_id")))
    try {
        var state = open()
        check(state.getString("status") == "local_only" && state.getString("projection_type") == "setup_draft")
        check(state.getLong("local_revision") == 0L && state.getLong("reducer_revision") == 0L)
        check(state.getString("local_draft_id") == open().getString("local_draft_id"))
        check(!state.getBoolean("saved") && !state.getBoolean("can_save") && !state.getBoolean("can_create") && !state.getBoolean("can_start"))
        check(state.getString("capability_metadata_status") == "unavailable" && state.getString("material_metadata_status") == "unavailable")
        check(state.isNull("actual_micro_cny") && state.isNull("reserved_micro_cny") && state.isNull("intent_id") && state.isNull("agent_id"))
        check(!state.getJSONArray("supported_local_operations").toString().contains("next"))
        check(!state.getJSONArray("supported_local_operations").toString().contains("suggest_role"))
        denied(setup(mutation(state, "next")))
        val original = state
        val edit = mutation(state, "edit_name", "文献助手")
        state = setup(edit)
        check(state.getString("name") == "文献助手" && state.getLong("local_revision") == 1L)
        denied(setup(edit)) // exact displayed CAS is single-use, never refreshed on failure
        check(read(state).getLong("local_revision") == 1L)
        denied(setup(mutation(original, "edit_name", "覆盖")))
        denied(setup(mutation(state, "edit_name", "\u0000")))
        denied(setup(mutation(state, "edit_name", "bad").put("value", 17)))
        denied(setup(mutation(state, "edit_name", "bad").put("value", JSONObject.NULL)))
        denied(setup(mutation(state, "edit_name", "invalid").put("expected_local_revision", 1.2)))
        denied(setup(mutation(state, "edit_name", "invalid").put("backend_intent", "invented")))
        check(read(state).getString("name") == "文献助手")
        denied(setup(mutation(state, "edit_name", "foreign"), conversation = "foreign"))
        denied(setup(mutation(state, "edit_name", "foreign"), project = "foreign"))
        val otherGeneration = scope("other", "project")
        denied(setup(mutation(state, "edit_name", "foreign"), session = "other", gen = otherGeneration))
        state = setup(mutation(state, "next"))
        check(state.getString("step") == "PURPOSE" && !state.getJSONArray("supported_local_operations").toString().contains("next"))
        denied(setup(mutation(state, "next")))
        state = setup(mutation(state, "back"))
        state = setup(mutation(state, "edit_purpose", "整理论文"))
        state = setup(mutation(state, "suggest_role"))
        val token = state.getJSONObject("suggestion").getString("request_id")
        check(state.getJSONObject("suggestion").getString("source_id") == "paper-organizer")
        denied(setup(mutation(state, "accept_role", token = "wrong")))
        state = setup(mutation(state, "accept_role", token = token))
        check(state.getString("role") == "文献整理助手")
        denied(setup(mutation(state, "accept_role", token = token)))
        state = setup(mutation(state, "edit_role", "手动角色"))
        state = setup(mutation(state, "suggest_role"))
        val lockedToken = state.getJSONObject("suggestion").getString("request_id")
        denied(setup(mutation(state, "accept_role", token = lockedToken)))
        check(read(state).getString("role") == "手动角色")
        state = setup(mutation(state, "cancel"))
        check(state.getBoolean("cancelled") && state.isNull("suggestion"))
        check(state.getJSONArray("supported_local_operations").toString() == "[\"open\",\"read\",\"resume\"]")
        denied(setup(mutation(state, "edit_role", "overwrite cancelled")))
        denied(setup(mutation(state, "accept_role", token = lockedToken)))
        state = setup(mutation(state, "resume"))
        repeat(3) { state = setup(mutation(state, "next")) }
        check(state.getString("step") == "REVIEW" && state.getString("creation_status") == "not_requested")
        check(!state.getJSONArray("supported_local_operations").toString().contains("next"))
        denied(setup(mutation(state, "next")))
        for (unsupported in listOf("create", "start", "save", "approve", "observe_created", "query_creation")) denied(setup(mutation(state, unsupported)))
        check(!read(state).getBoolean("saved"))
        check(state.getJSONArray("allowed_capabilities").length() == 0 && state.getJSONArray("allowed_materials").length() == 0)
        state.put("name", "tampered"); check(read(state).getString("name") == "文献助手")
        scope("owner", "other"); scope("owner", "project")
        denied(read(state)) // old generation cannot revive a draft
        val newGeneration = scope("owner", "project")
        denied(setup(JSONObject().put("action", "read").put("local_draft_id", state.getString("local_draft_id")), gen = newGeneration))
        runtime.releaseSession("owner")
        val releasedGeneration = scope("owner", "project")
        val fresh = setup(JSONObject().put("action", "open"), gen = releasedGeneration)
        check(fresh.getString("local_draft_id") != state.getString("local_draft_id"))
        check(fresh.getString("name").isEmpty())
        repeat(31) { index ->
            check(setup(JSONObject().put("action", "open"), conversation = "capacity-$index", gen = releasedGeneration).getString("status") == "local_only")
        }
        denied(setup(JSONObject().put("action", "open"), conversation = "over-capacity", gen = releasedGeneration))
        check(setup(JSONObject().put("action", "read").put("local_draft_id", fresh.getString("local_draft_id")), gen = releasedGeneration).getString("name").isEmpty())
        check(portCalls == 0)
        println("PASS host local setup: genuine ephemeral identity/CAS/repeat/scope/token/revoke/unknown/disabled backend; zero native calls")
    } finally { runtime.close(); check(runtime.awaitDrain(5000)) }
}
