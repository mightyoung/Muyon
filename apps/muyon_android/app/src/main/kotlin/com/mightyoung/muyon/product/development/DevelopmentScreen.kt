package com.mightyoung.muyon.product.development

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.mightyoung.muyon.product.agentipc.ProductClient
import com.mightyoung.muyon.product.chat.ChatOutboundPreview
import com.mightyoung.muyon.product.chat.hasCompleteOutboundPreview
import org.json.JSONObject

/** Local draft writes and model sends are separate, explicit user actions. */
@Composable
fun DevelopmentScreen(client: ProductClient, conversation: String, project: String?) {
    DevelopmentEditor(conversation, project) { method, payload, callback -> client.call(method, payload, callback) }
}

internal typealias DevelopmentCall = (String, JSONObject, (JSONObject) -> Unit) -> Unit

@Composable
internal fun DevelopmentEditor(conversation: String, project: String?, call: DevelopmentCall) {
    key(conversation, project) { ScopedDevelopmentEditor(conversation, project, call) }
}

@Composable
private fun ScopedDevelopmentEditor(conversation: String, project: String?, call: DevelopmentCall) {
    val preferences = LocalContext.current.getSharedPreferences("product-development-ui", 0)
    val scope = developmentScopeKey(conversation, project)
    var draftId by rememberSaveable { mutableStateOf(preferences.getString("draft:$scope", "").orEmpty()) }
    var previousDraftId by rememberSaveable { mutableStateOf(preferences.getString("previous-draft:$scope", "").orEmpty()) }
    var originalRequest by rememberSaveable { mutableStateOf(preferences.getString("request:$scope", "").orEmpty()) }
    var proposalRequest by rememberSaveable { mutableStateOf(preferences.getString("proposal-request:$scope", "").orEmpty()) }
    var proposalDraftId by rememberSaveable { mutableStateOf(preferences.getString("proposal-draft:$scope", "").orEmpty()) }
    var recoverId by rememberSaveable { mutableStateOf(draftId) }
    var snapshot by remember { mutableStateOf<JSONObject?>(null) }
    var plan by remember { mutableStateOf<JSONObject?>(null) }
    var projectReview by remember { mutableStateOf<DevelopmentProjectReview?>(null) }
    // A mounted observation only. Never restore or refresh this token while dispatching.
    var capturedGeneration by remember { mutableStateOf<Long?>(null) }
    var original by remember { mutableStateOf<JSONObject?>(null) }
    var nameInput by rememberSaveable { mutableStateOf("") }
    var itemInput by rememberSaveable { mutableStateOf("") }
    var itemId by rememberSaveable { mutableStateOf("") }
    var kind by rememberSaveable { mutableStateOf("requirement") }
    var modelInput by rememberSaveable { mutableStateOf("") }
    var preview by remember { mutableStateOf<JSONObject?>(null) }
    var observation by remember { mutableStateOf<JSONObject?>(null) }
    var proposal by remember { mutableStateOf<JSONObject?>(null) }
    var configured by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var notice by rememberSaveable { mutableStateOf("") }
    var uncertain by rememberSaveable { mutableStateOf(false) }
    var modelSent by rememberSaveable { mutableStateOf(false) }
    var proposalNotSaved by rememberSaveable { mutableStateOf(false) }
    val callbacks = remember { DevelopmentCallbackScope() }
    callbacks.select(conversation, project, draftId, capturedGeneration)
    val currentPreview by rememberUpdatedState(preview)
    DisposableEffect(callbacks) { onDispose {
        callbacks.close()
        currentPreview?.optString("request_id")?.takeIf { it.isNotBlank() }?.let {
            call("chat_cancel", JSONObject().put("request_id", it)) {}
        }
    } }
    fun payload() = JSONObject().put("conversation_id", conversation).put("project_id", project ?: JSONObject.NULL)
        .put("draft_id", draftId.takeIf { it.isNotBlank() } ?: JSONObject.NULL)
    fun request(method: String, args: JSONObject = payload(), onReply: (JSONObject) -> Unit) {
        if (busy) return
        val developmentRequest = method.startsWith("development_") || method == "chat_prepare_development"
        val frozenArgs = JSONObject(args.toString())
        if (developmentRequest) {
            val captured = capturedGeneration
            val supplied = if (frozenArgs.has("scope_generation")) developmentScopeGeneration(frozenArgs.opt("scope_generation")) else captured
            if (captured == null || supplied != captured) {
                notice = "当前作用域尚未核实或已改变，请重新核实后重读草稿；不会自动取得新权限并重放。"
                return
            }
            frozenArgs.put("scope_generation", supplied)
        }
        busy = true
        val token = callbacks.capture()
        call(method, frozenArgs) { reply ->
            if (callbacks.accepts(token)) {
                busy = false
                onReply(reply)
            } else if (method == "chat_prepare_development") {
                // A late preview never becomes confirmable in another selection.
                reply.optJSONObject("data")?.optString("request_id")?.takeIf { it.isNotBlank() }?.let {
                    call("chat_cancel", JSONObject().put("request_id", it)) {}
                }
            }
        }
    }
    fun verifyScope() {
        request("chat_scope_current", JSONObject().put("project_id", project ?: JSONObject.NULL)) { reply ->
            val data = reply.optJSONObject("data")
            val next = if (reply.optString("status") == "ok" && data?.optString("status") == "scope_current")
                developmentScopeGeneration(data.opt("scope_generation")) else null
            if (next != capturedGeneration) {
                snapshot = null; plan = null; projectReview = null; proposal = null; preview = null
            }
            capturedGeneration = next
            notice = if (next == null) "尚不能核实当前项目作用域，请先返回对应普通对话，再打开开发草稿。"
                else "当前作用域已核实。请显式打开或恢复草稿；不会自动执行。"
        }
    }
    LaunchedEffect(Unit) { verifyScope() }
    fun acceptSnapshot(data: JSONObject): Boolean {
        val generation = developmentScopeGeneration(data.opt("scope_generation"))
        if (generation == null || generation != capturedGeneration) return false
        val next = data.optJSONObject("snapshot") ?: return false
        val content = next.optJSONObject("content") ?: return false
        val reference = next.optJSONObject("draft_ref") ?: return false
        val id = reference.optString("draft_id")
        if (content.optString("conversation_id") != conversation || id.isBlank() || content.optString("edit_revision").isBlank()) return false
        val previous = draftId.takeIf { it.isNotBlank() && it != id } ?: previousDraftId
        if (!preferences.edit().putString("draft:$scope", id).putString("previous-draft:$scope", previous).commit()) {
            notice = "草稿身份未能保存，请记下原身份后恢复；不会自动重试。"
            return false
        }
        previousDraftId = previous; draftId = id; recoverId = id; snapshot = next; plan = data.optJSONObject("plan"); original = data.optJSONObject("original")
        projectReview = plan?.let { displayed ->
            DevelopmentProjectReview((displayed.opt("plan_id") as? String).orEmpty(), (data.opt("binding_digest") as? String).orEmpty(), generation,
                id, content.optString("edit_revision")).takeIf { it.canConfirm(generation, id, content.optString("edit_revision")) }
        }
        uncertain = false
        // Re-reading never replaces unsaved editor input.
        return true
    }
    fun handleDraft(reply: JSONObject) {
        val data = reply.optJSONObject("data")
        if (reply.optString("status") == "ok" && data != null && acceptSnapshot(data)) {
            notice = "已读取本地持久草稿。需求与 bug 仍是草稿。"
        } else {
            uncertain = true; plan = null; projectReview = null
            notice = "操作未确认或版本冲突；输入已保留。请重读草稿或查询原结果，不会自动覆写或重放。\n${reply.optString("error")}"
        }
    }
    fun update(action: String, extra: JSONObject = JSONObject()) {
        val revision = snapshot?.optJSONObject("content")?.optString("edit_revision") ?: return
        val args = payload().put("action", action).put("expected_revision", revision)
        extra.keys().forEach { args.put(it, extra.get(it)) }
        request("development_update", args, ::handleDraft)
    }
    val content = snapshot?.optJSONObject("content")
    val submission = content?.optJSONObject("submission")
    val dispatched = submission?.optBoolean("dispatched") == true
    val editable = content != null && capturedGeneration != null && !busy && !uncertain && !dispatched
    val requestId = preview?.optString("request_id").orEmpty()

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("开发草稿", style = MaterialTheme.typography.headlineSmall)
        Text("本页仅整理开发草稿；创建项目需要先查看完整计划，再单独确认。真实接入、Android 真机与视觉验收仍待完成。")
        Text("会话：$conversation\n当前项目：${project ?: "未选择"}", style = MaterialTheme.typography.bodySmall)
        TextButton(onClick = { verifyScope() }, enabled = !busy) { Text("重新核实当前作用域") }
        if (notice.isNotBlank()) Text(notice, Modifier.testTag("development-notice"), color = MaterialTheme.colorScheme.onSurfaceVariant)
        Button(onClick = { request("development_open", payload().put("create", false), ::handleDraft) }, enabled = !busy && capturedGeneration != null,
            modifier = Modifier.testTag("development-open")) { Text("打开／重读草稿") }
        OutlinedTextField(recoverId, { recoverId = it }, label = { Text("恢复草稿身份") }, modifier = Modifier.fillMaxWidth(), enabled = !busy)
        TextButton(onClick = { request("development_open", payload().put("draft_id", recoverId).put("create", false), ::handleDraft) }, enabled = !busy && capturedGeneration != null && recoverId.isNotBlank()) { Text("恢复指定草稿") }
        if (previousDraftId.isNotBlank() && previousDraftId != draftId) {
            Text("上一个草稿身份：$previousDraftId", style = MaterialTheme.typography.bodySmall)
            TextButton(onClick = { request("development_open", payload().put("draft_id", previousDraftId).put("create", false), ::handleDraft) }, enabled = !busy && capturedGeneration != null) { Text("恢复上一个草稿（保留输入）") }
        }
        TextButton(onClick = { request("development_open", payload().put("draft_id", JSONObject.NULL).put("create", true), ::handleDraft) }, enabled = !busy && !uncertain && capturedGeneration != null) { Text("打开或创建本地草稿") }
        if (content != null) {
            Text("草稿身份：$draftId\n编辑版本：${content.optString("edit_revision")} · 存储版本：${snapshot?.optJSONObject("draft_ref")?.optString("revision")}", style = MaterialTheme.typography.bodySmall)
            Text("已保存项目名：${content.optJSONObject("project_name")?.optString("text").orEmpty()}")
            TextButton(onClick = { nameInput = content.optJSONObject("project_name")?.optString("text").orEmpty() }, enabled = !busy) { Text("将已保存项目名放入编辑框") }
            OutlinedTextField(nameInput, { nameInput = it }, label = { Text("项目名草稿") }, modifier = Modifier.fillMaxWidth(), enabled = !busy)
            TextButton(onClick = { update("set_name", JSONObject().put("text", nameInput)) }, enabled = editable && nameInput.isNotBlank()) { Text("保存项目名草稿") }
            val items = content.optJSONArray("items")
            for (index in 0 until (items?.length() ?: 0)) {
                val item = items!!.getJSONObject(index)
                Surface(color = MaterialTheme.colorScheme.surfaceVariant, modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text("${developmentKindLabel(item.optString("kind"))} · 草稿", style = MaterialTheme.typography.titleSmall)
                        Text(item.optJSONObject("text")?.optString("text").orEmpty())
                        if (item.optJSONObject("text")?.optBoolean("manually_edited") == true) Text("已手工编辑", style = MaterialTheme.typography.bodySmall)
                        var sourceOpen by remember(item.optString("item_id")) { mutableStateOf(false) }
                        TextButton(onClick = { sourceOpen = !sourceOpen }) { Text(if (sourceOpen) "收起原始来源" else "查看原始来源") }
                        if (sourceOpen) {
                            val sources = item.optJSONArray("sources")
                            if (sources == null || sources.length() == 0) Text("手工条目；没有模型来源绑定。")
                            else for (sourceIndex in 0 until sources.length()) Text(sources.getJSONObject(sourceIndex).toString(2))
                        }
                        TextButton(onClick = { itemId = item.optString("item_id"); itemInput = item.optJSONObject("text")?.optString("text").orEmpty(); kind = item.optString("kind") }, enabled = editable) { Text("编辑此草稿条目") }
                    }
                }
            }
            Text(if (itemId.isBlank()) "新增草稿条目" else "编辑草稿条目 $itemId", style = MaterialTheme.typography.titleSmall)
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                listOf("requirement", "bug", "question").forEach { value ->
                    FilterChip(selected = kind == value, onClick = { kind = value }, label = { Text(developmentKindLabel(value)) }, enabled = !busy && itemId.isBlank())
                }
            }
            OutlinedTextField(itemInput, { itemInput = it }, label = { Text("条目内容（草稿）") }, modifier = Modifier.fillMaxWidth(), enabled = !busy)
            TextButton(onClick = {
                update(if (itemId.isBlank()) "add_item" else "edit_item", JSONObject().put("text", itemInput).apply {
                    if (itemId.isBlank()) put("kind", kind) else put("item_id", itemId)
                })
            }, enabled = editable && itemInput.isNotBlank()) { Text(if (itemId.isBlank()) "新增草稿条目" else "保存条目修改") }
            if (itemId.isNotBlank()) TextButton(onClick = { itemId = "" }, enabled = !busy) { Text("切换为新增条目（保留输入）") }
            Text("项目选择：${content.optJSONObject("project")?.optString("state").orEmpty()}")
            TextButton(onClick = { update("choose_new_project") }, enabled = editable) { Text("明确选择创建新项目") }
            Button(onClick = { request("development_prepare_project", onReply = ::handleDraft) }, enabled = editable && content.optJSONObject("project")?.optString("state") == "new",
                modifier = Modifier.testTag("development-prepare-project")) { Text("准备创建项目计划") }
            plan?.let { command ->
                val reviewed = projectReview
                Text("创建项目完整计划", style = MaterialTheme.typography.titleMedium)
                Text("影响：将按以下原始命令中的名称和身份创建一个项目。需求与 bug 仍保留为草稿，不会自动提交。")
                Text(command.toString(2), Modifier.testTag("development-project-plan"))
                Text("本计划绑定摘要：${reviewed?.bindingDigest ?: "未取得，不能确认"}", style = MaterialTheme.typography.bodySmall)
                Button(onClick = {
                    if (reviewed == null || !reviewed.canConfirm(capturedGeneration, draftId, content.optString("edit_revision"))) return@Button
                    // One confirmation attempt only. An unknown reply stays query-only.
                    plan = null; projectReview = null; uncertain = true
                    request("development_confirm_project", payload().put("plan_id", reviewed.planId)
                        .put("binding_digest", reviewed.bindingDigest).put("scope_generation", reviewed.scopeGeneration), ::handleDraft)
                }, enabled = !busy && !uncertain && !dispatched && reviewed?.canConfirm(capturedGeneration, draftId, content.optString("edit_revision")) == true,
                    modifier = Modifier.testTag("development-confirm-project")) { Text("确认创建项目") }
            }
            if (submission != null) Text("原提交记录：\n${submission.toString(2)}")
            TextButton(onClick = { request("development_lookup_original", onReply = ::handleDraft) }, enabled = !busy && draftId.isNotBlank()) { Text("查询原创建结果") }
            original?.let { Text("原结果：\n${it.toString(2)}") }
        }
        HorizontalDivider()
        Text("用模型整理开发草稿", style = MaterialTheme.typography.titleLarge)
        Text("模型仅提出带原文来源的候选草稿；接受提案不会创建项目，也不会自动继续请求。")
        TextButton(onClick = {
            request("agent_availability", JSONObject()) { reply ->
                configured = reply.optString("status") == "ok" && reply.optJSONObject("data")?.optBoolean("configured") == true
                notice = if (configured) "模型已配置，仍需逐次预览和确认。" else "模型尚不可用，请先到普通对话配置服务与预算。"
            }
        }, enabled = !busy) { Text("检查模型可用性") }
        OutlinedTextField(modelInput, { modelInput = it }, label = { Text("需要整理的开发内容") }, modifier = Modifier.fillMaxWidth(), enabled = !busy)
        Button(onClick = {
            request("chat_prepare_development", payload().put("text", modelInput)) { reply ->
                val data = reply.optJSONObject("data")
                if (reply.optString("status") == "ok" && !data?.optString("request_id").isNullOrBlank()) { preview = data; modelSent = false }
                else notice = "模型预览未完成；未自动发送。${reply.optString("error")}"
            }
        }, enabled = !busy && capturedGeneration != null && configured && modelInput.isNotBlank() && preview == null && !modelSent) { Text("预览模型整理请求") }
        preview?.let { prepared ->
            Text("本次保留费用上界：${prepared.optString("reserved_micro_cny")} 微人民币")
            ChatOutboundPreview(prepared)
            Text("阻断原因：${prepared.optString("blocked_reason").takeIf { it.isNotBlank() && it != "null" } ?: "无；仍需显式确认"}")
            Button(onClick = {
                if (preferences.edit().putString("request:$scope", requestId).commit()) {
                    originalRequest = requestId; modelSent = true; preview = null; observation = null; proposal = null
                    request("chat_confirm", JSONObject().put("request_id", requestId)) { reply ->
                        observation = reply.optJSONObject("data")
                        notice = "本次确认已结束，请查询原模型结果；不会重发。"
                    }
                } else notice = "原请求身份未能保存，未发出请求。"
            }, enabled = !busy && prepared.optBoolean("send_allowed") && hasCompleteOutboundPreview(prepared), modifier = Modifier.testTag("development-confirm-model")) { Text("确认本次模型外发") }
            TextButton(onClick = {
                preview = null
                request("chat_cancel", JSONObject().put("request_id", requestId)) { notice = "已请求取消预览，未自动外发。" }
            }, enabled = !busy) { Text("取消本次预览") }
        }
        if (originalRequest.isNotBlank()) {
            Text("原模型请求：$originalRequest", style = MaterialTheme.typography.bodySmall)
            TextButton(onClick = {
                request("chat_lookup", JSONObject().put("request_id", originalRequest)) { reply ->
                    observation = reply.optJSONObject("data")
                    notice = if (reply.optString("status") == "ok") "已查询原请求；不会自动继续。" else "原结果仍未知，请稍后再查询。"
                }
            }, enabled = !busy) { Text("查询原模型结果") }
            TextButton(onClick = { request("chat_cancel", JSONObject().put("request_id", originalRequest)) { notice = "已请求取消；已外发的请求仍需查询原结果与费用。" } }, enabled = !busy) { Text("取消原模型请求") }
            TextButton(onClick = { modelSent = false }, enabled = !busy && preview == null) { Text("开始另一次整理（保留原请求身份至确认新请求）") }
        }
        if (proposalRequest.isNotBlank()) {
            Text("原提案保存请求：$proposalRequest\n候选草稿身份：$proposalDraftId", style = MaterialTheme.typography.bodySmall)
            if (snapshot == null) Text("重连后请先打开或恢复原草稿，再查询原提案保存结果。")
            TextButton(onClick = {
                // A lost acceptance ACK may leave the host selected on the new
                // draft while this UI still remembers the previous draft ID.
                request("development_lookup_proposal", payload().put("draft_id", JSONObject.NULL).put("request_id", proposalRequest)) { reply ->
                    val data = reply.optJSONObject("data")
                    notice = when {
                        reply.optString("status") != "ok" || data == null -> "原提案保存结果仍未知，请继续查询；不会重新接受或生成新身份。"
                        data.optString("status") == "saved" && acceptSnapshot(data) -> {
                            proposalNotSaved = false
                            "已查询并打开原提案持久草稿；手工输入保留。"
                        }
                        data.optString("status") == "not_saved" -> {
                            proposalNotSaved = true
                            "尚未找到原提案的保存结果；原工具仍待处理。可显式取消原提案请求，或继续查询原结果；未自动重新接受。"
                        }
                        else -> "原提案结果尚不能核实；手工输入保留。"
                    }
                }
            }, enabled = !busy && snapshot != null, modifier = Modifier.testTag("development-lookup-proposal")) { Text("查询原提案保存结果") }
            if (proposalNotSaved) {
                TextButton(onClick = {
                    request("chat_cancel", JSONObject().put("request_id", proposalRequest)) {
                        notice = "已请求取消原提案；请继续查询原模型结果。没有重新外发或接受提案。"
                    }
                }, enabled = !busy, modifier = Modifier.testTag("development-cancel-unsaved-proposal")) { Text("取消原提案请求") }
                TextButton(onClick = {
                    request("chat_lookup", JSONObject().put("request_id", proposalRequest)) { reply ->
                        notice = "原提案模型结果：\n${reply.optJSONObject("data")?.toString(2) ?: "仍未知"}"
                    }
                }, enabled = !busy) { Text("查询原提案模型结果") }
            }
        }
        observation?.let { result ->
            val answer = result.optJSONObject("answer")
            Text("原请求状态：${result.optString("status")}")
            Text(answer?.optString("answer")?.takeIf { it.isNotBlank() } ?: result.toString(2))
            if (result.optString("status") == "tool_pending" && answer?.optJSONObject("call")?.optString("name") == "product.development_draft_propose") {
                if (snapshot == null) Text("请先打开或创建本地草稿，再审核提案。")
                TextButton(onClick = {
                    request("development_preview_proposal", payload().put("request_id", originalRequest)) { reply ->
                        val data = reply.optJSONObject("data")
                        if (reply.optString("status") == "ok" && !data?.optString("review_digest").isNullOrBlank()) proposal = data
                        else notice = "提案尚不能审核；原请求和手工输入保留。${reply.optString("error")}"
                    }
                }, enabled = !busy && snapshot != null && proposal == null) { Text("查看带来源的草稿提案差异") }
            } else if (result.optString("status") == "completed") Text("本次返回普通回答，没有可接受的开发草稿提案。")
        }
        proposal?.let { review ->
            DevelopmentProposalReview(snapshot?.optJSONObject("content"), review)
            fun reviewAction(accept: Boolean) {
                if (accept) {
                    val candidateDraftId = review.optString("draft_id")
                    if (!preferences.edit().putString("proposal-request:$scope", originalRequest)
                            .putString("proposal-draft:$scope", candidateDraftId).commit()) {
                        notice = "原提案保存身份未能记录，未接受提案。"
                        return
                    }
                    proposalRequest = originalRequest; proposalDraftId = candidateDraftId; proposalNotSaved = false
                }
                // Consume this UI review before IPC. Unknown replies cannot be retried
                // through the same confirmation button; query the original request.
                proposal = null
                request(if (accept) "development_accept_proposal" else "development_reject_proposal",
                    payload().put("request_id", originalRequest).put("review_digest", review.optString("review_digest"))) { reply ->
                    if (reply.optString("status") == "ok" && reply.optJSONObject("data")?.has("error") == false) {
                        proposal = null
                        if (accept) handleDraft(reply) else notice = "已拒绝提案；本地草稿与输入保留。"
                    } else notice = "审核结果未确认，请查询原请求；不会自动重放。${reply.optString("error")}"
                }
            }
            Button(onClick = { reviewAction(true) }, enabled = !busy, modifier = Modifier.testTag("development-accept-proposal")) { Text("接受为独立开发草稿") }
            TextButton(onClick = { reviewAction(false) }, enabled = !busy) { Text("拒绝此提案") }
        }
        if (busy) Text("正在处理，请等待；不会重复提交。")
    }
}

