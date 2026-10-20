package com.mightyoung.muyon.product.chat

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.mightyoung.muyon.product.agentipc.ProductClient
import org.json.JSONObject

/** Local reads are shown as local records, never as a fabricated model answer. */
@Composable
fun ChatScreen(client: ProductClient, projectId: String?) {
    val context = LocalContext.current
    val saved = remember { context.getSharedPreferences("product-chat-state", android.content.Context.MODE_PRIVATE) }
    var conversation by remember { mutableStateOf(saved.getString("conversation", null) ?: java.util.UUID.randomUUID().toString().also { saved.edit().putString("conversation", it).commit() }) }
    var original by remember { mutableStateOf(saved.getString("original_request", null)) }
    var settingsOpen by remember { mutableStateOf(false) }
    var key by remember { mutableStateOf("") }
    var cap by remember { mutableStateOf("1000000") }
    var calls by remember { mutableStateOf("10") }
    var configured by remember { mutableStateOf(false) }
    var review by remember { mutableStateOf<JSONObject?>(null) }
    var resultText by remember { mutableStateOf("") }
    var searchResults by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var accounting by remember { mutableStateOf("") }
    var pendingTool by remember { mutableStateOf<JSONObject?>(null) }
    var disclosure by remember { mutableStateOf<JSONObject?>(null) }
    var disclosureSuggestion by remember { mutableStateOf(false) }
    var suggestion by remember { mutableStateOf<JSONObject?>(null) }
    var followupReady by remember { mutableStateOf(false) }
    var businessPlan by remember { mutableStateOf(saved.getString("original_business_plan", null)) }
    var scopeReady by remember(projectId) { mutableStateOf(false) }
    var availability by remember { mutableStateOf<JSONObject?>(null) }
    var error by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var records by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var tool by remember { mutableStateOf("supplier_list") }
    var offset by remember { mutableIntStateOf(0) }
    var draft by remember { mutableStateOf("") }
    var source by remember { mutableStateOf("") }
    val currentProject by rememberUpdatedState(projectId)

    fun refreshStatus() {
        client.call("agent_availability") { reply ->
            if (reply.optString("status") == "ok") {
                availability = reply.optJSONObject("data")
                error = ""
            } else error = "暂时无法读取聊天状态，请重新连接后刷新。"
        }
    }
    fun observe() {
        val request = original ?: return
        client.call("chat_lookup", JSONObject().put("request_id", request)) { reply ->
            val result = reply.optJSONObject("data")
            if (reply.optString("status") != "ok" || result == null) {
                resultText = "原请求结果尚未取得，请继续查询；不会自动重发。"
            } else {
                val sources = result.optJSONArray("answer")
                searchResults = if (sources == null) emptyList() else (0 until sources.length()).map { sources.getJSONObject(it) }
                resultText = when (result.optString("status")) {
                    "tool_pending" -> {
                        pendingTool = result.optJSONObject("answer")?.optJSONObject("call")
                        "模型调用已结算，等待您查看业务动作；不会自动读取后外发、提交修改或继续请求。"
                    }
                    "completed" -> result.optJSONObject("answer")?.let { answer ->
                        answer.optString("answer") + "\n输入 ${answer.optString("input_tokens")}，输出 ${answer.optString("output_tokens")} token；本次成本上界 ${result.optString("charged_micro_cny")} 微人民币。"
                    }
                        ?: "搜索完成：${result.optJSONArray("answer")?.length() ?: 0} 条外部结果。"
                    "cancelled" -> "已取消。已开始外发的请求仍可能保留费用上界。"
                    "prepared" -> "尚未确认，未发出请求。"
                    else -> "原请求结果未知，费用保留，继续查询原结果。"
                }
            }
        }
        client.call("chat_budget") { reply ->
            reply.optJSONObject("data")?.let { data ->
                accounting = "累计成本上界 ${data.optString("charged_micro_cny")} / ${data.optString("cap_micro_cny")} 微人民币；未知或待发保留 ${data.optString("held_micro_cny")} 微人民币。"
            }
        }
    }
    fun preview(search: Boolean) {
        client.call("chat_prepare", JSONObject().put("conversation_id", conversation)
            .put("text", draft).put("search", search).put("count", 5).put("project_id", projectId ?: JSONObject.NULL)) { reply ->
            val data = reply.optJSONObject("data")
            if (reply.optString("status") == "ok" && data?.has("request_id") == true) review = data
            else error = "请求预览未完成，请检查配置、输入或先查询原请求。"
        }
    }
    fun toolAction(action: String, planId: String? = null, digest: String? = null, callback: (JSONObject) -> Unit) {
        val request = original ?: return
        client.call("chat_tool", JSONObject().put("action", action).put("request_id", request)
            .put("plan_id", planId ?: JSONObject.NULL).put("digest", digest ?: JSONObject.NULL)) { reply ->
            val data = reply.optJSONObject("data")
            if (reply.optString("status") == "ok" && data != null && !data.has("error")) callback(data)
            else error = "工具动作未完成；请查询原结果，作用域改变或结果未知时不会自动重试。"
        }
    }
    fun read(selectedTool: String, selectedOffset: Int) {
        if (loading) return
        loading = true
        val requestedProject = projectId
        client.call("agent_read", JSONObject()
            .put("project_id", projectId ?: JSONObject.NULL)
            .put("request", JSONObject().put("tool", selectedTool).put("limit", 20).put("offset", selectedOffset))) { reply ->
            loading = false
            if (currentProject != requestedProject) return@call
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
                error = "本地读取未完成，请检查项目或重新连接。"
                records = emptyList()
            }
        }
    }
    LaunchedEffect(client) { refreshStatus() }
    LaunchedEffect(client, projectId) {
        records = emptyList(); source = ""; offset = 0
        pendingTool = null; disclosure = null; suggestion = null; followupReady = false
        val requested = projectId
        client.call("chat_scope", JSONObject().put("project_id", projectId ?: JSONObject.NULL)) { reply ->
            if (currentProject == requested) scopeReady = reply.optString("status") == "ok" && reply.optJSONObject("data")?.has("scope_generation") == true
        }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("聊天与工作台", style = MaterialTheme.typography.headlineSmall)
        Text("DeepSeek · 独立产品配置与累计预算")
        Text(if (availability == null) "连接状态未读取" else "本地读取已连接；实际外发仍需通过计费证明与预算检查", Modifier.testTag("chat-availability"))
        OutlinedButton(onClick = { settingsOpen = true }) { Text("模型与预算设置") }
        OutlinedButton(onClick = {
            val next = java.util.UUID.randomUUID().toString()
            if (saved.edit().putString("conversation", next).commit()) {
                conversation = next; pendingTool = null; disclosure = null; suggestion = null; followupReady = false
                resultText = "已开始新会话，不会携带之前披露的业务数据；原请求仍可独立查询。"
            }
        }) { Text("开始新会话") }
        OutlinedButton(onClick = { refreshStatus() }) { Text("刷新连接状态") }
        OutlinedTextField(value = draft, onValueChange = { draft = it.take(4096) }, label = { Text("消息草稿") }, modifier = Modifier.fillMaxWidth())
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { preview(false) }, enabled = configured && scopeReady && draft.isNotBlank(), modifier = Modifier.testTag("chat-send")) { Text("预览聊天请求") }
            OutlinedButton(onClick = { preview(true) }, enabled = configured && scopeReady && draft.isNotBlank()) { Text("预览搜索请求") }
        }
        Text("配置不会发出请求。凭据仅保留在当前 Service 内存，重启后需重新输入。当前托管聊天计费上界与搜索价格证明尚未安装，预览会明确阻止外发。")
        if (original != null) {
            Text("原请求：$original")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { observe() }) { Text("查询原结果") }
                OutlinedButton(onClick = { client.call("chat_cancel", JSONObject().put("request_id", original)) { observe() } }) { Text("取消原请求") }
            }
        }
        if (resultText.isNotEmpty()) Text(resultText, Modifier.testTag("chat-original-result"))
        if (accounting.isNotEmpty()) Text(accounting)
        pendingTool?.takeIf { scopeReady }?.let { call ->
            Text("待处理动作：${call.optString("name")}")
            Text(call.optJSONObject("arguments")?.toString(2) ?: "")
            if (call.optString("name").endsWith("_suggest")) {
                OutlinedButton(onClick = { toolAction("prepare_suggestion") { suggestion = it } }) { Text("查看业务修改建议") }
                businessPlan?.let { plan -> OutlinedButton(onClick = {
                    toolAction("review_suggestion", plan) { disclosureSuggestion = true; disclosure = it }
                }) { Text("查询原业务结果") } }
            } else OutlinedButton(onClick = {
                toolAction("review_read") { disclosureSuggestion = false; disclosure = it }
            }) { Text("查看将披露的实际字段") }
            if (followupReady) OutlinedButton(onClick = { toolAction("followup") { review = it; followupReady = false } }) { Text("预览独立的后续模型请求") }
        }
        searchResults.forEach { result -> Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(result.optString("title"), style = MaterialTheme.typography.titleMedium)
                Text(result.optString("url"))
                Text(result.optString("snippet"))
                Text(result.optString("summary"))
            }
        } }
        Text("可以先查看当前业务记录。这里的本地内容不会自动发送给模型；业务修改需在对应页面预览并确认。")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { read("supplier_list", 0) }, enabled = !loading) { Text("读取供应商") }
            OutlinedButton(onClick = { read("paper_list", 0) }, enabled = !loading && projectId != null) { Text("读取项目论文") }
        }
        if (projectId == null) Text("选择科研项目后可读取该项目论文。")
        if (loading) CircularProgressIndicator()
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
    if (settingsOpen) AlertDialog(
        onDismissRequest = { settingsOpen = false; key = "" },
        title = { Text("确认新的产品配置") },
        text = { Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("供应商：DeepSeek；端点固定为 api.deepseek.com。不会读取历史凭据或预算。")
            OutlinedTextField(value = key, onValueChange = { key = it.take(512) }, label = { Text("新凭据（仅当前进程）") }, visualTransformation = PasswordVisualTransformation())
            OutlinedTextField(value = cap, onValueChange = { cap = it.filter(Char::isDigit).take(13) }, label = { Text("累计上限（微人民币）") })
            OutlinedTextField(value = calls, onValueChange = { calls = it.filter(Char::isDigit).take(6) }, label = { Text("累计请求数上限") })
            Text("1 元 = 1,000,000 微人民币。每次确认先保留经可信证明的请求成本上界；未知结果保留占额。更换配置不会清零已用费用或未知保留。填写预算不能替代真实计费证明。")
        } },
        confirmButton = { TextButton(onClick = {
            val input = key.toCharArray(); key = ""; settingsOpen = false
            client.configureChat(JSONObject().put("cap_micro_cny", cap).put("max_calls", calls).put("chat", true).put("search", true), input) { reply ->
                input.fill('\u0000')
                configured = reply.optString("status") == "ok" && reply.optJSONObject("data")?.has("id") == true
                error = if (configured) "" else "配置未完成，未发出请求。"
            }
        }, enabled = key.length in 16..512 && cap.isNotEmpty() && calls.isNotEmpty()) { Text("确认配置与累计预算") } },
        dismissButton = { TextButton(onClick = { settingsOpen = false; key = "" }) { Text("取消") } }
    )
    review?.let { plan -> AlertDialog(
        onDismissRequest = { client.call("chat_cancel", JSONObject().put("request_id", plan.optString("request_id"))) {}; review = null }, title = { Text("请求预览") },
        text = { Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("${if (plan.optString("purpose") == "search") "外部搜索" else "模型聊天"} · DeepSeek")
            Text("本次保留上界：${plan.optString("reserved_micro_cny")} 微人民币")
            Text("请求身份：${plan.optString("request_id")}")
            if (!plan.optBoolean("send_allowed")) Text("尚无可信的托管计费或搜索价格证明；此次请求不会发出。")
            Text("确认仅执行本次请求；超时或重启后查询原身份，不自动重发。")
        } },
        confirmButton = { TextButton(onClick = {
            val request = plan.getString("request_id")
            if (saved.edit().putString("original_request", request).commit()) {
                original = request; review = null
                client.call("chat_confirm", JSONObject().put("request_id", request)) { observe() }
            } else error = "原请求身份未能保存，未发出请求。"
        }, enabled = plan.optBoolean("send_allowed")) { Text("确认本次外发") } },
        dismissButton = { TextButton(onClick = { client.call("chat_cancel", JSONObject().put("request_id", plan.optString("request_id"))) {}; review = null }) { Text("返回") } }
    ) }
    disclosure?.let { data -> AlertDialog(
        onDismissRequest = { disclosure = null }, title = { Text("批准本次业务信息披露") },
        text = { Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
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
        onDismissRequest = { suggestion = null }, title = { Text("确认本次业务修改") },
        text = { Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
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
            if (saved.edit().putString("original_business_plan", plan).putString("original_business_intent", intent).commit()) {
                businessPlan = plan; suggestion = null
                toolAction("confirm_suggestion", plan) { disclosureSuggestion = true; disclosure = it }
            } else error = "原业务身份未能保存，未执行修改。"
        }, enabled = data.optJSONObject("business_preview")?.has("command") == true) { Text("确认以上完整修改") } },
        dismissButton = { TextButton(onClick = { suggestion = null }) { Text("取消修改") } }
    ) }
}
