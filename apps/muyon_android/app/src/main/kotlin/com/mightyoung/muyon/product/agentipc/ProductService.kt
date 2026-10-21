package com.mightyoung.muyon.product.agentipc

import android.app.Service
import android.content.Intent
import android.os.*
import com.mightyoung.muyon.productbridge.ProductCore
import com.mightyoung.muyon.productbridge.ProductException
import android.util.Base64
import com.mightyoung.muyon.product.chat.ProductChatPort
import com.mightyoung.muyon.product.chat.ProductChatRuntime
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.io.File
import java.util.UUID

/** One private process owns the native business connection. No fixture fallback. */
class ProductService : Service() {
    companion object {
        private val retiringOwners = java.util.concurrent.ConcurrentHashMap<String, java.util.concurrent.CountDownLatch>()
    }
    // Freeze predecessors on the main lifecycle thread. Waiting on later owners
    // could form a cycle during rapid A -> B -> C Service recreation.
    private var predecessorDrains: List<java.util.concurrent.CountDownLatch> = emptyList()
    private lateinit var worker: HandlerThread
    private lateinit var handler: Handler
    private lateinit var messenger: Messenger
    private val epoch = UUID.randomUUID().toString()
    private val workspace = "local-workspace"
    private var core: ProductCore? = null
    private lateinit var chat: ProductChatRuntime
    private val clients = java.util.concurrent.ConcurrentHashMap<IBinder, String>()
    private val deaths = mutableMapOf<IBinder, IBinder.DeathRecipient>()
    private val planOwners = java.util.concurrent.ConcurrentHashMap<String, String>()
    private val toolPlans = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
    private val readerOwners = mutableMapOf<String, String>()
    @Volatile private var stopped = false

