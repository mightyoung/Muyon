package com.mightyoung.muyon.product.research

import android.graphics.Bitmap
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.mightyoung.muyon.product.agentipc.ProductClient
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

private val metadataFields = linkedMapOf("title" to "论文标题", "authors" to "作者（每行一个）",
    "year" to "年份", "doi" to "DOI", "url" to "URL", "notes" to "论文备注")

@Composable
fun ResearchScreen(client: ProductClient) {
    val context = LocalContext.current
    val host = remember(client) { ResearchFileHost(context.applicationContext, client) }
    val preferences = remember { context.getSharedPreferences("muyon_product_research_v2", 0) }
    var intent by remember { mutableStateOf(preferences.getString("intent_id", null)) }
    var projectId by remember { mutableStateOf(preferences.getString("project_id", null)) }
    var projects by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var papers by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var sources by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var sourcesReady by remember { mutableStateOf(false) }
    var paper by remember { mutableStateOf<JSONObject?>(null) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }
    var projectName by remember { mutableStateOf<String?>(null) }
    var uploaded by remember { mutableStateOf<JSONObject?>(null) }
    var snapshot by remember { mutableStateOf<JSONObject?>(null) }
    var metadata by remember { mutableStateOf(metadataFields.keys.associateWith { "" }) }
    var sourceId by remember { mutableStateOf("") }
    var sourceRevision by remember { mutableStateOf("1") }
    var plan by remember { mutableStateOf<JSONObject?>(null) }
    var receipt by remember { mutableStateOf<JSONObject?>(null) }
    var submittedPlan by remember { mutableStateOf<String?>(null) }
    var discard by remember { mutableStateOf(false) }
    var pdf by remember { mutableStateOf<PrivatePdf?>(null) }
    var bitmap by remember { mutableStateOf<Bitmap?>(null) }
    var page by remember { mutableStateOf(0) }
    var projectOffset by remember { mutableStateOf(0) }
    var paperOffset by remember { mutableStateOf(0) }
    var listing by remember { mutableStateOf(false) }
    var readGeneration by remember { mutableStateOf(0) }

    fun problem(reply: JSONObject) = "${reply.optString("status")}: ${reply.optString("error", "operation_unavailable")}"
    fun array(reply: JSONObject): List<JSONObject>? {
        val values = reply.optJSONArray("data")
        return if (reply.optString("status") == "ok" && values != null)
            (0 until values.length()).map { values.getJSONObject(it) }
        else { message = problem(reply); null }
    }
    fun refresh() {
        val generation = ++readGeneration
        val id = projectId
        var remaining = if (id == null) 1 else 3
        listing = true
        fun finished() { if (generation == readGeneration && --remaining == 0) listing = false }
        client.call("projects", JSONObject().put("limit", 10).put("offset", projectOffset)) { reply ->
            if (generation == readGeneration) array(reply)?.let { projects = it }
            finished()
        }
        if (id != null) {
            client.call("papers", JSONObject().put("project_id", id).put("limit", 10).put("offset", paperOffset)) { reply ->
                if (generation == readGeneration && projectId == id) array(reply)?.let { papers = it }
                finished()
            }
            sourcesReady = false
            client.call("sources", JSONObject().put("project_id", id)) { reply ->
                if (generation == readGeneration && projectId == id) array(reply)?.let { sources = it; sourcesReady = true }
                finished()
            }
        }
    }
    fun prepare(operation: JSONObject, scope: String?, revision: String = "0") {
        if (busy || intent != null || plan != null) return
        busy = true
        val payload = JSONObject().put("operation", operation).put("expected_revision", revision)
        if (scope != null) payload.put("project_id", scope)
        client.call("prepare", payload) { reply ->
            busy = false
            val data = reply.optJSONObject("data")
            if (reply.optString("status") == "ok" && data?.has("plan_id") == true && data.has("intent_id")) plan = data
            else message = problem(reply)
        }
    }
    fun resolved(reply: JSONObject) {
        busy = false
        val data = reply.optJSONObject("data")
        if (reply.optString("status") != "ok" || data == null) { message = problem(reply); return }
        val resultReceipt = data.optJSONObject("receipt")
        val committed = data.optString("status") == "committed" && resultReceipt != null &&
            resultReceipt.optString("intent_id") == intent && resultReceipt.optString("status") == "committed"
        if (committed) {
            receipt = resultReceipt
            message = "科研操作已提交 · 版本 ${resultReceipt?.optString("revision")}"
            if (projectName != null) {
                projectId = resultReceipt?.getString("target_id")
                paperOffset = 0
                preferences.edit().putString("project_id", projectId).commit()
                client.call("chat_scope", JSONObject().put("project_id", projectId ?: JSONObject.NULL)) {}
            }
            projectName = null; uploaded = null; snapshot = null; metadata = metadataFields.keys.associateWith { "" }
        } else message = problem(data)
        if (committed || data.optString("status") in listOf("rejected", "cancelled")) {
            submittedPlan?.let { client.call("discard", JSONObject().put("plan_id", it)) {} }
            submittedPlan = null
            if (preferences.edit().remove("intent_id").commit()) intent = null
            else message += " · 恢复标记未清除，请查询原结果"
            refresh()
        }
    }
    fun fileSelected(uri: Uri?, kind: String) {
        if (uri == null || busy || intent != null || projectId == null) return
        busy = true
        val id = requireNotNull(projectId)
        host.run({ when (kind) {
            "pdf" -> host.pdf(id, uri)
            "directory" -> host.directory(id, uri)
            else -> host.archive(id, uri)
        } }) { result ->
            busy = false
            result.onSuccess { if (kind == "pdf") uploaded = it else snapshot = it }
                .onFailure { message = it.message ?: "文件导入失败"; host.run({ host.discard() }) {} }
        }
    }
    val choosePdf = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { fileSelected(it, "pdf") }
    val chooseZip = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { fileSelected(it, "zip") }
    val chooseDirectory = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { fileSelected(it, "directory") }
    fun closePreview() {
        plan?.let { client.call("discard", JSONObject().put("plan_id", it.getString("plan_id"))) {} }
        plan = null
    }
    BackHandler(enabled = busy || intent != null || plan != null || uploaded != null || snapshot != null || projectName != null || pdf != null) {
        if (!busy && intent == null) {
            if (pdf != null) { pdf = null; bitmap = null }
            else if (plan != null) closePreview()
            else discard = true
        }
    }
    LaunchedEffect(client, projectId, projectOffset, paperOffset) { refresh() }
    DisposableEffect(host) { onDispose {
        if (intent == null) plan?.let { client.call("discard", JSONObject().put("plan_id", it.getString("plan_id"))) {} }
        host.close()
    } }
    DisposableEffect(pdf) { val current = pdf; onDispose { current?.close() } }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("科研工作台", style = MaterialTheme.typography.headlineSmall)
        if (message.isNotEmpty()) Text(message, Modifier.testTag("research-status"))
        val unlocked = !busy && !listing && intent == null && plan == null
        val noDraft = uploaded == null && snapshot == null && projectName == null
        if (busy) { LinearProgressIndicator(Modifier.fillMaxWidth()); Text("正在处理，请等待当前结果") }
        if (intent != null) {
            Text("原操作待核实，不会重新提交：$intent")
            Button(enabled = !busy, onClick = {
                busy = true
                client.call("lookup", JSONObject().put("intent_id", intent)) { resolved(it) }
            }, modifier = Modifier.testTag("research-lookup")) { Text("查询原结果") }
        }
        Button(enabled = unlocked && noDraft, onClick = { projectName = "" }, modifier = Modifier.testTag("research-new-project")) { Text("新建项目") }
        TextButton(enabled = !busy && !listing && noDraft, onClick = { refresh() }) { Text("刷新科研当前值") }
        Text("项目偏移：$projectOffset · 本页 ${projects.size} 项", Modifier.testTag("research-project-page"))
        Row {
            TextButton(enabled = unlocked && noDraft && projectOffset > 0, onClick = { listing = true; projectOffset = (projectOffset - 10).coerceAtLeast(0) }, modifier = Modifier.testTag("research-project-previous")) { Text("上一页项目") }
            TextButton(enabled = unlocked && noDraft && projects.size == 10, onClick = { listing = true; projectOffset += 10 }, modifier = Modifier.testTag("research-project-next")) { Text("下一页项目") }
        }
        projects.forEach { project ->
            OutlinedButton(enabled = unlocked && noDraft, onClick = {
                val next = project.getString("id")
                pdf = null; bitmap = null
                if (projectId == next && paperOffset == 0) { paper = null; refresh() }
                else {
                    listing = true
                    projectId = next; paperOffset = 0; paper = null; papers = emptyList(); sources = emptyList()
                }
                preferences.edit().putString("project_id", projectId).commit()
                client.call("chat_scope", JSONObject().put("project_id", projectId ?: JSONObject.NULL)) {}
            }, modifier = Modifier.fillMaxWidth()) { Text("${project.optString("name")} · ${project.getString("id")}") }
        }
        projectName?.let { name ->
            OutlinedTextField(name, { projectName = it }, enabled = unlocked, label = { Text("项目名称") }, modifier = Modifier.testTag("research-project-name"))
            Button(enabled = unlocked, onClick = {
                prepare(JSONObject().put("operation", "project_create").put("project_id", UUID.randomUUID().toString()).put("name", name), null)
            }, modifier = Modifier.testTag("research-project-preview")) { Text("预览新建项目") }
        }
        projectId?.let { id ->
            Text("当前项目：$id")
            if (noDraft) {
                Button(enabled = unlocked, onClick = { choosePdf.launch(arrayOf("application/pdf")) }, modifier = Modifier.testTag("research-add-pdf")) { Text("添加独立 PDF") }
                Button(enabled = unlocked, onClick = { chooseDirectory.launch(null) }) { Text("导入科研工作台目录") }
                Button(enabled = unlocked, onClick = { chooseZip.launch(arrayOf("application/zip", "application/x-zip-compressed")) }) { Text("导入科研工作台 ZIP") }
            }
            uploaded?.let { finished ->
                Text("PDF已受控暂存，尚未添加论文。")
                metadataFields.forEach { (key, label) ->
                    OutlinedTextField(metadata.getValue(key), { metadata = metadata + (key to it) }, enabled = unlocked,
                        label = { Text(label) }, modifier = Modifier.fillMaxWidth().testTag("research-field-$key"))
                }
                Button(enabled = unlocked, onClick = {
                    val year = metadata.getValue("year")
                    val parsedYear = year.toIntOrNull()
                    if (year.isNotEmpty() && (parsedYear == null || parsedYear !in 1..9999)) {
                        message = "年份需为1至9999的整数，或留空"; return@Button
                    }
                    val payload = JSONObject().put("title", metadata.getValue("title"))
                        .put("authors", JSONArray(metadata.getValue("authors").lines().filter { it.isNotEmpty() }))
                        .put("year", parsedYear ?: JSONObject.NULL)
                        .put("attachment", finished.getJSONObject("blob")).put("attachment_upload_id", finished.getString("upload_id"))
                    listOf("doi", "url", "notes").forEach { payload.put(it, metadata.getValue(it).takeIf(String::isNotEmpty) ?: JSONObject.NULL) }
                    prepare(JSONObject().put("operation", "paper_create").put("paper_id", UUID.randomUUID().toString()).put("payload", payload), id)
                }, modifier = Modifier.testTag("research-paper-preview")) { Text("预览添加论文") }
            }
            snapshot?.let { frozen ->
                Text("已验证快照：${frozen.optInt("record_count")} 条记录 · ${frozen.optString("layout")}")
                OutlinedTextField(sourceId, { sourceId = it }, enabled = unlocked, label = { Text("稳定来源标识") }, modifier = Modifier.testTag("research-source-id"))
                OutlinedTextField(sourceRevision, { sourceRevision = it }, enabled = unlocked, label = { Text("外部来源版本（正整数）") }, modifier = Modifier.testTag("research-source-revision"))
                val previous = sources.firstOrNull { it.optString("source_id") == sourceId }?.optString("revision") ?: "0"
                Text(if (sourcesReady) "本地来源版本：$previous" else "正在读取来源版本，无法提交")
                Button(enabled = unlocked && sourcesReady, onClick = {
                    if (!Regex("[1-9][0-9]*").matches(sourceRevision)) { message = "来源版本需为正整数"; return@Button }
                    prepare(JSONObject().put("operation", "research_import").put("source_id", sourceId)
                        .put("source_revision", sourceRevision).put("snapshot", frozen.getJSONObject("snapshot"))
                        .put("snapshot_upload_id", frozen.getString("snapshot_upload_id")).put("records", JSONArray()), id, previous)
                }, modifier = Modifier.testTag("research-import-preview")) { Text("预览导入快照") }
            }
            Text("论文偏移：$paperOffset · 本页 ${papers.size} 项", Modifier.testTag("research-paper-page"))
            Row {
                TextButton(enabled = unlocked && noDraft && paperOffset > 0, onClick = { listing = true; paperOffset = (paperOffset - 10).coerceAtLeast(0) }, modifier = Modifier.testTag("research-paper-previous")) { Text("上一页论文") }
                TextButton(enabled = unlocked && noDraft && papers.size == 10, onClick = { listing = true; paperOffset += 10 }, modifier = Modifier.testTag("research-paper-next")) { Text("下一页论文") }
            }
            papers.forEach { entry ->
                OutlinedButton(enabled = unlocked && noDraft, onClick = {
                    busy = true
                    client.call("paper", JSONObject().put("project_id", id).put("paper_id", entry.getString("id"))) { reply ->
                        busy = false
                        if (reply.optString("status") == "ok") paper = reply.optJSONObject("data") else message = problem(reply)
                    }
                }, modifier = Modifier.fillMaxWidth()) { Text("${entry.optString("title")} · ${entry.getString("id")}") }
            }
            paper?.let { detail ->
                Text("论文详情：${detail.optString("title")}", Modifier.testTag("research-paper-detail"))
                Text(detail.optString("raw_json"))
                if (detail.optBoolean("raw_json_truncated")) Text("元数据预览已截断；原始 ${detail.optString("raw_json_byte_length")} 字节仍完整保存在工作台中")
                val attachments = detail.optJSONArray("attachments") ?: JSONArray()
                for (index in 0 until attachments.length()) {
                    Button(enabled = unlocked && noDraft, onClick = {
                        busy = true
                        host.run({ host.attachment(id, detail.getString("id"), attachments.getJSONObject(index)).let { it to it.render(0) } }) { result ->
                            busy = false
                            result.onSuccess { pdf = it.first; bitmap = it.second; page = 0 }.onFailure { message = it.message ?: "附件打开失败" }
                        }
                    }, modifier = Modifier.testTag("research-open-attachment-$index")) { Text("打开受控附件 ${index + 1}") }
                }
            }
        }
        if (!noDraft) TextButton(enabled = unlocked, onClick = { discard = true }) { Text("放弃科研草稿") }
        receipt?.let { Text("历史回执（不代表当前值）：${it.optString("intent_id")} · ${it.optString("target_id")} · 版本 ${it.optString("revision")}", Modifier.testTag("research-receipt")) }
        pdf?.let { viewer ->
            bitmap?.let { Image(it.asImageBitmap(), "论文 PDF 第 ${page + 1} 页", Modifier.fillMaxWidth().heightIn(max = 800.dp)) }
            Text("第 ${page + 1} / ${viewer.pages} 页")
            Row {
                listOf(-1 to "上一页", 1 to "下一页").forEach { (offset, label) ->
                    TextButton(enabled = !busy && page + offset in 0 until viewer.pages, onClick = {
                        busy = true
                        val next = page + offset
                        host.run({ viewer.render(next) }) { result -> busy = false; result.onSuccess { bitmap = it; page = next }.onFailure { message = "附件读取失败" } }
                    }) { Text(label) }
                }
                TextButton(enabled = !busy, onClick = { pdf = null; bitmap = null }) { Text("关闭附件") }
            }
        }
    }
    plan?.let { envelope ->
        AlertDialog(onDismissRequest = { if (!busy) closePreview() }, title = { Text("确认科研操作") },
            text = { Column(Modifier.verticalScroll(rememberScrollState())) {
                Text("确认后才写入；附件和快照将在同一操作内发布。")
                Text(envelope.getJSONObject("command").toString(2), Modifier.testTag("research-preview"))
                Text("基于版本 ${envelope.optString("expected_revision")}")
            } }, confirmButton = {
                Button(enabled = !busy, onClick = {
                    if (busy || intent != null) return@Button
                    val original = envelope.getString("intent_id")
                    if (!preferences.edit().putString("intent_id", original).putString("project_id", projectId).commit()) {
                        message = "恢复标记保存失败，尚未提交"; return@Button
                    }
                    intent = original; submittedPlan = envelope.getString("plan_id"); plan = null; busy = true
                    client.call("confirm", JSONObject().put("plan_id", envelope.getString("plan_id"))) { resolved(it) }
                }, modifier = Modifier.testTag("research-confirm")) { Text("确认科研写入") }
            }, dismissButton = { TextButton(onClick = { closePreview() }, enabled = !busy) { Text("返回科研草稿") } })
    }
    if (discard) AlertDialog(onDismissRequest = { discard = false }, title = { Text("放弃尚未提交的科研草稿？") },
        confirmButton = { TextButton(onClick = {
            discard = false; busy = true
            host.run({ host.discard() }) {
                busy = false; uploaded = null; snapshot = null; projectName = null
                metadata = metadataFields.keys.associateWith { "" }
            }
        }) { Text("放弃科研草稿") } }, dismissButton = { TextButton(onClick = { discard = false }) { Text("继续科研编辑") } })
}
