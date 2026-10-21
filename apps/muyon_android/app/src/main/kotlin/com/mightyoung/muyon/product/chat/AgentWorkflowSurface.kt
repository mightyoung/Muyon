package com.mightyoung.muyon.product.chat

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import com.mightyoung.muyon.product.agentipc.ProductClient
import com.mightyoung.muyon.product.agents.visibleName
import kotlinx.coroutines.delay
import org.json.JSONArray
import org.json.JSONObject

private fun JSONArray?.objects(): List<JSONObject> = if (this == null) emptyList() else
    (0 until length()).mapNotNull { optJSONObject(it) }

internal fun workflowReplyData(reply: JSONObject): JSONObject? {
    val data = reply.optJSONObject("data") ?: return null
    return data.takeIf { reply.optString("status") == "ok" && it.isNull("error") && it.optString("status") !in setOf("unavailable", "unknown") }
}

private fun workflowFailureCode(reply: JSONObject): String {
    val code = reply.optJSONObject("data")?.optString("error")?.takeIf { it.isNotBlank() }
        ?: reply.optString("error")
    return code.takeIf { it.matches(Regex("[a-z][a-z0-9_]{0,99}")) } ?: "workflow_operation_unavailable"
}

internal fun workflowChildCount(snapshot: JSONObject?): Int = snapshot?.optJSONArray("runs").objects().count { !it.isNull("parent_id") }