    override fun onCreate() {
        super.onCreate()
        predecessorDrains = retiringOwners.values.toList()
        worker = HandlerThread("MuyonProductCore").also { it.start() }
        handler = object : Handler(worker.looper) {
            override fun handleMessage(message: Message) { receive(message) }
        }
        messenger = Messenger(handler)
        chat = ProductChatRuntime(object : ProductChatPort {
            private fun data(raw: String) = nativeData(raw) as JSONObject
            override fun failureCode(failure: Exception): String? = (failure as? ProductException.Failure)?.code
            override fun configure(settings: JSONObject) = data(open(false).agentConfigure(settings.toString()))
            override fun prepare(conversation: String, text: String, search: Boolean, count: Int) = data(open(false).agentPrepare(conversation, text, search, count.toUInt()))
            override fun prepareScoped(conversation: String, text: String, search: Boolean, count: Int, session: String, project: String?): JSONObject {
                check(!stopped && clients.containsValue(session))
                return data(open(false).agentPrepareScoped(conversation,text,search,count.toUInt(),session,project))
            }
            override fun confirm(request: String, configuration: String) = data(open(false).agentConfirm(request, configuration))
            override fun claim(request: String, configuration: String, generation: String) = data(open(false).agentClaim(request, configuration, generation))
            override fun allowed(request: String, configuration: String, generation: String) = !stopped && open(false).agentAllowed(request, configuration, generation)
            override fun settle(request: String, body: String) = data(open(false).agentSettle(request, body))
            override fun diagnostic(request: String, stage: String, httpStatus: Int?) { open(false).agentDiagnostic(request, stage, httpStatus?.toUShort()) }
            override fun lookup(request: String) = data(open(false).agentLookup(request))
            override fun cancel(request: String) = data(open(false).agentCancel(request))
            override fun budget() = data(open(false).agentBudget())
            override fun workflow(action: JSONObject, session: String, conversation: String, project: String?): JSONObject {
                check(!stopped && clients.containsValue(session))
                return data(open(false).agentWorkflow(action.toString(), session, conversation, project))
            }
            override fun workflowPrepare(run: String, session: String, conversation: String, project: String?, generation: String): JSONObject {
                check(!stopped && clients.containsValue(session))
                return data(open(false).agentWorkflowPrepare(run, session, conversation, project, generation))
            }
            private fun tool(action: String, request: String, session: String, generation: String, project: String?, value: String = "", digest: String = ""): JSONObject {
                check(!stopped && clients.containsValue(session))
                val result = nativeData(open(false).agentToolStep(action, request, session, generation, project, value, digest))
                return if (action in setOf("bind", "approve_read", "approve_suggestion")) {
                    check(result === JSONObject.NULL)
                    JSONObject().put("approved", true)
                } else {
                    check(result is JSONObject)
                    result
                }
            }
            override fun bindScope(request: String, session: String, generation: String, project: String?) { tool("bind", request, session, generation, project) }
            override fun reviewRead(request: String, session: String, generation: String, project: String?) = tool("review_read", request, session, generation, project)
            override fun approveRead(request: String, session: String, generation: String, project: String?, digest: String) = tool("approve_read", request, session, generation, project, digest = digest)
            override fun prepareSuggestion(request: String, session: String, generation: String, project: String?): JSONObject {
                val result = tool("prepare_suggestion", request, session, generation, project)
                val plan = result.getString("plan_id")
                synchronized(this@ProductService) {
                    if (stopped || !clients.containsValue(session)) {
                        core?.discardPlan(plan)
                        throw IllegalStateException("stale_session")
                    }
                    planOwners[plan] = session
                    toolPlans.add(plan)
                }
                return result
            }
            override fun reviewSuggestion(request: String, session: String, generation: String, project: String?, planId: String) = tool("review_suggestion", request, session, generation, project, planId)
            override fun approveSuggestion(request: String, session: String, generation: String, project: String?, planId: String, digest: String) = tool("approve_suggestion", request, session, generation, project, planId, digest)
            override fun followup(request: String, session: String, generation: String, project: String?) = tool("followup", request, session, generation, project)
            override fun discardBusinessPlan(session: String, planId: String) = synchronized(this@ProductService) {
                check(planOwners[planId] == session)
                core?.discardPlan(planId)
                planOwners.remove(planId)
                toolPlans.remove(planId)
                Unit
            }
            override fun confirmBusinessPlan(request: String, session: String, generation: String, project: String?, planId: String): JSONObject = synchronized(this@ProductService) {
                check(!stopped && clients.containsValue(session) && planOwners[planId] == session && toolPlans.contains(planId))
                tool("confirm_suggestion", request, session, generation, project, planId)
            }
        })
    }
    override fun onBind(intent: Intent): IBinder = messenger.binder
    @Synchronized private fun open(initialize: Boolean): ProductCore {
        check(!stopped)
        core?.let { return it }
        val deadline = SystemClock.elapsedRealtime() + 10_000
        predecessorDrains.forEach { drain ->
            check(drain.await((deadline - SystemClock.elapsedRealtime()).coerceAtLeast(0), java.util.concurrent.TimeUnit.MILLISECONDS))
        }
        check(!stopped)
        val root = File(filesDir, "muyon-product-v2").absolutePath
        return ProductCore.open(root, workspace, epoch, initialize).also { core = it }
    }
    private fun error(code: String, status: String = "unknown") = JSONObject()
        .put("status", status).put("error", code).put("recovery_action", "query_original")
    @Synchronized private fun releaseClient(binder: IBinder, session: String) {
        if (clients[binder] != session) return
        clients.remove(binder)
        deaths.remove(binder)?.let { recipient -> runCatching { binder.unlinkToDeath(recipient, 0) } }
        chat.releaseSession(session)
        planOwners.filterValues { it == session }.keys.toList().forEach { plan ->
            runCatching { core?.discardPlan(plan) }; planOwners.remove(plan); toolPlans.remove(plan)
        }
        readerOwners.filterValues { it == session }.keys.toList().forEach { reader ->
            runCatching { core?.closeAttachment(reader) }; readerOwners.remove(reader)
        }
    }
    private fun nativeData(raw: String): Any {
        check(raw.toByteArray(Charsets.UTF_8).size <= 1_048_576)
        return JSONTokener(raw).nextValue()
    }
    private fun receive(message: Message) {
        val reply = message.replyTo ?: return
        val request = message.data.getString("request_id").orEmpty()
        if (!Regex("[A-Za-z0-9_-]{1,80}").matches(request)) return
        val response = try {
            if (stopped || message.sendingUid != Process.myUid()) {
                error("caller_refused", "rejected")
            } else {
                val method = message.data.getString("method").orEmpty()
                val raw = message.data.getString("payload") ?: "{}"
                if (!wellFormedUtf16(raw)) return send(reply, request, error("invalid_unicode", "rejected"))
                check(raw.length <= 1_048_576 && raw.toByteArray(Charsets.UTF_8).size <= 1_048_576)
                val payload = JSONObject(raw)
                if (!validWireJson(payload)) return send(reply, request, error("invalid_unicode", "rejected"))
                if (method == "connect") {
                    val session = clients.getOrPut(reply.binder) {
                        val id = UUID.randomUUID().toString()
                        val death = IBinder.DeathRecipient { handler.post {
                            releaseClient(reply.binder, id)
                        } }
                        reply.binder.linkToDeath(death, 0)
                        deaths[reply.binder] = death
                        id
                    }
                    JSONObject().put("status", "ok").put("data", JSONObject()
                        .put("session", session).put("epoch", epoch).put("workspace", workspace)
                        .put("initialized", File(filesDir, "muyon-product-v2/business-v2.sqlite").isFile))
                } else if (method == "disconnect") {
                    // Revocation is bound to this caller's Binder identity. It
                    // also works if close raced the connect reply (no lease yet
                    // known to the UI); it never grants or executes authority.
                    clients[reply.binder]?.let { releaseClient(reply.binder, it) }
                    JSONObject().put("status", "ok").put("data", JSONObject().put("released", true))
                } else if (clients[reply.binder] != message.data.getString("session") || message.data.getString("epoch") != epoch) {
                    error("stale_session", "rejected")
                } else {
                    val session = clients.getValue(reply.binder)
                    if (method in setOf("chat_configure", "chat_prepare", "chat_confirm", "chat_lookup", "chat_cancel", "chat_budget", "chat_scope", "chat_tool", "agent_workflow", "workflow_prepare")) {
                        val callback: (JSONObject) -> Unit = { result -> handler.post {
                            if (!stopped && clients[reply.binder] == session) send(reply, request,
                                JSONObject().put("status", "ok").put("data", result))
                        } }
                        when (method) {
                            "agent_workflow" -> chat.workflow(session, payload.getString("conversation_id"), payload.getJSONObject("operation"), callback)
                            "workflow_prepare" -> chat.workflowPrepare(session, payload.getString("conversation_id"), payload.getString("run_id"), callback)
                            "chat_configure" -> chat.configure(session, requireNotNull(message.data.getCharArray("credential")),
                                payload.getString("cap_micro_cny"), payload.getString("max_calls"), payload.getBoolean("chat"), payload.getBoolean("search"), callback)
                            "chat_prepare" -> chat.prepare(session, payload.getString("conversation_id"), payload.getString("text"),
                                payload.getBoolean("search"), payload.optInt("count", 5).also { check(it in 1..10) }, payload.optString("project_id").takeIf { it.isNotEmpty() }, callback)
                            "chat_confirm" -> chat.confirm(session, payload.getString("request_id"), callback)
                            "chat_lookup" -> chat.lookup(session, payload.getString("request_id"), callback)
                            "chat_cancel" -> chat.cancel(session, payload.getString("request_id"), callback)
                            "chat_budget" -> chat.budget(callback)
                            "chat_scope" -> chat.updateScope(session, payload.optString("project_id").takeIf { it.isNotEmpty() && it != "null" }, callback)
                            "chat_tool" -> when (payload.getString("action")) {
                                "review_read" -> chat.reviewRead(session, payload.getString("request_id"), callback)
                                "approve_read" -> chat.approveRead(session, payload.getString("request_id"), payload.getString("digest"), callback)
                                "prepare_suggestion" -> chat.prepareSuggestion(session, payload.getString("request_id"), callback)
                                "confirm_suggestion" -> chat.confirmSuggestion(session, payload.getString("request_id"), payload.getString("plan_id"), callback)
                                "review_suggestion" -> chat.reviewSuggestion(session, payload.getString("request_id"), payload.getString("plan_id"), callback)
                                "approve_suggestion" -> chat.approveSuggestion(session, payload.getString("request_id"), payload.getString("plan_id"), payload.getString("digest"), callback)
                                "followup" -> chat.followup(session, payload.getString("request_id"), callback)
                                else -> throw IllegalArgumentException("tool_action_invalid")
                            }
                        }
                        return
                    }
                    val limit = payload.optInt("limit", 10).also { check(it in 1..10) }.toUInt()
                    val offset = payload.optInt("offset", 0).also { check(it >= 0) }.toUInt()
                    val data: Any = when (method) {
                        "initialize" -> nativeData(open(true).health())
                        "health" -> nativeData(open(false).health()).also { (it as JSONObject).put("active_clients", clients.size).put("service_pid", Process.myPid()) }
                        "agent_availability" -> nativeData(open(false).agentAvailability())
                        "agent_read" -> nativeData(open(false).agentRead(payload.getJSONObject("request").toString(),
                            payload.optString("project_id").takeIf { it.isNotBlank() }))
                        "suppliers" -> nativeData(open(false).listSuppliers(limit, offset))
                        "deleted_suppliers" -> nativeData(open(false).listDeletedSuppliers(limit, offset))
                        "supplier" -> nativeData(open(false).supplier(payload.getString("id")))
                        "projects" -> nativeData(open(false).listProjects(limit, offset))
                        "papers" -> nativeData(open(false).listPapers(payload.getString("project_id"), limit, offset))
                        "sources" -> nativeData(open(false).researchSources(payload.getString("project_id")))
                        "paper" -> nativeData(open(false).paper(payload.getString("project_id"), payload.getString("paper_id")))
                        "begin_upload" -> nativeData(open(false).beginUpload(payload.getString("project_id")))
                        "append_upload" -> {
                            val bytes = Base64.decode(payload.getString("bytes"), Base64.NO_WRAP)
                            check(bytes.size <= 65536)
                            JSONObject().put("byte_length", open(false).appendUpload(payload.getString("upload_id"), bytes).toString())
                        }
                        "finish_upload" -> nativeData(open(false).finishUpload(payload.getString("upload_id"), payload.getString("kind")))
                        "lookup_upload" -> nativeData(open(false).lookupUpload(payload.getString("upload_id")))
                        "abort_upload" -> { open(false).abortUpload(payload.getString("upload_id")); JSONObject().put("aborted", true) }
                        "archive_manifest" -> nativeData(open(false).archiveManifest(payload.getString("upload_id")))
                        "seal_snapshot" -> nativeData(open(false).sealSnapshot(payload.getString("project_id"),
                            payload.getJSONArray("entries").toString(), payload.optString("archive_upload_id").takeIf { it.isNotBlank() }))
                        "open_attachment" -> nativeData(open(false).openAttachment(payload.getString("project_id"), payload.getString("paper_id"), payload.getString("digest"))).also {
                            readerOwners[(it as JSONObject).getString("reader_id")] = session
                        }
                        "open_upload_reader" -> nativeData(open(false).openUploadReader(payload.getString("upload_id"))).also {
                            readerOwners[(it as JSONObject).getString("reader_id")] = session
                        }
                        "read_attachment" -> {
                            val reader = payload.getString("reader_id"); check(readerOwners[reader] == session)
                            JSONObject().put("bytes", Base64.encodeToString(open(false).readAttachment(reader, 65536u), Base64.NO_WRAP))
                        }
                        "close_attachment" -> {
                            val reader = payload.getString("reader_id"); check(readerOwners[reader] == session)
                            open(false).closeAttachment(reader); readerOwners.remove(reader); JSONObject().put("closed", true)
                        }
                        "discard" -> {
                            val plan = payload.getString("plan_id"); check(planOwners[plan] == session)
                            open(false).discardPlan(plan); planOwners.remove(plan); toolPlans.remove(plan); JSONObject().put("discarded", true)
                        }
                        "prepare" -> nativeData(open(false).prepare(payload.getJSONObject("operation").toString(),
                            payload.optString("project_id").takeIf { it.isNotBlank() }, payload.getString("expected_revision"))).also {
                            val plan = it as JSONObject
                            planOwners[plan.getString("plan_id")] = session
                        }
                        // Only the visible UI review callback uses this endpoint. The
                        // registered model tool dispatcher never exposes it or initialize.
                        "confirm" -> {
                            val plan = payload.getString("plan_id")
                            check(planOwners[plan] == session)
                            check(!toolPlans.contains(plan))
                            nativeData(open(false).confirmUserPlan(plan))
                        }
                        "lookup" -> nativeData(open(false).lookupOriginal(payload.getString("intent_id")))
                        "cancel" -> nativeData(open(false).cancelOriginal(payload.getString("intent_id")))
                        else -> return send(reply, request, error("unsupported_operation", "rejected"))
                    }
                    JSONObject().put("status", "ok").put("data", data)
                }
            }
        } catch (_: UnsatisfiedLinkError) { error("native_unavailable", "unavailable")
        } catch (_: NoClassDefFoundError) { error("native_unavailable", "unavailable")
        } catch (failure: ProductException.Failure) { error(failure.code)
        } catch (_: Exception) { error("operation_unavailable") }
        send(reply, request, response)
    }
    private fun send(target: Messenger, request: String, response: JSONObject) {
        try {
            response.put("request_id", request)
            val raw = response.toString()
            if (raw.toByteArray(Charsets.UTF_8).size > 1_048_576) return
            target.send(Message.obtain(null, 1).apply { data = Bundle().apply { putString("response", raw) } })
        } catch (_: RemoteException) { /* The original intent remains in Rust, never resend. */ }
    }
    override fun onDestroy() {
        stopped = true
        val drained = java.util.concurrent.CountDownLatch(1)
        retiringOwners[epoch] = drained
        handler.post {
            deaths.forEach { (binder, recipient) -> runCatching { binder.unlinkToDeath(recipient, 0) } }; deaths.clear()
            clients.clear(); planOwners.clear(); toolPlans.clear()
            readerOwners.keys.toList().forEach { runCatching { core?.closeAttachment(it) } }; readerOwners.clear()
            chat.close()
            fun drainAndClose() {
                if (chat.awaitDrain(1000)) {
                    synchronized(this@ProductService) { core?.close(); core = null }
                    drained.countDown()
                    retiringOwners.remove(epoch, drained)
                    worker.quitSafely()
                } else handler.postDelayed({ drainAndClose() }, 1000)
            }
            drainAndClose()
        }
        super.onDestroy()
    }
}
