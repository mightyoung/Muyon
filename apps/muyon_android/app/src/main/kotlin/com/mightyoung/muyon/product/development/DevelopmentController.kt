package com.mightyoung.muyon.product.development

import com.mightyoung.muyon.product.chat.ProductScopeRegistry
import org.json.JSONObject

/** Private host capability. UI scope tokens must match the host's current lease;
 * owners and credential generations are never supplied by JSON callers. */
interface DevelopmentDraftPort {
    fun open(session: String, conversation: String, project: String?, draftId: String?, create: Boolean): DevelopmentDraftHandle
}

interface DevelopmentDraftHandle : AutoCloseable {
    fun snapshot(): JSONObject
    fun setProjectName(name: String, expectedRevision: String): JSONObject
    fun addItem(kind: String, text: String, expectedRevision: String): JSONObject
    fun editItem(itemId: String, text: String, expectedRevision: String): JSONObject
    fun chooseNewProject(expectedRevision: String): JSONObject
    fun prepareProject(): JSONObject
    fun confirmProject(planId: String, digest: String): JSONObject
    fun recoverOriginal(): JSONObject
    fun recoverProposal(request: String): JSONObject
    fun previewProposal(request: String, session: String, generation: String): JSONObject
    fun acceptProposal(request: String, session: String, generation: String, digest: String): JSONObject
    fun rejectProposal(request: String, session: String, generation: String, digest: String): JSONObject
}

/** Called on the chat control queue. Scope changes and disconnect close every
 * capability; storage namespace identity is owned exclusively by native code. */
internal class DevelopmentController(private val port: DevelopmentDraftPort, private val scopes: ProductScopeRegistry) : AutoCloseable {
    private data class View(val session: String, val conversation: String, val project: String?, val generation: Long)
    private data class Key(val view: View, val draft: String)
    private val handles = linkedMapOf<Key, DevelopmentDraftHandle>()
    private val selected = mutableMapOf<View, String>()
    private data class Review(val planId: String, val digest: String)
    private val reviews = mutableMapOf<Key, Review>()
    private var closed = false
    private fun snapshot(view: View, handle: DevelopmentDraftHandle): JSONObject = handle.snapshot().also { value ->
        check(value.getJSONObject("content").getString("conversation_id") == view.conversation)
        val project = value.getJSONObject("draft_ref").getJSONObject("scope").getJSONObject("scope").opt("project_id")
        check((if (project == null || project === JSONObject.NULL) null else project as String) == view.project)
    }

