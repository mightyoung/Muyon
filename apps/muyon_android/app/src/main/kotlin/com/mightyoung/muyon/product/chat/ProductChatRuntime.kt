package com.mightyoung.muyon.product.chat

import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Native calls are private Service ports, never named UI/model methods. */
interface ProductChatPort {
    fun configure(settings: JSONObject): JSONObject
    fun prepare(conversation: String, text: String, search: Boolean, count: Int): JSONObject
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
class ProductChatRuntime(private val port: ProductChatPort) : AutoCloseable {
    private val control = Executors.newSingleThreadExecutor()
    private val network = Executors.newSingleThreadExecutor()
    private val closed = AtomicBoolean(false)
    private val credentials = ProductCredentialVault()
    private val sendGate = ProductSendGate()
    private data class Plan(val session: String, val data: JSONObject)
    private data class ToolOrigin(val session: String, val generation: String, val project: String?, val scopeGeneration: Long)
    private val scopes = ProductScopeRegistry() // control only
    private val toolOrigins = mutableMapOf<String, ToolOrigin>() // control only
    private val businessPreviews = mutableMapOf<String, JSONObject>() // exact host plan per request
    private val plans = mutableMapOf<String, Plan>() // control thread only
    private val active = java.util.concurrent.ConcurrentHashMap<String, String>()
    private val cancelled = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
    private fun failure(code: String) = JSONObject().put("status", "unavailable").put("error", code)
    private fun unknown(request: String) = JSONObject().put("request_id", request).put("status", "unknown").put("recovery_action", "query_original")
    private fun operationFailure(error: Exception): JSONObject {
        val code = try { port.failureCode(error) } catch (_: Exception) { null }
        return failure(if (code in setOf("agent_budget_exhausted", "agent_budget_below_consumed", "agent_settings_invalid",
            "agent_configuration_unavailable", "agent_configuration_changed", "agent_credential_reinstall_required",
            "chat_text_denied", "search_query_denied", "search_request_invalid", "chat_disabled", "search_disabled",
            "hosted_cost_proof_unavailable", "search_price_proof_unavailable", "conversation_original_outcome_required",
            "agent_request_already_confirmed", "agent_request_not_found", "agent_dispatch_denied")) checkNotNull(code) else "chat_operation_unavailable")
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
        val result = port.prepare(conversation, text, search, count)
        val request = result.getString("request_id")
        if (!search) {
            port.bindScope(request, session, generation, project)
            toolOrigins[request] = ToolOrigin(session, generation, project, scope.generation)
        }
        plans[request] = Plan(session, JSONObject(result.toString()))
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
                ProductHttpsTransport().exchange(checkNotNull(payload), credential, dispatch.getString("purpose"), allowed) { write ->
                    if (!port.allowed(request, configuration, generation)) false
                    else sendGate.authorizeWrite(ticket, write)
                }
            }
            if (allowed()) port.settle(request, Charsets.UTF_8.newDecoder()
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
    fun budget(callback: (JSONObject) -> Unit) = submit(callback) { port.budget() }
    private fun toolOrigin(session: String, request: String): ToolOrigin {
        val origin = checkNotNull(toolOrigins[request])
        check(origin.session == session && origin.generation == credentials.current() && scopes.matches(session, origin.project, origin.scopeGeneration))
        return origin
    }
    fun updateScope(session: String, project: String?, callback: (JSONObject) -> Unit) = submit(callback) {
        require(session.isNotEmpty())
        if (scopes.get(session)?.project != project || scopes.get(session) == null) {
            sendGate.invalidateSessionScope(session)
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
        plan
    }
    fun cancel(session: String, request: String, callback: (JSONObject) -> Unit) {
        submit(callback) {
            // Check ownership on the same control queue as plan→active changes,
            // before revocation can affect another session's in-flight ticket.
            val owner = active[request]
            val plan = plans[request]
            if ((owner != null && owner != session) || (plan != null && plan.session != session)) return@submit failure("chat_session_mismatch")
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