@Composable
private fun WorkflowFailure(message: String, code: String) {
    var details by remember(code) { mutableStateOf(false) }
    Column {
        Text(message, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        TextButton(onClick = { details = !details }) { Text(if (details) "收起错误详情" else "错误详情") }
        if (details) Text(code, style = MaterialTheme.typography.bodySmall)
    }
}

/** Only received execution facts are presented. There is no synthetic reasoning stream. */
@Composable
internal fun AgentWorkflowSurface(
    client: ProductClient,
    conversation: String,
    project: String?,
    managerOpen: Boolean,
    onDismiss: () -> Unit,
    onRemotePlan: (JSONObject) -> Unit,
) {
    key(client, conversation, project) {
        WorkflowContent(client, conversation, project, managerOpen, onDismiss, onRemotePlan)
    }
}

@Composable
private fun WorkflowContent(client: ProductClient, conversation: String, project: String?, managerOpen: Boolean,
    onDismiss: () -> Unit, onRemotePlan: (JSONObject) -> Unit) {
    var live by remember { mutableStateOf(true) }
    DisposableEffect(Unit) { onDispose { live = false } }
    var roots by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var skills by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var rootId by remember { mutableStateOf("") }
    var snapshot by remember { mutableStateOf<JSONObject?>(null) }
    var expanded by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf("") }
    var errorCode by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var title by remember { mutableStateOf("") }
    var task by remember { mutableStateOf("") }
    var childTask by remember { mutableStateOf("") }
    var skillId by remember { mutableStateOf("") }
    var executor by remember { mutableStateOf("local_read") }
    var skillBody by remember { mutableStateOf<JSONObject?>(null) }
    val latestRoot by rememberUpdatedState(rootId)
    val remotePlan by rememberUpdatedState(onRemotePlan)
    fun request(operation: JSONObject, mutation: Boolean = false, receive: (JSONObject) -> Unit = {}) {
        if (mutation) busy = true
        client.call("agent_workflow", JSONObject().put("conversation_id", conversation).put("operation", operation)) { reply ->
            if (!live) return@call
            if (mutation) busy = false
            val data = workflowReplyData(reply)
            if (data != null) { error = ""; receive(data) }
            else { error = "任务状态暂未取得，请刷新查看原任务。"; errorCode = workflowFailureCode(reply) }
        }
    }
    fun refresh() {
        request(JSONObject().put("action", "list").put("limit", 20)) { data ->
            roots = data.optJSONArray("roots").objects()
            if (latestRoot.isBlank() || roots.none { it.optString("id") == latestRoot }) rootId = roots.firstOrNull()?.optString("id").orEmpty()
        }
        if (rootId.isNotBlank()) request(JSONObject().put("action", "snapshot").put("root_id", rootId).put("after_seq", 0)) { data ->
            if (data.optJSONObject("root")?.optString("id") == latestRoot) snapshot = data
        }
    }
    fun mutate(operation: JSONObject) = request(operation, true) { refresh() }
    LaunchedEffect(client, conversation, project) { refresh() }
    LaunchedEffect(rootId) { snapshot = null; if (rootId.isNotBlank()) refresh() }
    LaunchedEffect(managerOpen) {
        if (managerOpen) request(JSONObject().put("action", "skills")) { skills = it.optJSONArray("skills").objects() }
    }
    LaunchedEffect(expanded, managerOpen) {
        while (expanded || managerOpen) { delay(1800); if (!busy) refresh() }
    }
    if (roots.isNotEmpty()) {
        Column(Modifier.fillMaxWidth().testTag("workflow-surface")) {
            TextButton(onClick = { expanded = !expanded }, modifier = Modifier.testTag("workflow-expand")) { Text("执行过程 · ${workflowChildCount(snapshot)}项子任务${if (expanded) " ∧" else " ∨"}") }
            if (expanded) {
                Text("以下是任务与工具的执行记录。", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                WorkflowRecords(roots, rootId, { rootId = it }, snapshot, busy,
                    { mutate(JSONObject().put("action", "cancel").put("run_id", it)) },
                    { mutate(JSONObject().put("action", "execute_local").put("run_id", it)) },
                    { run ->
                        busy = true
                        client.call("workflow_prepare", JSONObject().put("conversation_id", conversation).put("run_id", run)) { reply ->
                            if (live) {
                                busy = false
                                val plan = workflowReplyData(reply)
                                if (plan != null && plan.optString("request_id").isNotBlank()) { remotePlan(plan); refresh() }
                                else { error = "尚未取得外发预览，请刷新查看原任务。"; errorCode = workflowFailureCode(reply) }
                            }
                        }
                    })
                if (error.isNotBlank()) WorkflowFailure(error, errorCode)
            }
        }
    }
    if (managerOpen) Dialog(onDismissRequest = onDismiss) {
        Surface(shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surface,
            modifier = Modifier.testTag("workflow-manager").widthIn(max = 680.dp).fillMaxWidth().heightIn(max = 720.dp)) {
            Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("任务与技能", style = MaterialTheme.typography.titleLarge)
                    TextButton(onClick = onDismiss) { Text("关闭") }
                }
                Text("本地工具任务只读取本地数据；AI子任务需要单独查看外发内容与费用并确认。", style = MaterialTheme.typography.bodySmall)
                if (error.isNotBlank()) WorkflowFailure(error, errorCode)
                TextButton(onClick = { refresh() }, enabled = !busy) { Text("刷新原任务") }
                OutlinedTextField(title, { title = it.take(120) }, label = { Text("任务名称") }, modifier = Modifier.testTag("workflow-title").fillMaxWidth())
                OutlinedTextField(task, { task = it.take(8000) }, label = { Text("目标与要求") }, minLines = 2, modifier = Modifier.testTag("workflow-task").fillMaxWidth())
                Button(onClick = {
                    request(JSONObject().put("action", "create_root").put("title", title).put("task", task), true) {
                        rootId = it.optString("id"); title = ""; task = ""; refresh()
                    }
                }, modifier = Modifier.testTag("workflow-create-root"), enabled = !busy && title.isNotBlank() && task.isNotBlank()) { Text("创建任务") }
                if (roots.isNotEmpty()) {
                    Text("任务", style = MaterialTheme.typography.titleMedium)
                    roots.forEach { root -> TextButton(onClick = { rootId = root.optString("id") }) {
                        Text("${if (rootId == root.optString("id")) "✓ " else ""}${visibleName(root.optString("title"), "未命名任务")} · ${workflowStatus(root.optString("status"))}")
                    } }
                }
                HorizontalDivider()
                Text("技能", style = MaterialTheme.typography.titleMedium)
                skills.forEach { skill ->
                    Row(Modifier.fillMaxWidth()) {
                        Column(Modifier.weight(1f)) {
                        TextButton(onClick = { skillId = skill.optString("id") }, modifier = Modifier.testTag("workflow-skill-${skill.optString("id")}")) { Text("${if (skillId == skill.optString("id")) "✓ " else ""}${visibleName(skill.optString("name", skill.optString("title")), "未命名技能")}") }
                            Text(skill.optString("description"), style = MaterialTheme.typography.bodySmall)
                            TextButton(onClick = { request(JSONObject().put("action", "load_skill").put("skill_id", skill.optString("id"))) { skillBody = it } }) { Text("查看技能正文") }
                        }
                        Switch(checked = skill.optBoolean("enabled"), modifier = Modifier.testTag("workflow-skill-toggle-${skill.optString("id")}")
                            .semantics { contentDescription = "启用技能 ${visibleName(skill.optString("name", skill.optString("title")), "未命名技能")}" }, enabled = !busy, onCheckedChange = { enabled ->
                            request(JSONObject().put("action", "set_skill").put("skill_id", skill.optString("id")).put("enabled", enabled), true) {
                                request(JSONObject().put("action", "skills")) { skills = it.optJSONArray("skills").objects() }
                            }
                        })
                    }
                }
                skillBody?.let { body ->
                    Surface(color = MaterialTheme.colorScheme.surfaceVariant, shape = MaterialTheme.shapes.medium) {
                        Column(Modifier.padding(12.dp)) {
                            Text(body.optString("name", "技能正文"), style = MaterialTheme.typography.titleMedium)
                            ConversationRichText(body.optString("body", body.optString("content", "正文未返回")))
                            TextButton(onClick = { skillBody = null }) { Text("收起正文") }
                        }
                    }
                }
                if (rootId.isNotBlank()) {
                    HorizontalDivider()
                    Text("派生子任务", style = MaterialTheme.typography.titleMedium)
                    OutlinedTextField(childTask, { childTask = it.take(8000) }, label = { Text("子任务要求") }, minLines = 2, modifier = Modifier.testTag("workflow-child-task").fillMaxWidth())
                    Row {
                        FilterChip(executor == "local_read", { executor = "local_read" }, { Text("本地工具任务") })
                        Spacer(Modifier.width(8.dp))
                        FilterChip(executor == "remote_chat", { executor = "remote_chat" }, { Text("AI子任务") })
                    }
                    val chosenSkill = skills.firstOrNull { it.optString("id") == skillId }
                    Text("${chosenSkill?.optString("name", chosenSkill.optString("title")) ?: "请选择一个技能"} · 子任务不会自动执行", style = MaterialTheme.typography.bodySmall)
                    Button(onClick = {
                        request(JSONObject().put("action", "create_child").put("root_id", rootId).put("skill_id", skillId).put("task", childTask)
                            .put("executor", executor).put("arguments", JSONObject().put("limit", 10).put("offset", 0)), true) { childTask = ""; refresh() }
                    }, modifier = Modifier.testTag("workflow-create-child"), enabled = !busy && childTask.isNotBlank() && skills.any { it.optString("id") == skillId && it.optBoolean("enabled") }) { Text("创建子任务") }
                    TextButton(onClick = { expanded = true; onDismiss() }, modifier = Modifier.testTag("workflow-show-activity")) { Text("查看执行过程") }
                }
            }
        }
    }
}