    @Synchronized fun execute(session: String, method: String, input: JSONObject, credentialGeneration: String? = null): JSONObject {
        check(!closed)
        val fields = mutableSetOf("conversation_id", "project_id", "draft_id", "scope_generation")
        when (method) {
            "development_open" -> fields.add("create")
            "development_update" -> {
                fields.addAll(listOf("action", "expected_revision"))
                when (input.getString("action")) {
                    "set_name" -> fields.add("text")
                    "add_item" -> fields.addAll(listOf("kind", "text"))
                    "edit_item" -> fields.addAll(listOf("item_id", "text"))
                    "choose_new_project" -> Unit
                    else -> throw IllegalArgumentException("development_action_unavailable")
                }
            }
            "development_prepare_project", "development_lookup_original" -> Unit
            "development_confirm_project" -> fields.addAll(listOf("plan_id", "binding_digest"))
            "development_preview_proposal", "development_lookup_proposal" -> fields.add("request_id")
            "development_accept_proposal", "development_reject_proposal" -> fields.addAll(listOf("request_id", "review_digest"))
            else -> throw IllegalArgumentException("development_operation_unavailable")
        }
        require(input.keys().asSequence().all { it in fields })
        require(input.keys().asSequence().all { input.get(it) !is JSONObject && input.get(it) !is org.json.JSONArray })
        val scope = checkNotNull(scopes.get(session))
        val capturedGeneration = input.get("scope_generation").let {
            require(it is Int || it is Long)
            (it as Number).toLong().also { generation -> require(generation >= 0) }
        }
        val conversation = input.getString("conversation_id").also { require(it.isNotBlank() && it.length <= 1024) }
        val project = input.opt("project_id").let { if (it == null || it === JSONObject.NULL) null else it as String }
        check(scopes.matches(session, project, capturedGeneration))
        val view = View(session, conversation, project, scope.generation)
        val requestedDraft = input.opt("draft_id").let { if (it == null || it === JSONObject.NULL) null else it as String }
        val handle = if (method == "development_open") {
            val draft = requestedDraft ?: selected[view]
            handles[Key(view, draft.orEmpty())] ?: run {
                require(handles.size < 32)
                val opened = port.open(session, conversation, project, requestedDraft, input.optBoolean("create", false))
                try {
                    val actual = snapshot(view, opened).getJSONObject("draft_ref").getString("draft_id")
                    require(actual.isNotBlank() && (requestedDraft == null || actual == requestedDraft))
                    handles[Key(view, actual)] = opened
                    selected[view] = actual
                    opened
                } catch (failure: Exception) { opened.close(); throw failure }
            }.also { selected[view] = snapshot(view, it).getJSONObject("draft_ref").getString("draft_id") }
        } else {
            val draft = requestedDraft ?: checkNotNull(selected[view])
            check(draft == selected[view])
            checkNotNull(handles[Key(view, draft)])
        }
        check(scopes.matches(session, project, scope.generation))
        check(snapshot(view, handle).getJSONObject("draft_ref").getString("draft_id") == selected[view])
        if (method in setOf("development_preview_proposal", "development_accept_proposal", "development_reject_proposal", "development_lookup_proposal")) {
            val request = input.getString("request_id")
            val result = when (method) {
                "development_lookup_proposal" -> handle.recoverProposal(request)
                "development_preview_proposal" -> handle.previewProposal(request, session, checkNotNull(credentialGeneration))
                "development_accept_proposal" -> handle.acceptProposal(request, session, checkNotNull(credentialGeneration), input.getString("review_digest"))
                else -> handle.rejectProposal(request, session, checkNotNull(credentialGeneration), input.getString("review_digest"))
            }
            if (method == "development_accept_proposal" || (method == "development_lookup_proposal" && result.optString("status") == "saved")) {
                val current = snapshot(view, handle)
                val actual = current.getJSONObject("draft_ref").getString("draft_id")
                check(result.getString("draft_id") == actual)
                result.put("snapshot", current)
                handles.keys.filter { it.view == view && handles[it] === handle }.forEach { handles.remove(it) }
                reviews.keys.removeAll { it.view == view }
                handles.put(Key(view, actual), handle)?.takeIf { it !== handle }?.close()
                selected[view] = actual
            }
            return result.put("scope_generation", scope.generation)
        }
        val result = JSONObject().put("scope_generation", scope.generation)
        when (method) {
            "development_open" -> Unit
            "development_update" -> {
                val revision = input.get("expected_revision").let {
                    require(it is String || it is Int || it is Long)
                    it.toString().also { value -> require(Regex("0|[1-9][0-9]{0,19}").matches(value)) }
                }
                when (input.getString("action")) {
                    "set_name" -> handle.setProjectName(input.getString("text"), revision)
                    "add_item" -> handle.addItem(input.getString("kind"), input.getString("text"), revision)
                    "edit_item" -> handle.editItem(input.getString("item_id"), input.getString("text"), revision)
                    "choose_new_project" -> handle.chooseNewProject(revision)
                    else -> throw IllegalArgumentException("development_action_unavailable")
                }
                reviews.remove(Key(view, checkNotNull(selected[view])))
            }
            "development_prepare_project" -> {
                val prepared = handle.prepareProject()
                val plan = prepared.getJSONObject("plan")
                val digest = prepared.getString("binding_digest").also { require(it.isNotBlank()) }
                reviews[Key(view, checkNotNull(selected[view]))] = Review(plan.getString("plan_id"), digest)
                result.put("plan", plan).put("binding_digest", digest)
            }
            "development_confirm_project" -> {
                val planId = input.getString("plan_id")
                val digest = input.getString("binding_digest")
                check(reviews[Key(view, checkNotNull(selected[view]))] == Review(planId, digest))
                result.put("original", handle.confirmProject(planId, digest))
            }
            "development_lookup_original" -> result.put("original", handle.recoverOriginal())
            else -> throw IllegalArgumentException("development_operation_unavailable")
        }
        return result.put("snapshot", snapshot(view, handle))
    }

    @Synchronized fun release(session: String) {
        handles.keys.filter { it.view.session == session }.forEach { key ->
            runCatching { handles.remove(key)?.close() }
        }
        selected.keys.removeAll { it.session == session }
        reviews.keys.removeAll { it.view.session == session }
    }
    @Synchronized override fun close() {
        closed = true
        handles.values.forEach { runCatching { it.close() } }
        handles.clear(); selected.clear(); reviews.clear()
    }
}
