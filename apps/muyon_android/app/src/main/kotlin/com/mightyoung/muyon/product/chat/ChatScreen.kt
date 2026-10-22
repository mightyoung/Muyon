package com.mightyoung.muyon.product.chat

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import com.mightyoung.muyon.product.ui.shell.ConversationHeader
import com.mightyoung.muyon.product.ui.shell.ShellInputDock
import com.mightyoung.muyon.product.ui.shell.LocalShellDrafts
import com.mightyoung.muyon.product.ui.shell.ReadOnlySnapshot
import com.mightyoung.muyon.product.ui.shell.RequestCandidate
import com.mightyoung.muyon.product.ui.shell.RequestCandidatePanel
import com.mightyoung.muyon.product.ui.shell.decodeRequestCandidate
import com.mightyoung.muyon.product.ui.shell.ReadOnlySnapshotPanel
import com.mightyoung.muyon.product.ui.shell.decodeReadOnlySnapshot
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.mightyoung.muyon.product.agentipc.ProductClient
import com.mightyoung.muyon.product.design.ClaudeReplyFont
import org.json.JSONObject

/** Local reads are shown as local records, never as a fabricated model answer. */
@Composable
fun ChatScreen(
    client: ProductClient,
    projectId: String?,
    conversationKey: String = "default",
    displayName: String = "Muyon 助手",
    memberNames: List<String> = emptyList(),
    agentRole: String = "",
    agentInstructions: String = "",
    onOpenMenu: () -> Unit = {},
) {
    var configured by remember(client) { mutableStateOf(false) }
    key(conversationKey, projectId) {
        ChatConversation(client, projectId, conversationKey, displayName, memberNames, agentRole, agentInstructions, configured, onOpenMenu) { configured = it }
    }
}