internal fun workflowStatus(status: String): String = when (status) {
    "planned", "created", "pending", "queued" -> "待执行"
    "running" -> "执行中"
    "completed" -> "已完成"
    "cancelled" -> "已停止"
    "blocked" -> "受阻"
    "failed" -> "失败"
    "awaiting_confirmation", "waiting_confirmation", "prepared" -> "等待确认"
    "unknown" -> "结果未知"
    else -> "状态未知"
}

@Composable
private fun WorkflowRecords(roots: List<JSONObject>, rootId: String, select: (String) -> Unit, snapshot: JSONObject?, busy: Boolean,
    cancel: (String) -> Unit, execute: (String) -> Unit, preview: (String) -> Unit) {
    if (roots.size > 1) {
        var choosing by remember { mutableStateOf(false) }
        Box {
            TextButton(onClick = { choosing = true }, modifier = Modifier.testTag("workflow-root-selector")) {
                Text(roots.firstOrNull { it.optString("id") == rootId }?.optString("title").orEmpty(),
                    modifier = Modifier.weight(1f, fill = false), maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(" ▾")
            }
            DropdownMenu(expanded = choosing, onDismissRequest = { choosing = false }) {
                roots.forEach { root -> DropdownMenuItem(text = {
                    Text("${if (rootId == root.optString("id")) "✓ " else ""}${root.optString("title")}",
                        maxLines = 2, overflow = TextOverflow.Ellipsis)
                }, onClick = { select(root.optString("id")); choosing = false }) }
            }
        }
    }
    snapshot?.optJSONArray("runs").objects().forEach { run ->
        var details by remember(run.optString("id")) { mutableStateOf(false) }
        val kind = run.optString("executor", run.optString("kind"))
        val status = run.optString("status")
        Surface(Modifier.fillMaxWidth().padding(vertical = 4.dp), shape = MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.surfaceVariant) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(visibleName(run.optString("title").ifBlank { run.optString("task") }, "未命名任务"), style = MaterialTheme.typography.titleSmall)
                Text("${if (kind == "local_read") "本地工具任务" else if (kind == "remote_chat") "AI子任务" else "任务"} · ${workflowStatus(status)}", style = MaterialTheme.typography.bodySmall)
                run.optString("blocked_reason").takeIf { it.isNotBlank() && it != "null" }?.let { WorkflowFailure("任务暂时受阻，请检查配置、权限或查询原请求。", it) }
                val result = run.opt("result")
                if (result != null && result != JSONObject.NULL) {
                    TextButton(onClick = { details = !details }, modifier = Modifier.testTag("workflow-result-${run.optString("id")}")) { Text(if (details) "收起结果" else "查看结果") }
                    if (details) WorkflowResult(result, Modifier.testTag("workflow-result-body-${run.optString("id")}"))
                }
                if (run.optBoolean("can_control")) Row {
                    if (status in setOf("planned", "created", "pending", "queued")) {
                        if (kind == "local_read") TextButton(onClick = { execute(run.optString("id")) }, modifier = Modifier.testTag("workflow-execute-${run.optString("id")}"), enabled = !busy) { Text("执行本地工具") }
                        if (kind == "remote_chat") TextButton(onClick = { preview(run.optString("id")) }, enabled = !busy) { Text("查看外发预览") }
                    }
                    if (status !in setOf("completed", "cancelled", "failed")) TextButton(onClick = { cancel(run.optString("id")) }, enabled = !busy) { Text("停止任务") }
                }
            }
        }
    }
    snapshot?.optJSONArray("events").objects().forEach { event ->
        WorkflowEventSummary(event)
    }
}

