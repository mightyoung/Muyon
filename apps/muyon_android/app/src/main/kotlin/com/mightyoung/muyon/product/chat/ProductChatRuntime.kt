package com.mightyoung.muyon.product.chat

import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Native calls are private Service ports, never named UI/model methods. */
interface ProductChatPort {
    fun configure(settings: JSONObject): JSONObject
    fun prepare(conversation: String, text: String, search: Boolean, count: Int): JSONObject
    fun prepareScoped(conversation: String, text: String, search: Boolean, count: Int, session: String, project: String?): JSONObject = prepare(conversation, text, search, count)
    fun confirm(request: String, configuration: String): JSONObject
    fun claim(request: String, configuration: String, generation: String): JSONObject
    fun allowed(request: String, configuration: String, generation: String): Boolean
    fun settle(request: String, body: String): JSONObject
    fun lookup(request: String): JSONObject
    fun cancel(request: String): JSONObject
    fun budget(): JSONObject
    fun diagnostic(request: String, stage: String, httpStatus: Int?)
    /** Return only a generated native error-code field, never Throwable.message. */
    fun failureCode(failure: Exception): String? = null
    fun bindScope(request: String, session: String, generation: String, project: String?)
    fun reviewRead(request: String, session: String, generation: String, project: String?): JSONObject
    fun approveRead(request: String, session: String, generation: String, project: String?, digest: String): JSONObject
    fun prepareSuggestion(request: String, session: String, generation: String, project: String?): JSONObject
    fun reviewSuggestion(request: String, session: String, generation: String, project: String?, planId: String): JSONObject
    fun approveSuggestion(request: String, session: String, generation: String, project: String?, planId: String, digest: String): JSONObject
    fun followup(request: String, session: String, generation: String, project: String?): JSONObject
    fun confirmBusinessPlan(request: String, session: String, generation: String, project: String?, planId: String): JSONObject
    fun discardBusinessPlan(session: String, planId: String)
    fun workflow(action: JSONObject, session: String, conversation: String, project: String?): JSONObject = throw UnsupportedOperationException()
    fun workflowPrepare(run: String, session: String, conversation: String, project: String?, generation: String): JSONObject = throw UnsupportedOperationException()
}

/** Extracted from the existing temporary credential port. Memory-only and no
 * stringify/persistence API; only an opaque generation crosses native calls. */
internal class ProductCredentialVault {
    private var key: CharArray? = null
    private var generation: String? = null
    private var closed = false
    @Synchronized fun install(input: CharArray, next: String) {
        check(!closed)
        require(input.size in 16..512 && input.all { it.code in 33..126 })
        val copy = input.copyOf()
        key?.fill('\u0000'); key = copy; generation = next
    }
    @Synchronized fun current(): String? = generation
    fun <T> withCopy(expected: String, block: (CharArray) -> T): T {
        val copy = synchronized(this) { check(generation == expected); checkNotNull(key).copyOf() }
        return try { block(copy) } finally { copy.fill('\u0000') }
    }
    @Synchronized fun close() { closed = true; key?.fill('\u0000'); key = null; generation = null }
}

/** Product-specific owner; history/caps/holds live exclusively in the new Rust
 * ledger. No old canary profile, key, grant, batch or reservation is loaded.
 * Configuring does not send. Confirming a blocked plan cannot reserve or send.
 */
internal fun interface ProductChatExchange {
    fun exchange(payload: ByteArray, credential: CharArray, purpose: String,
        allowed: () -> Boolean, authorizeAndWrite: ((() -> Unit) -> Boolean)): ByteArray
}