@Composable
private fun DevelopmentProposalReview(current: JSONObject?, review: JSONObject) {
    val candidate = review.optJSONObject("snapshot")?.optJSONObject("content")
    Column(Modifier.testTag("development-proposal-preview"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("草稿提案差异", style = MaterialTheme.typography.titleMedium)
        Text("接受后保存为独立草稿；当前手工草稿和未保存输入保留。")
        Text("项目名 · 当前：${current?.optJSONObject("project_name")?.optString("text") ?: "未填写"}")
        Text("项目名 · 提案：${candidate?.optJSONObject("project_name")?.optString("text") ?: "未提出"}")
        val previousItems = current?.optJSONArray("items")
        val nextItems = candidate?.optJSONArray("items")
        for (index in 0 until (nextItems?.length() ?: 0)) {
            val item = nextItems!!.getJSONObject(index)
            val id = item.optString("item_id")
            val before = (0 until (previousItems?.length() ?: 0)).map { previousItems!!.getJSONObject(it) }
                .firstOrNull { it.optString("item_id") == id }
            Text("${developmentKindLabel(item.optString("kind"))} · 提案草稿", style = MaterialTheme.typography.titleSmall)
            Text("当前：${before?.optJSONObject("text")?.optString("text") ?: "无同身份条目（新增）"}")
            Text("提案：${item.optJSONObject("text")?.optString("text").orEmpty()}")
            var expanded by remember(review.optString("review_digest"), id) { mutableStateOf(false) }
            TextButton(onClick = { expanded = !expanded }) { Text(if (expanded) "收起提案原文来源" else "查看提案原文来源") }
            if (expanded) {
                val sources = item.optJSONArray("sources")
                for (sourceIndex in 0 until (sources?.length() ?: 0)) {
                    val source = sources!!.getJSONObject(sourceIndex)
                    Text("原消息 ${source.optString("message_id")} · 版本 ${source.optString("message_revision")} · 字节范围 ${source.optString("start")}–${source.optString("end")}", style = MaterialTheme.typography.bodySmall)
                    Text(source.optString("original_message"))
                }
            }
        }
        var details by remember(review.optString("review_digest")) { mutableStateOf(false) }
        TextButton(onClick = { details = !details }) { Text(if (details) "收起完整提案记录" else "查看完整提案与来源记录") }
        if (details) Text(review.toString(2))
    }
}