@Composable
private fun ChatConversation(client: ProductClient, projectId: String?, conversationKey: String, displayName: String, memberNames: List<String>, agentRole: String, agentInstructions: String, configured: Boolean, onOpenMenu: () -> Unit, onConfigured: (Boolean) -> Unit) {
    val context = LocalContext.current
    val saved = remember { context.getSharedPreferences("product-chat-state", android.content.Context.MODE_PRIVATE) }
    val conversationPreference = remember(conversationKey) { if (conversationKey == "default") "conversation" else "conversation:$conversationKey" }
    var conversation by remember { mutableStateOf(saved.getString(conversationPreference, null) ?: java.util.UUID.randomUUID().toString().also { saved.edit().putString(conversationPreference, it).commit() }) }
    var original by remember { mutableStateOf(saved.getString("original_request", null)) }
    var originalConversationKey by remember { mutableStateOf(saved.getString("original_request_conversation_key", null)) }
    var originalDisplayName by remember { mutableStateOf(saved.getString("original_request_display_name", null)) }
    var settingsOpen by remember { mutableStateOf(false) }
    var moreOpen by remember { mutableStateOf(false) }
    var workflowOpen by remember { mutableStateOf(false) }
    var historyOpen by remember { mutableStateOf(false) }
    var requestDetailsOpen by remember { mutableStateOf(false) }
    var key by remember { mutableStateOf("") }
    var cap by remember { mutableStateOf("1000000") }
    var calls by remember { mutableStateOf("10") }
    var review by remember { mutableStateOf<JSONObject?>(null) }
    var reviewInput by remember { mutableStateOf("") }
    val shellSaved = remember { context.getSharedPreferences("muyon_ui_shell_v1", android.content.Context.MODE_PRIVATE) }
    var submittedInput by remember { mutableStateOf(shellSaved.getString("submitted_input", "").orEmpty()) }
    var submittedRequest by remember { mutableStateOf(shellSaved.getString("submitted_request", "").orEmpty()) }
    var submittedConversation by remember { mutableStateOf(shellSaved.getString("submitted_conversation", "").orEmpty()) }
    var reviewConversationKey by remember { mutableStateOf<String?>(null) }
    var reviewDisplayName by remember { mutableStateOf<String?>(null) }
    var resultText by remember { mutableStateOf("") }
    var usageDetails by remember { mutableStateOf("") }
    var requestObservation by remember { mutableStateOf<JSONObject?>(null) }
    var toolDetailsOpen by remember { mutableStateOf(false) }
    var conversationNotice by remember { mutableStateOf("") }
    var searchResults by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var accounting by remember { mutableStateOf("") }
    var pendingTool by remember { mutableStateOf<JSONObject?>(null) }
    var disclosure by remember { mutableStateOf<JSONObject?>(null) }
    var disclosureSuggestion by remember { mutableStateOf(false) }
    var suggestion by remember { mutableStateOf<JSONObject?>(null) }
    var followupReady by remember { mutableStateOf(false) }
    var businessPlan by remember { mutableStateOf(saved.getString("original_business_plan", null)) }
    var businessIntent by remember { mutableStateOf(saved.getString("original_business_intent", null)) }
    var businessOriginalText by remember { mutableStateOf(saved.getString("last_business_receipt_fact", "").orEmpty()) }
    var businessLookupRunning by remember { mutableStateOf(false) }
    var scopeReady by remember(projectId) { mutableStateOf(false) }
    var snapshotGeneration by remember { mutableStateOf<Long?>(null) }
    var readOnlySnapshot by remember { mutableStateOf<ReadOnlySnapshot?>(null) }
    var snapshotNotice by remember { mutableStateOf("") }
    var snapshotReading by remember { mutableStateOf(false) }
    var availability by remember { mutableStateOf<JSONObject?>(null) }
    var error by remember { mutableStateOf("") }
    var draftSaveError by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var records by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var tool by remember { mutableStateOf("supplier_list") }
    var offset by remember { mutableIntStateOf(0) }
    // Draft text stays out of the Activity Bundle and is isolated by actual selection and project.
    val localDrafts = remember { LocalShellDrafts(shellSaved) }
    var draft by remember { mutableStateOf(localDrafts.read(conversationKey, projectId)) }
    var source by remember { mutableStateOf("") }
    val currentProject by rememberUpdatedState(projectId)
    val currentReview by rememberUpdatedState(review)
    val callbacks = remember(client) { ChatCallbackScope() }
    callbacks.select(conversation, projectId)
    DisposableEffect(callbacks) { onDispose {
        callbacks.close()
        currentReview?.optString("request_id")?.takeIf { it.isNotBlank() }?.let {
            client.call("chat_cancel", JSONObject().put("request_id", it)) {}
        }
    } }
    fun scopedCall(method: String, payload: JSONObject = JSONObject(), callback: (JSONObject) -> Unit) {
        val token = callbacks.capture()
        client.call(method, payload) { reply ->
            if (callbacks.accepts(token)) callback(reply)
            else if (method == "chat_prepare" || (method == "chat_tool" && payload.optString("action") == "followup")) {
                // A prepared request is not sent. Revoke a late preview rather
                // than making it available for confirmation in another scope.
                reply.optJSONObject("data")?.optString("request_id")?.takeIf { it.isNotBlank() }?.let {
                    client.call("chat_cancel", JSONObject().put("request_id", it)) {}
                }
            }
        }
    }
    val originalOriginLabel = if (originalConversationKey.isNullOrBlank() || originalDisplayName.isNullOrBlank())
        "历史原请求（身份未记录）" else "原请求 · $originalDisplayName · 会话 $originalConversationKey"

    fun refreshStatus() {
        scopedCall("agent_availability") { reply ->
            if (reply.optString("status") == "ok") {
                availability = reply.optJSONObject("data")
                onConfigured(availability?.optBoolean("configured", false) == true)
                error = ""
            } else { onConfigured(false); error = "暂时无法读取聊天状态，请重新连接后刷新。" }
        }
    }
    fun observe() {
        val request = original ?: return
        scopedCall("chat_lookup", JSONObject().put("request_id", request)) { reply ->
            if (original != request) return@scopedCall
            val result = reply.optJSONObject("data")
            pendingTool = null
            searchResults = emptyList()
            if (reply.optString("status") != "ok" || result == null) {
                resultText = "原请求结果尚未取得，请继续查询；不会自动重发。"
            } else {
                usageDetails = ""
                requestObservation = result
                val sources = result.optJSONArray("answer")
                searchResults = if (sources == null) emptyList() else (0 until sources.length()).map { sources.getJSONObject(it) }
                resultText = when (result.optString("status")) {
                    "tool_pending" -> {
                        pendingTool = result.optJSONObject("answer")?.optJSONObject("call")
                        "模型调用已结算，等待您查看业务动作；不会自动读取后外发、提交修改或继续请求。"
                    }
                    "completed" -> result.optJSONObject("answer")?.let { answer ->
                        usageDetails = "输入 ${answer.optString("input_tokens")}，输出 ${answer.optString("output_tokens")} token；本次成本上界 ${result.optString("charged_micro_cny")} 微人民币。"
                        answer.optString("answer")
                    }
                        ?: "搜索完成：${result.optJSONArray("answer")?.length() ?: 0} 条外部结果。"
                    "cancelled" -> "已取消。已开始外发的请求仍可能保留费用上界。"
                    "prepared" -> "尚未确认，未发出请求。"
                    else -> "原请求结果未知，费用保留，继续查询原结果。"
                }
            }
        }
        scopedCall("chat_budget") { reply ->
            reply.optJSONObject("data")?.let { data ->
                accounting = "累计成本上界 ${data.optString("charged_micro_cny")} / ${data.optString("cap_micro_cny")} 微人民币；未知或待发保留 ${data.optString("held_micro_cny")} 微人民币。"
            }
        }
    }
    var requestCandidate by remember { mutableStateOf<RequestCandidate?>(null) }
    fun readOriginalSnapshot(candidate: RequestCandidate? = null) {
        val request = candidate?.snapshot?.requestId ?: original ?: return
        if (request != original) return
        if (snapshotReading) return
        val generation = snapshotGeneration ?: return
        val selectedConversation = conversation
        val selectedProject = projectId
        fun stillSelected() = original == request && conversation == selectedConversation &&
            currentProject == selectedProject && snapshotGeneration == generation
        snapshotReading = true; snapshotNotice = ""
        // Explicit user gesture only. Resolve current trusted workspace locally;
        // never auto-query a recovered historical request on mount or refresh.
        scopedCall("health") healthReply@{ health ->
            if (!stillSelected()) return@healthReply
            val workspace = (health.optJSONObject("data")?.opt("workspace") as? String)?.takeIf { it.isNotBlank() }
            if (health.optString("status") != "ok" || workspace == null) {
                snapshotReading = false; snapshotNotice = "当前工作台身份未取得，只读快照暂不可用。"
                return@healthReply
            }
            scopedCall(if (candidate == null) "chat_card_candidates" else "chat_snapshot", JSONObject().put("request_id", request)
                .put("conversation_id", selectedConversation).put("project_id", selectedProject ?: JSONObject.NULL)
                .put("scope_generation", generation)) snapshotReply@{ reply ->
                if (!stillSelected()) return@snapshotReply
                val data = reply.optJSONObject("data")
                val decodedCandidate = if (candidate == null && reply.optString("status") == "ok" && data != null)
                    decodeRequestCandidate(data, workspace, selectedConversation, selectedProject, generation, request) else null
                val decoded = if (candidate == null) decodedCandidate?.snapshot else if (reply.optString("status") == "ok" && data != null)
                    decodeReadOnlySnapshot(data, workspace, selectedConversation, selectedProject, generation, request) else null
                if (decodedCandidate != null) requestCandidate = decodedCandidate
                snapshotReading = false
                if (decoded != null) readOnlySnapshot = decoded
                else snapshotNotice = "当前会话缺少有效只读来源或作用域已变化；原请求身份保留，可使用原结果查询。"
            }
        }
    }
    fun preview(search: Boolean) {
        val frozenDraft = draft
        scopedCall("chat_prepare", JSONObject().put("conversation_id", conversation)
            .put("text", if (search) frozenDraft else agentUserInput(frozenDraft, agentRole, agentInstructions)).put("search", search).put("count", 5).put("project_id", projectId ?: JSONObject.NULL)) { reply ->
            val data = reply.optJSONObject("data")
            if (reply.optString("status") == "ok" && data?.has("request_id") == true) {
                reviewInput = frozenDraft
                reviewConversationKey = conversationKey; reviewDisplayName = displayName; review = data
            }
            else error = if (reply.optString("error") == "chat_tool_history_review_required" || data?.optString("error") == "chat_tool_history_review_required")
                "此会话包含尚未完成披露审核的工具历史。请查询原请求并完成审核，或从更多菜单开始新会话。"
            else "请求预览未完成，请检查配置、输入或先查询原请求。"
        }
    }
    fun toolAction(action: String, planId: String? = null, digest: String? = null, callback: (JSONObject) -> Unit) {
        val request = original ?: return
        scopedCall("chat_tool", JSONObject().put("action", action).put("request_id", request)
            .put("plan_id", planId ?: JSONObject.NULL).put("digest", digest ?: JSONObject.NULL)) { reply ->
            val data = reply.optJSONObject("data")
            if (reply.optString("status") == "ok" && data != null && !data.has("error")) callback(data)
            else error = "工具动作未完成；请查询原结果，作用域改变或结果未知时不会自动重试。"
        }
    }
    fun queryBusinessOriginal() {
        val intent = businessIntent ?: return
        if (businessLookupRunning) return
        historyOpen = true
        businessLookupRunning = true
        scopedCall("health") { health ->
            val workspace = health.optJSONObject("data")?.optString("workspace").orEmpty()
            if (health.optString("status") != "ok" || workspace.isBlank() || health.optJSONObject("data")?.optInt("protocol") != 1) {
                businessLookupRunning = false
                businessOriginalText = "原业务意图 $intent：工作台连接尚未核实，保留原身份，未重新执行。"
            } else scopedCall("lookup", JSONObject().put("intent_id", intent)) lookupReply@{ reply ->
                businessLookupRunning = false
                if (businessIntent != intent) return@lookupReply
                val result = reply.optJSONObject("data")
                val receipt = result?.optJSONObject("receipt")
                val scope = receipt?.optJSONObject("scope")
                val storedScope = try { saved.getString("original_business_scope", null)?.let(::JSONObject) } catch (_: Exception) { null }
                val scopeMatches = scope?.optString("workspace_id") == workspace &&
                    (storedScope == null || (storedScope.optString("workspace_id") == workspace && storedScope.opt("project_id") == scope?.opt("project_id")))
                val committed = reply.optString("status") == "ok" && result?.optString("status") == "committed" && receipt != null &&
                    receipt.optString("intent_id") == intent && receipt.optString("status") == "committed" &&
                    receipt.optInt("protocol_version") == 1 && scopeMatches
                val noCommitTerminal = reply.optString("status") == "ok" && result?.optString("status") in setOf("cancelled", "rejected", "not_submitted") && receipt == null
                if (committed) {
                    businessOriginalText = "历史业务回执：原意图 $intent 已提交，目标 ${receipt!!.optString("target_id")}，修订 ${receipt.optString("revision")}，原作用域 $scope。此为历史事实，不代表当前记录状态；未批准模型披露，也未再次执行。"
                } else if (noCommitTerminal) {
                    businessOriginalText = if (result!!.optString("status") == "not_submitted")
                        "原业务意图 $intent：核心尚未接收确认，原预览已封存；没有提交，也不会重发。"
                    else "原业务意图 $intent：查询终态 ${result.optString("status")}，没有提交回执；未声称业务成功，未再次执行。"
                } else {
                    businessOriginalText = "原业务意图 $intent：结果未知或回执身份尚未核实，保留原身份继续查询，不会重新执行。"
                }
                if (committed || noCommitTerminal) {
                    if (saved.getString("original_business_intent", null) == intent && saved.edit().putString("last_business_receipt_fact", businessOriginalText).remove("original_business_intent").remove("original_business_scope").commit()) {
                        businessIntent = null
                    }
                }
            }
        }
    }
    fun read(selectedTool: String, selectedOffset: Int) {
        if (loading) return
        loading = true
        val requestedProject = projectId
        scopedCall("agent_read", JSONObject()
            .put("project_id", projectId ?: JSONObject.NULL)
            .put("request", JSONObject().put("tool", selectedTool).put("limit", 20).put("offset", selectedOffset))) { reply ->
            loading = false
            if (currentProject != requestedProject) return@scopedCall
            if (reply.optString("status") == "ok") {
                val data = reply.optJSONObject("data")
                if (data == null || data.optString("source") != "current_local_business" || data.optBoolean("outbound_authorized", true) ||
                    (selectedTool == "paper_list" && data.optString("project_id") != requestedProject)) {
                    error = "本地读取未返回有效来源。"; records = emptyList()
                } else {
                    val array = data.optJSONArray("records")
                    records = if (array == null) emptyList() else (0 until array.length()).map { array.getJSONObject(it) }
                    source = "当前工作台 · ${data.optString("workspace_id")}" +
                        if (selectedTool == "paper_list") " · 项目 ${data.optString("project_id")}" else ""
                    tool = selectedTool; offset = selectedOffset; error = ""
                }
            } else {
                error = "本地读取未完成，以下保留上次读取内容；请检查项目或重新连接。"
            }
        }
    }
    LaunchedEffect(original, conversation) {
        readOnlySnapshot = null; requestCandidate = null; snapshotNotice = ""; snapshotReading = false
    }
    LaunchedEffect(client, conversation) { refreshStatus() }
    LaunchedEffect(client, projectId) {
        records = emptyList(); source = ""; offset = 0
        pendingTool = null; disclosure = null; suggestion = null; followupReady = false
        val requested = projectId
        scopedCall("chat_scope", JSONObject().put("project_id", projectId ?: JSONObject.NULL)) { reply ->
            if (currentProject == requested) {
                val data = reply.optJSONObject("data")
                scopeReady = reply.optString("status") == "ok" && data?.has("scope_generation") == true
                val value = data?.opt("scope_generation")
                snapshotGeneration = if (!scopeReady) null else when (value) {
                    is Int -> value.toLong().takeIf { it >= 0 }; is Long -> value.takeIf { it >= 0 }; else -> null
                }
            }
        }
    }

    Column(Modifier.fillMaxSize().imePadding()) {
        ConversationHeader(displayName, onOpenMenu, onMore = { moreOpen = true }, mainAgent = conversationKey == "default")
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())) {
        Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        if (resultText.isEmpty() && source.isEmpty() && businessIntent == null && !historyOpen) {
            Column(Modifier.fillMaxWidth().padding(vertical = 40.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text("今天想做些什么？", style = MaterialTheme.typography.headlineSmall)
                if (memberNames.isNotEmpty()) Text("群组仅作本地组织；不会自动调度成员。", style = MaterialTheme.typography.bodyMedium)
            }
        }
        if (conversationNotice.isNotEmpty()) Text(conversationNotice, style = MaterialTheme.typography.bodySmall)
        if (submittedRequest == original && submittedConversation == conversation && originalConversationKey == conversationKey && submittedInput.isNotBlank()) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                Surface(Modifier.widthIn(max = 320.dp).fillMaxWidth(.82f).testTag("chat-submitted-input"),
                    shape = RoundedCornerShape(24.dp), color = MaterialTheme.colorScheme.surfaceVariant) {
                    Text(submittedInput, Modifier.padding(16.dp), style = MaterialTheme.typography.bodyLarge)
                }
            }
        }
        if (original != null || resultText.isNotEmpty()) ChatPanel {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(originalOriginLabel, Modifier.weight(1f).testTag("chat-original-origin"), style = MaterialTheme.typography.labelMedium)
                TextButton(onClick = { observe() }) { Text("查询原结果") }
            }
            TextButton(onClick = { requestDetailsOpen = !requestDetailsOpen }) { Text(if (requestDetailsOpen) "收起原请求详情" else "原请求详情") }
            if (requestDetailsOpen) {
                Text("全局原请求恢复 · 结果与动作属于以上原始身份，不代表当前助手或群组的回复。", style = MaterialTheme.typography.bodySmall)
                Text("原请求：$original")
                if (usageDetails.isNotBlank()) Text(usageDetails, style = MaterialTheme.typography.bodySmall)
                ReadOnlySnapshotPanel(readOnlySnapshot?.takeIf { it.requestId == original }, snapshotNotice, snapshotReading,
                    if (scopeReady && snapshotGeneration != null) ({ readOriginalSnapshot() }) else null)
                requestCandidate?.takeIf { it.snapshot.requestId == original }?.let { candidate ->
                    RequestCandidatePanel(candidate, !snapshotReading && scopeReady) { readOriginalSnapshot(candidate) }
                }
                TextButton(onClick = { scopedCall("chat_cancel", JSONObject().put("request_id", original)) { observe() } }) { Text("取消原请求") }
            }
        requestObservation?.let { ChatRequestActivity(it) }
        if (resultText.isNotEmpty()) ConversationRichText(resultText, Modifier.testTag("chat-original-result"))
        pendingTool?.takeIf { scopeReady }?.let { call ->
            ChatPanel {
            Text("原请求待处理动作 · $originalOriginLabel", style = MaterialTheme.typography.labelLarge)
            Text("等待工具审核 · ${call.optString("name")}", style = MaterialTheme.typography.labelLarge)
            TextButton(onClick = { toolDetailsOpen = !toolDetailsOpen }) { Text(if (toolDetailsOpen) "收起调用详情" else "调用详情") }
            if (toolDetailsOpen) ConversationRichText("```json\n${call.optJSONObject("arguments")?.toString(2) ?: ""}\n```")
            if (call.optString("name").endsWith("_suggest")) {
                OutlinedButton(onClick = { toolAction("prepare_suggestion") { suggestion = it } }) { Text("查看业务修改建议") }
                businessPlan?.let { plan -> OutlinedButton(onClick = {
                    toolAction("review_suggestion", plan) { disclosureSuggestion = true; disclosure = it }
                }) { Text("查看原业务结果披露") } }
            } else OutlinedButton(onClick = {
                toolAction("review_read") { disclosureSuggestion = false; disclosure = it }
            }) { Text("查看将披露的实际字段") }
            if (followupReady) OutlinedButton(onClick = { toolAction("followup") {
                reviewConversationKey = originalConversationKey; reviewDisplayName = originalDisplayName
                reviewInput = ""; review = it; followupReady = false
            } }) { Text("预览独立的后续模型请求") }
            }
        }
        searchResults.forEach { result -> Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(result.optString("title"), style = MaterialTheme.typography.titleMedium)
                Text(result.optString("url"))
                Text(result.optString("snippet"))
                Text(result.optString("summary"))
            }
        } }
        }
        if (businessIntent != null) {
            Text("待核实的原业务意图：$businessIntent")
            OutlinedButton(onClick = { queryBusinessOriginal() }, enabled = !businessLookupRunning, modifier = Modifier.testTag("chat-business-original-lookup")) { Text("查询原业务回执") }
        }
        if (historyOpen && businessOriginalText.isNotEmpty()) Text(businessOriginalText, Modifier.testTag("chat-business-original-result"))
        if (loading) CircularProgressIndicator()
        if (scopeReady) AgentWorkflowSurface(client, conversation, projectId, workflowOpen,
            onDismiss = { workflowOpen = false }, onRemotePlan = { plan ->
                workflowOpen = false
                reviewConversationKey = "$conversationKey / ${plan.optString("workflow_id")}"
                reviewDisplayName = "$displayName · AI子任务"
                reviewInput = ""; review = plan
            })
        if (draftSaveError.isNotEmpty()) Text(draftSaveError, color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("chat-draft-save-error"))
        if (error.isNotEmpty()) Text(error, color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("chat-error"))
        if (source.isNotEmpty()) {
            Text(source, modifier = Modifier.testTag("chat-local-source"))
            if (records.isEmpty()) Text("本页没有记录。")
            records.forEach { record ->
                val payload = record.optJSONObject("payload")
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(payload?.optString("name") ?: record.optString("title"), style = MaterialTheme.typography.titleMedium)
                        Text("${record.optString("id")} · 修订 ${record.optString("revision")}")
                        payload?.optString("notes")?.takeIf { it.isNotBlank() && it != "null" }?.let { Text(it) }
                        if (payload == null) Text("附件 ${record.optInt("attachment_count")} 个")
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { read(tool, (offset - 20).coerceAtLeast(0)) }, enabled = !loading && offset > 0) { Text("上一页") }
                OutlinedButton(onClick = { read(tool, offset + 20) }, enabled = !loading && records.size == 20 && offset < 10_000) { Text("下一页") }
            }
        }
        }
        }
        ShellInputDock(draft, {
            draft = it.take(4096)
            draftSaveError = if (localDrafts.write(conversationKey, projectId, draft)) ""
                else "草稿尚未写入本机，当前输入仍保留；请勿离开页面。"
        }, configured && scopeReady && draft.isNotBlank(),
            onChat = { preview(false) }, onMore = { moreOpen = true }, moreMenu = {
                DropdownMenu(expanded = moreOpen, onDismissRequest = { moreOpen = false }) {
                    DropdownMenuItem(text = { Text("任务与技能") }, enabled = scopeReady, onClick = { moreOpen = false; workflowOpen = true })
                    DropdownMenuItem(text = { Text("模型与预算设置") }, onClick = { moreOpen = false; settingsOpen = true })
                    DropdownMenuItem(text = { Text("开始新会话") }, onClick = {
                        moreOpen = false
                        val next = java.util.UUID.randomUUID().toString()
                        if (saved.edit().putString(conversationPreference, next).commit()) {
                            callbacks.invalidate()
                            review?.optString("request_id")?.takeIf { it.isNotBlank() }?.let {
                                client.call("chat_cancel", JSONObject().put("request_id", it)) {}
                            }
                            conversation = next; submittedInput = ""; submittedRequest = ""; submittedConversation = ""; reviewInput = ""; review = null; reviewConversationKey = null; reviewDisplayName = null
                            pendingTool = null; disclosure = null; suggestion = null; followupReady = false
                            resultText = ""; requestObservation = null; usageDetails = ""; searchResults = emptyList(); records = emptyList(); source = ""; historyOpen = false
                            conversationNotice = "已开始新会话；原请求仍可独立查询。"
                        }
                    })
                    DropdownMenuItem(text = { Text("刷新连接状态") }, onClick = { moreOpen = false; refreshStatus() })
                    DropdownMenuItem(text = { Text("预览搜索请求") }, enabled = configured && scopeReady && draft.isNotBlank(), onClick = { moreOpen = false; preview(true) })
                    DropdownMenuItem(text = { Text("读取供应商") }, enabled = !loading, onClick = { moreOpen = false; read("supplier_list", 0) })
                    DropdownMenuItem(text = { Text("读取项目论文") }, enabled = !loading && projectId != null, onClick = { moreOpen = false; read("paper_list", 0) })
                    DropdownMenuItem(text = { Text("历史业务回执") }, enabled = businessOriginalText.isNotEmpty() || businessIntent != null, onClick = {
                        moreOpen = false; historyOpen = true
                        if (businessIntent != null) queryBusinessOriginal()
                    })
                }
            })
    }
    if (settingsOpen) AlertDialog(
        shape = RoundedCornerShape(32.dp),
        onDismissRequest = { settingsOpen = false; key = "" },
        title = { Text("确认新的产品配置") },
        text = { Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(if (availability == null) "连接状态未读取" else "本地读取已连接；实际外发仍需通过计费证明与预算检查", Modifier.testTag("chat-availability"))
            if (accounting.isNotEmpty()) Text(accounting)
            Text("DeepSeek · 独立产品配置与累计预算。所有助手与群组共享此工作台的模型配置和累计预算；成员资料不会自动发送给模型，也不会自动调度成员。")
            Text("配置不会发出请求。凭据仅保留在当前 Service 内存，重启后需重新输入。当前托管聊天计费上界与搜索价格证明尚未安装，预览会明确阻止外发。")
            Text("供应商：DeepSeek；端点固定为 api.deepseek.com。不会读取历史凭据或预算。")
            OutlinedTextField(value = key, onValueChange = { key = it.take(512) }, label = { Text("新凭据（仅当前进程）") }, visualTransformation = PasswordVisualTransformation())
            OutlinedTextField(value = cap, onValueChange = { cap = it.filter(Char::isDigit).take(13) }, label = { Text("累计上限（微人民币）") })
            OutlinedTextField(value = calls, onValueChange = { calls = it.filter(Char::isDigit).take(6) }, label = { Text("累计请求数上限") })
            Text("1 元 = 1,000,000 微人民币。每次确认先保留经可信证明的请求成本上界；未知结果保留占额。更换配置不会清零已用费用或未知保留。填写预算不能替代真实计费证明。")
        } },
        confirmButton = { TextButton(onClick = {
            val input = key.toCharArray(); key = ""; settingsOpen = false
            // In-flight status replies belong to the previous configuration.
            snapshotReading = false
            if (snapshotNotice.isEmpty()) snapshotNotice = "配置已变化，可按需重新读取只读快照。"
            callbacks.invalidate()
            val token = callbacks.capture()
            client.configureChat(JSONObject().put("cap_micro_cny", cap).put("max_calls", calls).put("chat", true).put("search", true), input) { reply ->
                input.fill('\u0000')
                if (!callbacks.accepts(token)) return@configureChat
                val accepted = reply.optString("status") == "ok" && reply.optJSONObject("data")?.has("id") == true
                onConfigured(accepted)
                error = if (accepted) "" else "配置未完成，未发出请求。"
            }
        }, enabled = key.length in 16..512 && cap.isNotEmpty() && calls.isNotEmpty()) { Text("确认配置与累计预算") } },
        dismissButton = { TextButton(onClick = { settingsOpen = false; key = "" }) { Text("取消") } }
    )
    review?.let { plan -> AlertDialog(
        shape = RoundedCornerShape(32.dp),
        onDismissRequest = { client.call("chat_cancel", JSONObject().put("request_id", plan.optString("request_id"))) {}; review = null }, title = { Text("请求预览") },
        text = { Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("${if (plan.optString("purpose") == "search") "外部搜索" else "模型聊天"} · DeepSeek")
            Text(if (reviewConversationKey.isNullOrBlank() || reviewDisplayName.isNullOrBlank()) "历史原请求（身份未记录）" else "请求来源：$reviewDisplayName · 会话 $reviewConversationKey")
            Text("本次保留上界：${plan.optString("reserved_micro_cny")} 微人民币")
            Text("请求身份：${plan.optString("request_id")}")
            ChatOutboundPreview(plan)
            plan.optString("input_preview").takeIf { it.isNotBlank() }?.let {
                Text("本次子任务的完整输入", style = MaterialTheme.typography.titleSmall)
                ConversationRichText(it)
            }
            if (!plan.optBoolean("send_allowed")) Text("尚无可信的托管计费或搜索价格证明；此次请求不会发出。")
            Text("确认仅执行本次请求；超时或重启后查询原身份，不自动重发。")
        } },
        confirmButton = { TextButton(onClick = {
            val request = plan.getString("request_id")
            if (saved.edit().putString("original_request", request)
                    .putString("original_request_conversation_key", reviewConversationKey)
                    .putString("original_request_display_name", reviewDisplayName).commit()) {
                submittedInput = reviewInput; submittedRequest = request; submittedConversation = conversation
                // Display metadata only; it never participates in dispatch authority.
                shellSaved.edit().putString("submitted_input", submittedInput).putString("submitted_request", submittedRequest).putString("submitted_conversation", submittedConversation).apply()
                original = request; originalConversationKey = reviewConversationKey; originalDisplayName = reviewDisplayName
                pendingTool = null; searchResults = emptyList(); resultText = ""; requestObservation = null; usageDetails = ""; review = null
                disclosure = null; suggestion = null; followupReady = false
                scopedCall("chat_confirm", JSONObject().put("request_id", request)) { observe() }
            } else error = "原请求身份未能保存，未发出请求。"
        }, enabled = plan.optBoolean("send_allowed") && hasCompleteOutboundPreview(plan)) { Text("确认本次外发") } },
        dismissButton = { TextButton(onClick = { client.call("chat_cancel", JSONObject().put("request_id", plan.optString("request_id"))) {}; review = null }) { Text("返回") } }
    ) }
    disclosure?.let { data -> AlertDialog(
        shape = RoundedCornerShape(32.dp),
        onDismissRequest = { disclosure = null }, title = { Text("批准本次业务信息披露") },
        text = { Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(originalOriginLabel)
            Text("目的：下一次模型工具结果；费用预算不能代替此许可。")
            Text("作用域：${data.optJSONObject("scope")?.toString()}")
            Text(data.optString("bytes"))
            Text("字节摘要：${data.optString("digest")}")
            Text("只批准屏幕上的实际字段；数据、项目、会话或代次变化后需重新核验。批准不会自动发起下一次请求。")
        } },
        confirmButton = { TextButton(onClick = {
            val action = if (disclosureSuggestion) "approve_suggestion" else "approve_read"
            toolAction(action, if (disclosureSuggestion) businessPlan else null, data.optString("digest")) { disclosure = null; followupReady = true }
        }) { Text("批准这些字段供本次后续请求使用") } },
        dismissButton = { TextButton(onClick = { disclosure = null }) { Text("取消披露") } }
    ) }
    suggestion?.let { data -> AlertDialog(
        shape = RoundedCornerShape(32.dp),
        onDismissRequest = { suggestion = null }, title = { Text("确认本次业务修改") },
        text = { Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(originalOriginLabel)
            val preview = data.optJSONObject("business_preview")
            Text(data.optString("summary"))
            Text("作用域：${preview?.optJSONObject("scope")}")
            Text("预期修订：${preview?.optString("expected_revision")}")
            Text(preview?.optJSONObject("command")?.toString(2) ?: "未取得完整修改参数，不可确认。")
            Text("这是本地业务修改确认，不批准模型外发；完成后还需独立审核结果披露。")
        } },
        confirmButton = { TextButton(onClick = {
            val plan = data.getString("plan_id")
            val intent = data.getJSONObject("business_preview").getString("intent_id")
            val unresolved = saved.getString("original_business_intent", null)
            if (unresolved != null) {
                businessIntent = unresolved; error = "请先查询并核实原业务回执，未执行新的修改。"
            } else if (saved.edit().putString("original_business_plan", plan).putString("original_business_intent", intent)
                    .putString("original_business_scope", data.getJSONObject("business_preview").getJSONObject("scope").toString()).commit()) {
                businessPlan = plan; businessIntent = intent; suggestion = null
                toolAction("confirm_suggestion", plan) { disclosureSuggestion = true; disclosure = it }
            } else error = "原业务身份未能保存，未执行修改。"
        }, enabled = businessIntent == null && data.optJSONObject("business_preview")?.has("command") == true) { Text("确认以上完整修改") } },
        dismissButton = { TextButton(onClick = { suggestion = null }) { Text("取消修改") } }
    ) }
}
