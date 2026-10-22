package com.mightyoung.muyon.product.ui.shell

import org.json.JSONObject

data class HostSetupScope(val workspace: String, val conversation: String, val project: String?, val generation: Long)
data class HostRoleSuggestion(val requestId: String, val role: String, val sourceId: String, val sourceVersion: Long, val label: String)
data class HostSetupSnapshot(val scope: HostSetupScope, val id: String, val revision: Long, val reducerRevision: Long,
    val step: String, val name: String, val purpose: String, val role: String, val cancelled: Boolean,
    val operations: Set<String>, val suggestion: HostRoleSuggestion?)
fun canAcceptHostSuggestion(value: HostSetupSnapshot, buffer: String): Boolean =
    value.suggestion != null && "accept_role" in value.operations && buffer == value.role

private val localSetupOperations = setOf("open", "read", "edit_name", "edit_purpose", "edit_role",
    "next", "back", "cancel", "resume", "suggest_role", "accept_role")

/** Strict passive view projection. Backend/local reducer remains the only flow-state owner. */
fun decodeHostSetup(data: JSONObject, expected: HostSetupScope): HostSetupSnapshot? {
    fun integer(value: Any?): Long? = when (value) { is Int -> value.toLong(); is Long -> value; else -> null }
    fun text(objectValue: JSONObject, key: String, limit: Int, blank: Boolean = false): String? {
        val value = objectValue.opt(key) as? String ?: return null
        if (value.length > limit || (!blank && value.isBlank()) || '\u0000' in value) return null
        var index = 0
        while (index < value.length) {
            val c = value[index++]
            if (Character.isHighSurrogate(c)) {
                if (index >= value.length || !Character.isLowSurrogate(value[index++])) return null
            } else if (Character.isLowSurrogate(c)) return null
        }
        return value
    }
    if (expected.workspace.isBlank() || expected.conversation.isBlank() || expected.generation < 0 ||
        integer(data.opt("schema_version")) != 1L || data.opt("status") != "local_only" || data.opt("projection_type") != "setup_draft") return null
    val scope = data.optJSONObject("scope") ?: return null
    if (scope.opt("workspace_id") != expected.workspace || scope.opt("conversation_id") != expected.conversation ||
        !scope.has("project_id") || (if (scope.isNull("project_id")) null else scope.opt("project_id")) != expected.project ||
        integer(scope.opt("generation")) != expected.generation) return null
    if (listOf("saved", "can_save", "can_create", "can_start").any { data.opt(it) != false } ||
        listOf("agent_id", "intent_id", "actual_micro_cny", "reserved_micro_cny", "binding").any { !data.has(it) || !data.isNull(it) } ||
        data.opt("creation_status") != "not_requested" ||
        data.opt("capability_metadata_status") != "unavailable" || data.opt("material_metadata_status") != "unavailable" ||
        data.optJSONArray("allowed_capabilities")?.length() != 0 || data.optJSONArray("allowed_materials")?.length() != 0) return null
    val id = text(data, "local_draft_id", 80) ?: return null
    val revision = integer(data.opt("local_revision"))?.takeIf { it >= 0 } ?: return null
    val reducerRevision = integer(data.opt("reducer_revision"))?.takeIf { it >= 0 } ?: return null
    val step = text(data, "step", 32)?.takeIf { it in setOf("NAME", "PURPOSE", "CONFIGURATION", "REVIEW") } ?: return null
    val name = text(data, "name", 60, true) ?: return null
    val purpose = text(data, "purpose", 8000, true) ?: return null
    val role = text(data, "role", 160, true) ?: return null
    val cancelled = data.opt("cancelled") as? Boolean ?: return null
    val array = data.optJSONArray("supported_local_operations") ?: return null
    if (array.length() > localSetupOperations.size) return null
    val operations = (0 until array.length()).map { array.opt(it) as? String ?: return null }
    if (operations.distinct().size != operations.size || operations.any { it !in localSetupOperations } ||
        (cancelled && operations.any { it !in setOf("open", "read", "resume") })) return null
    val suggestion = if (data.has("suggestion") && data.isNull("suggestion")) null else {
        val value = data.optJSONObject("suggestion") ?: return null
        HostRoleSuggestion(text(value, "request_id", 128) ?: return null, text(value, "role", 160) ?: return null,
            text(value, "source_id", 128) ?: return null, integer(value.opt("source_version"))?.takeIf { it > 0 } ?: return null,
            text(value, "source_label", 256) ?: return null)
    }
    return HostSetupSnapshot(expected, id, revision, reducerRevision, step, name, purpose, role, cancelled, operations.toSet(), suggestion)
}