@Composable
internal fun WorkflowResult(result: Any, modifier: Modifier = Modifier) {
    val value = result as? JSONObject
    val records = value?.optJSONArray("records")
    if (value?.optString("source") == "current_local_business" && records != null) {
        var technical by remember(result.toString()) { mutableStateOf(false) }
        Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("已读取 ${records.length()} 条本地记录", style = MaterialTheme.typography.bodyMedium)
            records.objects().forEach { record ->
                val payload = record.optJSONObject("payload")
                val label = payload?.optString("name")?.takeIf { it.isNotBlank() }
                    ?: payload?.optString("title")?.takeIf { it.isNotBlank() }
                    ?: "未命名记录"
                Text("• $label", style = MaterialTheme.typography.bodyMedium)
            }
            Text("来源：本地业务数据", style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            TextButton(onClick = { technical = !technical }) { Text(if (technical) "收起原始记录" else "查看原始记录") }
            if (technical) ConversationRichText("```json\n${value.toString(2)}\n```")
        }
    } else if (value != null) {
        var technical by remember(result.toString()) { mutableStateOf(false) }
        val answer = (value.opt("answer") as? String)?.takeIf { it.isNotBlank() }
            ?: (value.opt("summary") as? String)?.takeIf { it.isNotBlank() } ?: "任务结果已返回。"
        Column(modifier) {
            ConversationRichText(answer)
            TextButton(onClick = { technical = !technical }, modifier = Modifier.testTag("workflow-result-metadata")) {
                Text(if (technical) "收起原始详情" else "查看原始详情")
            }
            if (technical) ConversationRichText("```json\n${value.toString(2)}\n```")
        }
    } else ConversationRichText(result.toString(), modifier)
}

@Composable
internal fun WorkflowEventSummary(event: JSONObject) {
    val summary = event.optString("summary").ifBlank { event.optString("message") }
    if (summary.isNotBlank() && summary != "null") Text(summary, Modifier.testTag("workflow-event"), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
}