class ProductChatRuntime internal constructor(private val port: ProductChatPort,
    private val transport: ProductChatExchange = ProductChatExchange { payload, credential, purpose, allowed, write ->
        ProductHttpsTransport().exchange(payload, credential, purpose, allowed, write)
    }) : AutoCloseable {
    private val control = Executors.newSingleThreadExecutor()
    private val network = Executors.newSingleThreadExecutor()
    private val closed = AtomicBoolean(false)
    private val credentials = ProductCredentialVault()
    private val sendGate = ProductSendGate()
    private data class Plan(val session: String, val data: JSONObject)
    private data class ToolOrigin(val session: String, val generation: String, val project: String?, val scopeGeneration: Long, val skillId: String? = null, val conversation: String? = null)
    private val scopes = ProductScopeRegistry() // control only
    private val toolOrigins = mutableMapOf<String, ToolOrigin>() // control only
    private val businessPreviews = mutableMapOf<String, JSONObject>() // exact host plan per request
    private val plans = mutableMapOf<String, Plan>() // control thread only
    private data class ReadOrigin(val session: String, val conversation: String,
        val requestConversation: String, val project: String?, val generation: Long)
    // Display provenance only. Never used to authorize a write or infer a card binding.
    private val readOrigins = linkedMapOf<String, ReadOrigin>() // control only; bounded
    private fun rememberReadOrigin(session: String, conversation: String, plan: JSONObject) {
        val scope = scopes.get(session) ?: return
        val request = (plan.opt("request_id") as? String)?.takeIf { it.isNotBlank() } ?: return
        val requestConversation = (plan.opt("conversation_id") as? String)?.takeIf { it.isNotBlank() } ?: return
        if (request in readOrigins) { readOrigins.remove(request); return } // ambiguous display provenance
        // Eviction removes display availability only; never block business prepare.
        if (readOrigins.size >= 256) readOrigins.remove(readOrigins.keys.first())
        readOrigins[request] = ReadOrigin(session, conversation, requestConversation, scope.project, scope.generation)
    }
    private val active = java.util.concurrent.ConcurrentHashMap<String, String>()
    private val cancelled = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
    private var configurationReady = false // control queue only
    private fun failure(code: String) = JSONObject().put("status", "unavailable").put("error", code)
    private fun unknown(request: String) = JSONObject().put("request_id", request).put("status", "unknown").put("recovery_action", "query_original")
    private fun operationFailure(error: Exception): JSONObject {
        val code = try { port.failureCode(error) } catch (_: Exception) { null }
        return failure(if ((code?.startsWith("workflow_") == true && code.length <= 80) || code in setOf("agent_budget_exhausted", "agent_budget_below_consumed", "agent_settings_invalid",
            "agent_configuration_unavailable", "agent_configuration_changed", "agent_credential_reinstall_required",
            "chat_text_denied", "search_query_denied", "search_request_invalid", "chat_disabled", "search_disabled",
            "hosted_cost_proof_unavailable", "search_price_proof_unavailable", "conversation_original_outcome_required",
            "agent_request_already_confirmed", "agent_request_not_found", "agent_dispatch_denied", "chat_tool_history_review_required")) checkNotNull(code) else "chat_operation_unavailable")
    }
    private fun submit(callback: (JSONObject) -> Unit, action: () -> JSONObject) {
        if (closed.get()) { callback(failure("chat_closed")); return }
        try { control.execute { if (closed.get()) callback(failure("chat_closed")) else callback(try { action() } catch (failure: Exception) { operationFailure(failure) }) } }
        catch (_: java.util.concurrent.RejectedExecutionException) { callback(failure("chat_closed")) }
    }

    /** Called only after visible settings review. Credential stays in a private
     * Binder CharArray; never put it into JSON, native arguments or saved state. */
    fun configure(session: String, input: CharArray, capMicroCny: String, maxCalls: String, chat: Boolean, search: Boolean, callback: (JSONObject) -> Unit) {
        if (closed.get()) { input.fill('\u0000'); callback(failure("chat_closed")); return }
        submit({ result -> input.fill('\u0000'); callback(result) }) {
            try {
                require(session.isNotEmpty() && input.size in 16..512 && input.all { it.code in 33..126 })
                val generation = UUID.randomUUID().toString()
                configurationReady = false
                val gateGeneration = sendGate.invalidateConfiguration()
                businessPreviews.toMap().forEach { (request, preview) ->
                    val owner = toolOrigins[request]?.session
                    if (owner != null) try { port.discardBusinessPlan(owner, preview.getString("plan_id")) } catch (_: Exception) { }
                }
                businessPreviews.clear(); toolOrigins.clear()
                val settings = JSONObject().put("credential_generation", generation).put("cap_micro_cny", capMicroCny)
                    .put("max_calls", maxCalls).put("chat", chat).put("search", search)
                    .put("price_revision", "product-deepseek-cny-2-8-search5000-v1")
                val result = port.configure(settings)
                check(result.has("id"))
                credentials.install(input, generation)
                sendGate.activateConfiguration(gateGeneration)
                configurationReady = true
                plans.clear()
                businessPreviews.clear()
                result.put("credential_persistence", "service_memory_only").put("pricing_proof", "unavailable")
            } finally { input.fill('\u0000') }
        }
    }
    fun prepare(session: String, conversation: String, text: String, search: Boolean, count: Int, project: String?, callback: (JSONObject) -> Unit) = submit(callback) {
        require(session.isNotEmpty() && plans.size < 128 && toolOrigins.size < 256)
        val scope = checkNotNull(scopes.get(session))
        check(scope.project == project)
        val generation = checkNotNull(credentials.current())
        val result = port.prepareScoped(conversation, text, search, count, session, project)
        val request = result.getString("request_id")
        if (!search) {
            port.bindScope(request, session, generation, project)
            toolOrigins[request] = ToolOrigin(session, generation, project, scope.generation)
        }
        plans[request] = Plan(session, JSONObject(result.toString()))
        rememberReadOrigin(session, conversation, result)
        result
    }
    /** Workflow scope is obtained from this same serialized, selected session. */
    fun workflow(session: String, conversation: String, action: JSONObject, callback: (JSONObject) -> Unit) = submit(callback) {
        val scope = checkNotNull(scopes.get(session))
        val revoking = action.optString("action") == "set_skill" && !action.optBoolean("enabled", true)
        if (revoking) {
            // Linearize local revocation against the final socket-write gate
            // before durably disabling the skill. Followups inherit this origin.
            toolOrigins.filterValues { it.conversation == conversation && it.project == scope.project && it.skillId == action.optString("skill_id") }
                .keys.toList().forEach { request ->
                    sendGate.cancel(request); cancelled.add(request)
                    port.cancel(request) // revoke prepared/native authority before skill mutation too
                }
        }
        val result = port.workflow(action, session, conversation, scope.project)
        if (action.optString("action") == "cancel" || revoking) {
            val requests = result.optJSONArray("remote_request_ids")
            for (index in 0 until (requests?.length() ?: 0)) {
                val request = requireNotNull(requests).getString(index)
                if (!revoking) check(productRequestOwnedBy(session, active[request], plans[request]?.session, toolOrigins[request]?.session))
                sendGate.cancel(request); cancelled.add(request); plans.remove(request)
                businessPreviews.remove(request)?.optString("plan_id")?.let { port.discardBusinessPlan(session, it) }
                toolOrigins.remove(request)
                port.cancel(request) // actual state remains authoritative; no invented refund/terminal status
            }
        }
        result
    }
    fun workflowPrepare(session: String, conversation: String, run: String, callback: (JSONObject) -> Unit) = submit(callback) {
        require(plans.size < 128 && toolOrigins.size < 256)
        val scope = checkNotNull(scopes.get(session))
        val generation = checkNotNull(credentials.current())
        val result = port.workflowPrepare(run, session, conversation, scope.project, generation)
        val request = result.getString("request_id")
        plans[request] = Plan(session, JSONObject(result.toString()))
        toolOrigins[request] = ToolOrigin(session, generation, scope.project, scope.generation, result.optString("skill_id").takeIf { it.isNotBlank() }, conversation)
        rememberReadOrigin(session, conversation, result)
        result
    }
    /** The request must be this live Binder session's exact reviewed plan. The
     * Service must route only its visible confirmation action here. */
    fun confirm(session: String, request: String, callback: (JSONObject) -> Unit) {
        submit(callback) {
            val plan = checkNotNull(plans[request]); check(plan.session == session)
            if (!plan.data.optBoolean("send_allowed", false)) return@submit failure(plan.data.optString("blocked_reason", "pricing_proof_unavailable"))
            val generation = checkNotNull(credentials.current())
            val configuration = plan.data.getString("configuration_id")
            plans.remove(request) // one UI confirmation, never replay on a lost callback
            val ticket = sendGate.register(request, session)
            try {
                port.confirm(request, configuration)
                val dispatch = port.claim(request, configuration, generation)
                active[request] = session
                try { network.execute { exchange(request, configuration, generation, dispatch, ticket) } }
                catch (_: java.util.concurrent.RejectedExecutionException) { active.remove(request); sendGate.finish(ticket) }
            } catch (failure: Exception) { sendGate.finish(ticket); throw failure }
            unknown(request)
        }
    }
    private fun exchange(request: String, configuration: String, generation: String, dispatch: JSONObject, ticket: ProductSendGate.Ticket) {
        var response: ByteArray? = null
        var payload: ByteArray? = null
        try {
            // Watchdog uses only nonblocking local reads. Native permission is
            // checked separately, never under sendGate or on the watchdog.
            val allowed = { !closed.get() && request !in cancelled && active.containsKey(request) && sendGate.advisoryAllowed(ticket) }
            check(port.allowed(request, configuration, generation))
            payload = dispatch.getString("payload").toByteArray(Charsets.UTF_8)
            response = credentials.withCopy(generation) { credential ->
                transport.exchange(checkNotNull(payload), credential, dispatch.getString("purpose"), allowed) { write ->
                    if (!port.allowed(request, configuration, generation)) false
                    else sendGate.authorizeWrite(ticket, write)
                }
            }
            // A complete validated provider response must reach durable accounting
            // even when cancellation happened after the sole write. Rust records
            // the charge while suppressing cancelled answers; no redispatch occurs.
            port.settle(request, Charsets.UTF_8.newDecoder()
                .onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
                .onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT)
                .decode(java.nio.ByteBuffer.wrap(checkNotNull(response))).toString())
        } catch (failure: ProductHttpsFailure) {
            try { port.diagnostic(request, failure.stage.name, failure.httpStatus) } catch (_: Exception) { }
        } catch (_: Exception) {
            try { port.diagnostic(request, ProductFailureStage.RESPONSE_VALIDATION.name, null) } catch (_: Exception) { }
            // Unknown retains the native hold. No retries, refunds, alternate
            // endpoint, credential fallback or parsing of raw failure text.
        } finally { response?.fill(0); payload?.fill(0); active.remove(request); cancelled.remove(request); sendGate.finish(ticket) }
    }
    fun lookup(session: String, request: String, callback: (JSONObject) -> Unit) = submit(callback) { require(session.isNotEmpty()); port.lookup(request) }
    /** Bounded read-only observation. Workspace is supplied by the Service, while
     * caller-supplied conversation/project/generation must match the captured origin.
     * This is not ComponentSnapshot/CardBinding: missing core identity remains null.
     * The shell must also compare returned scope with its still-mounted view.
     * No automatic recovery of old unknown requests or mutation takes place here. */
    fun readSnapshot(session: String, workspace: String, conversation: String, request: String,
        project: String?, generation: Long, callback: (JSONObject) -> Unit) = submit(callback) {
        val origin = readOrigins[request]
        if (workspace.isBlank() || origin == null || origin.session != session ||
            origin.conversation != conversation || origin.project != project || origin.generation != generation ||
            !scopes.matches(session, project, generation)) return@submit failure("snapshot_scope_unavailable")
        val observation = port.lookup(request) // original local lookup only, never dispatch
        if (observation.opt("request_id") != request) return@submit failure("snapshot_identity_mismatch")
        val rawStatus = (observation.opt("status") as? String)?.takeIf { it in setOf(
            "prepared", "reserved", "unknown", "tool_pending", "tool_consumed", "completed", "failed", "cancelled", "pending") }
        fun micro(key: String): Any = (observation.opt(key) as? String)
            ?.takeIf { it.length <= 20 && it.matches(Regex("0|[1-9][0-9]*")) && it.toULongOrNull() != null } ?: JSONObject.NULL
        val cancelledFact = observation.opt("cancelled") as? Boolean
        val attemptedFact = observation.opt("attempted") as? Boolean
        // Native charged defaults to zero, including unresolved unknown requests.
        // Only completed + actual dispatch has a validated-settlement invariant
        // in AgentOwner::settle_response. Other statuses are conservatively
        // unavailable in this projection; cancelled mixes pre-send and settled.
        val actualCharge = if (rawStatus == "completed" && attemptedFact == true)
            micro("charged_micro_cny") else JSONObject.NULL
        val execution = when (rawStatus) {
            "completed", "failed", "cancelled" -> rawStatus
            "unknown" -> "unknown"
            else -> "unavailable" // local prepared/reserved/tool-pending is not running proof
        }
        JSONObject().put("schema_version", 1).put("status", "read_only")
            .put("scope", JSONObject().put("workspace_id", workspace).put("conversation_id", origin.conversation)
                .put("project_id", origin.project ?: JSONObject.NULL).put("generation", origin.generation)
                .put("agent_id", JSONObject.NULL))
            .put("original_request", JSONObject().put("request_id", request)
                .put("request_conversation_id", origin.requestConversation).put("intent_id", JSONObject.NULL))
            .put("observation", JSONObject().put("status", rawStatus ?: JSONObject.NULL)
                .put("execution_status", execution).put("reserved_micro_cny", micro("reserved_micro_cny"))
                .put("charged_micro_cny", actualCharge)
                .put("cancelled", cancelledFact ?: JSONObject.NULL)
                .put("attempted", attemptedFact ?: JSONObject.NULL)
                .put("cancellation_status", if (rawStatus == "cancelled") "confirmed_cancelled"
                    else if (cancelledFact == true) "intent_recorded_outcome_unknown" else "unavailable")
                .put("current_business_state", JSONObject.NULL))
            .put("binding", JSONObject.NULL).put("capabilities", JSONArray())
            .put("unavailable", JSONArray(listOf("agent_id", "message_id", "component_id", "component_revision",
                "state_revision", "attempt_id", "host_digest", "intent_id", "task_snapshot", "source_snapshot")))
    }
    fun budget(callback: (JSONObject) -> Unit) = submit(callback) { port.budget() }
    fun availability(base: JSONObject, callback: (JSONObject) -> Unit) = submit(callback) {
        JSONObject(base.toString()).put("configured", configurationReady && credentials.current() != null)
    }
    private fun toolOrigin(session: String, request: String): ToolOrigin {
        val origin = checkNotNull(toolOrigins[request])
        check(origin.session == session && origin.generation == credentials.current() && scopes.matches(session, origin.project, origin.scopeGeneration))
        return origin
    }
    fun updateScope(session: String, project: String?, callback: (JSONObject) -> Unit) = submit(callback) {
        require(session.isNotEmpty())
        if (scopes.get(session)?.project != project || scopes.get(session) == null) {
            sendGate.invalidateSessionScope(session)
            readOrigins.entries.removeAll { it.value.session == session }
            val requests = (toolOrigins.filterValues { it.session == session }.keys + plans.filterValues { it.session == session }.keys + active.filterValues { it == session }.keys).toSet()
            requests.forEach { request ->
                cancelled.add(request)
                try { port.cancel(request) } catch (_: Exception) { /* Preserve unknown. */ }
                businessPreviews.remove(request)?.optString("plan_id")?.let { plan ->
                    try { port.discardBusinessPlan(session, plan) } catch (_: Exception) { }
                }
                toolOrigins.remove(request); plans.remove(request)
            }
        }
        val scope = scopes.update(session, project)
        JSONObject().put("status", "scope_updated").put("project_id", project ?: JSONObject.NULL).put("scope_generation", scope.generation)
    }
    /** Local-only review; never sends the resulting business data. */
    fun reviewRead(session: String, request: String, callback: (JSONObject) -> Unit) = submit(callback) {
        val scope = toolOrigin(session, request)
        port.reviewRead(request, session, scope.generation, scope.project)
    }
    fun approveRead(session: String, request: String, digest: String, callback: (JSONObject) -> Unit) = submit(callback) {
        val scope = toolOrigin(session, request)
        port.approveRead(request, session, scope.generation, scope.project, digest)
    }
    fun prepareSuggestion(session: String, request: String, callback: (JSONObject) -> Unit) = submit(callback) {
        val scope = toolOrigin(session, request)
        businessPreviews[request]?.let { return@submit JSONObject(it.toString()) }
        port.prepareSuggestion(request, session, scope.generation, scope.project).also {
            check(it.has("plan_id") && it.has("business_preview"))
            businessPreviews[request] = JSONObject(it.toString())
        }
    }
    /** This is exclusively the distinct visible P04 business confirmation. */
    fun confirmSuggestion(session: String, request: String, planId: String, callback: (JSONObject) -> Unit) = submit(callback) {
        val scope = toolOrigin(session, request)
        check(businessPreviews[request]?.optString("plan_id") == planId)
        val original = port.lookup(request)
        check(original.optString("status") == "tool_pending" && !original.optBoolean("cancelled", true))
        businessPreviews.remove(request) // unknown confirmation is query-only
        port.confirmBusinessPlan(request, session, scope.generation, scope.project, planId)
        // An unknown original receipt makes this fail closed; never retry write.
        port.reviewSuggestion(request, session, scope.generation, scope.project, planId)
    }
    fun reviewSuggestion(session: String, request: String, planId: String, callback: (JSONObject) -> Unit) = submit(callback) {
        val scope = toolOrigin(session, request)
        port.reviewSuggestion(request, session, scope.generation, scope.project, planId)
    }
    fun approveSuggestion(session: String, request: String, planId: String, digest: String, callback: (JSONObject) -> Unit) = submit(callback) {
        val scope = toolOrigin(session, request)
        port.approveSuggestion(request, session, scope.generation, scope.project, planId, digest)
    }
    /** Only prepares an independent follow-up plan; never automatically confirms
     * or dispatches another HTTP request after a tool or business confirmation. */
    fun followup(session: String, request: String, callback: (JSONObject) -> Unit) = submit(callback) {
        val scope = toolOrigin(session, request)
        val plan = port.followup(request, session, scope.generation, scope.project)
        val next = plan.getString("request_id")
        toolOrigins[next] = scope
        plans[next] = Plan(session, JSONObject(plan.toString()))
        readOrigins[request]?.let { rememberReadOrigin(session, it.conversation, plan) }
        plan
    }
    fun cancel(session: String, request: String, callback: (JSONObject) -> Unit) {
        submit(callback) {
            // Check ownership on the same control queue as plan→active changes,
            // before revocation can affect another session's in-flight ticket.
            val owner = active[request]
            val plan = plans[request]
            val toolOwner = toolOrigins[request]?.session
            if (!productRequestOwnedBy(session, owner, plan?.session, toolOwner)) return@submit failure("chat_session_mismatch")
            sendGate.cancel(request)
            cancelled.add(request)
            plans.remove(request)
            toolOrigins.remove(request)
            businessPreviews.remove(request)?.optString("plan_id")?.let { planId ->
                try { port.discardBusinessPlan(session, planId) } catch (_: Exception) { }
            }
            port.cancel(request)
        }
    }
    fun releaseSession(session: String) {
        sendGate.releaseSession(session)
        val requests = active.filterValues { it == session }.keys.toList()
        requests.forEach { cancelled.add(it) }
        if (!closed.get()) submit({}) {
            (requests + plans.filterValues { it.session == session }.keys).distinct().forEach { request ->
                try { port.cancel(request) } catch (_: Exception) { /* Unknown remains held. */ }
            }
            plans.entries.removeAll { it.value.session == session }
            toolOrigins.filterValues { it.session == session }.keys.toList().forEach { request ->
                businessPreviews.remove(request)?.optString("plan_id")?.let { planId -> try { port.discardBusinessPlan(session, planId) } catch (_: Exception) { } }
                toolOrigins.remove(request)
            }
            readOrigins.entries.removeAll { it.value.session == session }
            scopes.release(session)
            JSONObject().put("status", "released")
        }
    }
    override fun close() {
        sendGate.close()
        if (!closed.compareAndSet(false, true)) return
        active.keys.forEach { cancelled.add(it) }
        credentials.close()
        control.shutdown(); network.shutdown()
    }
    /** Invoke on the Service destroy worker before closing native state. A
     * timeout means native ownership must be retained until a later drain;
     * shutdown alone is not proof that callbacks have finished. */
    fun awaitDrain(timeoutMillis: Long): Boolean {
        require(timeoutMillis in 1..10_000)
        if (!closed.get()) return false
        val deadline = System.nanoTime() + java.util.concurrent.TimeUnit.MILLISECONDS.toNanos(timeoutMillis)
        if (!control.awaitTermination(timeoutMillis, java.util.concurrent.TimeUnit.MILLISECONDS)) return false
        val remaining = deadline - System.nanoTime()
        return remaining > 0 && network.awaitTermination(remaining, java.util.concurrent.TimeUnit.NANOSECONDS)
    }
}