/** No local reducer, port, create, save or execution seam. Calls are finite in-memory host operations. */
class HostSetupController(private val scope: HostSetupScope,
    private val call: (String, JSONObject, (JSONObject) -> Unit) -> Unit, private val changed: () -> Unit, initial: HostSetupSnapshot? = null) {
    init { require(initial == null || initial.scope == scope) }
    @Volatile var snapshot: HostSetupSnapshot? = initial; private set
    @Volatile var busy = false; private set
    @Volatile var needsRead = initial != null; private set
    @Volatile var notice = ""; private set
    private var active = true
    private var serial = 0L
    private var unresolved: HostSetupSnapshot? = initial

    @Synchronized fun open() {
        if (!active || busy || needsRead) return
        request(JSONObject().put("action", "open"), snapshot, false)
    }
    @Synchronized fun readOriginal() {
        if (!active || busy) return
        val original = unresolved ?: snapshot ?: return
        request(JSONObject().put("action", "read").put("local_draft_id", original.id), original, false)
    }
    @Synchronized fun mutate(displayed: HostSetupSnapshot, action: String, value: String? = null, suggestionToken: String? = null): Boolean {
        if (!active || busy || needsRead) return false
        if (snapshot != displayed || displayed.scope != scope || displayed.revision == Long.MAX_VALUE ||
            action !in displayed.operations || action !in localSetupOperations || action in setOf("open", "read")) {
            notice = "显示的内存草稿或操作已失效，请读取原草稿后核对。"; changed(); return false
        }
        val edit = action in setOf("edit_name", "edit_purpose", "edit_role")
        if ((edit && value == null) || (!edit && value != null) ||
            (action == "accept_role" && (suggestionToken == null || suggestionToken != displayed.suggestion?.requestId)) ||
            (action != "accept_role" && suggestionToken != null)) return false
        val operation = JSONObject().put("action", action).put("local_draft_id", displayed.id)
            .put("expected_local_revision", displayed.revision)
        if (edit) operation.put("value", value)
        if (action == "accept_role") operation.put("suggestion_request_id", suggestionToken)
        request(operation, displayed, true)
        return true
    }
    private fun request(operation: JSONObject, expected: HostSetupSnapshot?, mutation: Boolean) {
        val token = ++serial
        busy = true; notice = ""; changed()
        val payload = JSONObject().put("conversation_id", scope.conversation).put("project_id", scope.project ?: JSONObject.NULL)
            .put("scope_generation", scope.generation).put("operation", operation)
        try {
            call("chat_setup_draft", payload) { reply -> receive(token, reply, expected, mutation) }
        } catch (_: Exception) { receive(token, JSONObject().put("status", "unknown"), expected, mutation) }
    }
    @Synchronized private fun receive(token: Long, reply: JSONObject, expected: HostSetupSnapshot?, mutation: Boolean) {
        if (!active || serial != token) return
        val data = reply.optJSONObject("data")
        val decoded = if (reply.opt("status") == "ok" && data != null) decodeHostSetup(data, scope) else null
        if (decoded == null || (expected != null && (decoded.id != expected.id || decoded.revision < expected.revision ||
                decoded.reducerRevision < expected.reducerRevision || (decoded.revision == expected.revision && decoded != expected) || (mutation && decoded.revision != expected.revision + 1)))) {
            unresolved = expected
            needsRead = expected != null
            notice = "内存操作未确认或快照失效；编辑文本保留。请读取原内存草稿，不会自动重试或替换身份。"
        } else {
            snapshot = decoded; unresolved = null; needsRead = false
        }
        // Publish completion only after the immutable snapshot/recovery fields are final.
        busy = false
        changed()
    }
    @Synchronized fun close() { active = false; serial++; busy = false }
}
