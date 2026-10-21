package com.mightyoung.muyon.product.supplier

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.mightyoung.muyon.product.agentipc.ProductClient
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

private val fields = linkedMapOf(
    "name" to "名称", "aliases" to "别名（每行一个）", "address" to "地址",
    "categories" to "类别（每行一个）", "notes" to "备注",
    "rating" to "评级（preferred / caution / disabled，可留空）", "rating_note" to "评级备注",
)

/** All write effects are owned by the native service; preview does not establish success. */
@Composable
fun SupplierScreen(client: ProductClient) {
    val context = LocalContext.current
    val preferences = remember { context.getSharedPreferences("muyon_product_supplier_v2", 0) }
    var originalIntent by remember { mutableStateOf(preferences.getString("intent_id", null)) }
    var selectedId by remember { mutableStateOf(preferences.getString("supplier_id", null)) }
    var records by remember { mutableStateOf<List<JSONObject>>(emptyList()) }
    var deleted by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf<JSONObject?>(null) }
    var draft by remember { mutableStateOf<Map<String, String>?>(null) }
    var plan by remember { mutableStateOf<JSONObject?>(null) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf("") }
    var receipt by remember { mutableStateOf<JSONObject?>(null) }
    var discard by remember { mutableStateOf(false) }
    var pending by remember { mutableStateOf(false) }
    var submittedPlan by remember { mutableStateOf<String?>(null) }
    var offset by remember { mutableStateOf(0) }
    var loading by remember { mutableStateOf(false) }
    var readGeneration by remember { mutableStateOf(0) }

    fun problem(reply: JSONObject): String = "${reply.optString("status")}: ${reply.optString("error", "operation_unavailable")}" +
        reply.optString("recovery_action").takeIf { it.isNotBlank() }?.let { " · $it" }.orEmpty()

    fun reload() {
        val generation = ++readGeneration
        val requestedOffset = offset
        val requestedDeleted = deleted
        loading = true
        client.call(if (deleted) "deleted_suppliers" else "suppliers", JSONObject().put("limit", 10).put("offset", requestedOffset)) { reply ->
            if (generation != readGeneration) return@call
            val data = reply.optJSONArray("data")
            if (reply.optString("status") == "ok" && data != null) {
                records = (0 until data.length()).map { data.getJSONObject(it) }
                // An in-flight/rejected draft keeps its original revision. Refresh
                // cannot silently rebase stale fields onto somebody else's update.
                val requestedId = selectedId
                if (draft == null && requestedId != null) {
                    client.call("supplier", JSONObject().put("id", requestedId)) { detailReply ->
                        if (generation == readGeneration) {
                            val detail = detailReply.optJSONObject("data")
                            if (draft == null && selectedId == requestedId && detailReply.optString("status") == "ok" && detail != null)
                                selected = detail.takeIf { it.optBoolean("deleted") == requestedDeleted }
                            loading = false
                        }
                    }
                } else loading = false
            } else { message = problem(reply); loading = false }
        }
    }

    fun resolved(reply: JSONObject) {
        busy = false
        val data = reply.optJSONObject("data")
        if (reply.optString("status") != "ok" || data == null) {
            message = problem(reply)
            return
        }
        val status = data.optString("status")
        val nativeReceipt = data.optJSONObject("receipt")
        // Only a matching durable receipt can establish a successful business write.
        if (status == "committed" && nativeReceipt != null && nativeReceipt.optString("intent_id") == originalIntent &&
            nativeReceipt.optString("status") == "committed") {
            receipt = nativeReceipt
            message = "已提交 · 版本 ${nativeReceipt.optString("revision")}"
            draft = null
        } else {
            message = if (status == "not_submitted")
                "核心未接收此确认，原预览已封存；可重新编辑草稿，不会重发原操作" else problem(data)
        }
        pending = status == "pending"
        if ((status == "committed" && receipt === nativeReceipt) || status in listOf("rejected", "cancelled", "not_submitted")) {
            submittedPlan?.let { client.call("discard", JSONObject().put("plan_id", it)) {} }
            submittedPlan = null
            if (preferences.edit().remove("intent_id").commit()) originalIntent = null
            else message += " · 本地恢复标记未清除，请查询原结果"
            pending = false
            reload()
        }
    }

    fun prepare(operation: JSONObject, revision: String) {
        if (busy || originalIntent != null || plan != null) return
        busy = true
        client.call("prepare", JSONObject().put("operation", operation)
            .put("expected_revision", revision)) { reply ->
            busy = false
            val envelope = reply.optJSONObject("data")
            if (reply.optString("status") == "ok" && envelope?.optString("plan_id")?.isNotBlank() == true &&
                envelope.optString("intent_id").isNotBlank()) plan = envelope
            else message = problem(reply)
        }
    }

    fun select(record: JSONObject) {
        selected = record
        selectedId = record.getString("id")
        preferences.edit().putString("supplier_id", selectedId).commit()
    }

    fun closeDraft() {
        if (!busy && plan == null && originalIntent == null) discard = true
    }
    fun closePreview() {
        plan?.let { client.call("discard", JSONObject().put("plan_id", it.getString("plan_id"))) {} }
        plan = null
    }
    BackHandler(enabled = draft != null || plan != null || busy || originalIntent != null) {
        if (plan != null && !busy) closePreview() else closeDraft()
    }
    LaunchedEffect(client, deleted, offset) { reload() }
    DisposableEffect(client) {
        onDispose {
            if (originalIntent == null) plan?.let {
                client.call("discard", JSONObject().put("plan_id", it.getString("plan_id"))) {}
            }
        }
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("供应商", style = MaterialTheme.typography.headlineSmall)
        if (message.isNotEmpty()) Text(message, Modifier.testTag("supplier-status"))
        if (originalIntent != null) {
            Text("有一项原操作待核实；不会重新提交。")
            Text("原操作：$originalIntent")
            Button(enabled = !busy, onClick = {
                busy = true
                client.call("lookup", JSONObject().put("intent_id", originalIntent)) { resolved(it) }
            }, modifier = Modifier.testTag("supplier-lookup")) { Text("查询原结果") }
            if (pending) Button(enabled = !busy, onClick = {
                busy = true
                client.call("cancel", JSONObject().put("intent_id", originalIntent)) { resolved(it) }
            }) { Text("取消原操作") }
        }
        val unlocked = !busy && !loading && originalIntent == null && plan == null
        if (draft == null) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(enabled = unlocked, onClick = {
                    selected = null
                    selectedId = UUID.randomUUID().toString()
                    draft = fields.keys.associateWith { "" }
                }, modifier = Modifier.testTag("supplier-new")) { Text("新增供应商") }
                TextButton(enabled = unlocked, onClick = { loading = true; deleted = !deleted; offset = 0; selected = null }) {
                    Text(if (deleted) "查看在用" else "查看已删除")
                }
            }
            TextButton(enabled = !busy && !loading, onClick = { reload() }) { Text("刷新当前值") }
            Text("供应商偏移：$offset · 本页 ${records.size} 项", Modifier.testTag("supplier-page"))
            Row {
                TextButton(enabled = unlocked && offset > 0, onClick = { loading = true; offset = (offset - 10).coerceAtLeast(0) }, modifier = Modifier.testTag("supplier-previous")) { Text("上一页供应商") }
                TextButton(enabled = unlocked && records.size == 10, onClick = { loading = true; offset += 10 }, modifier = Modifier.testTag("supplier-next")) { Text("下一页供应商") }
            }
            if (records.isEmpty()) Text(if (deleted) "没有已删除供应商" else "暂无供应商")
            records.forEach { record ->
                OutlinedButton(enabled = unlocked, onClick = { select(record) }, modifier = Modifier.fillMaxWidth()) {
                    Text("${record.getJSONObject("payload").optString("name")} · ${record.getString("id")}")
                }
            }
            selected?.let { record ->
                val payload = record.getJSONObject("payload")
                Text("当前值 · ${record.getString("id")} · 版本 ${record.optString("revision")}")
                fields.forEach { (key, label) -> Text("$label：${payload.opt(key)?.takeUnless { it == JSONObject.NULL } ?: ""}") }
                if (!deleted) {
                    Button(enabled = unlocked, onClick = {
                        draft = fields.keys.associateWith { key ->
                            if (key == "aliases" || key == "categories") {
                                val values = payload.optJSONArray(key) ?: JSONArray()
                                (0 until values.length()).joinToString("\n") { values.getString(it) }
                            } else payload.opt(key)?.takeUnless { it == JSONObject.NULL }?.toString().orEmpty()
                        }
                    }, modifier = Modifier.testTag("supplier-edit")) { Text("编辑供应商") }
                }
                OutlinedButton(enabled = unlocked, onClick = {
                    prepare(JSONObject().put("operation", if (deleted) "supplier_restore" else "supplier_delete")
                        .put("supplier_id", record.getString("id")), record.getString("revision"))
                }, modifier = Modifier.testTag(if (deleted) "supplier-restore" else "supplier-delete")) {
                    Text(if (deleted) "恢复（撤销删除）" else "删除供应商")
                }
            }
        } else {
            Text(if (selected == null) "新增草稿" else "编辑草稿")
            fields.forEach { (key, label) ->
                OutlinedTextField(value = draft?.get(key).orEmpty(), onValueChange = { value ->
                    draft = draft.orEmpty() + (key to value)
                }, enabled = unlocked, label = { Text(label) }, modifier = Modifier.fillMaxWidth().testTag("supplier-field-$key"))
            }
            Button(enabled = unlocked, onClick = {
                val values = draft ?: return@Button
                val payload = JSONObject()
                fields.keys.forEach { key ->
                    val value = values.getValue(key)
                    payload.put(key, if (key == "aliases" || key == "categories")
                        JSONArray(value.lines().filter { it.isNotEmpty() })
                    else if (key != "name" && value.isEmpty()) JSONObject.NULL else value)
                }
                payload.put("merged_into", selected?.getJSONObject("payload")?.opt("merged_into") ?: JSONObject.NULL)
                prepare(JSONObject().put("operation", if (selected == null) "supplier_create" else "supplier_update")
                    .put("supplier_id", selectedId).put("payload", payload), selected?.getString("revision") ?: "0")
            }, modifier = Modifier.testTag("supplier-save-preview")) { Text("预览保存") }
            TextButton(enabled = unlocked, onClick = { closeDraft() }) { Text("放弃草稿") }
        }
        receipt?.let {
            HorizontalDivider()
            Text("历史回执（不代表当前值）", style = MaterialTheme.typography.titleSmall)
            Text("${it.optString("intent_id")} · ${it.optString("target_id")} · 版本 ${it.optString("revision")}",
                Modifier.testTag("supplier-receipt"))
        }
    }
    plan?.let { envelope ->
        AlertDialog(onDismissRequest = { if (!busy) closePreview() }, title = { Text("确认供应商操作") },
            text = { Column(Modifier.verticalScroll(rememberScrollState())) {
                Text("请核对完整内容；确认后才会写入。")
                Text(envelope.getJSONObject("command").toString(2), Modifier.testTag("supplier-preview"))
                Text("基于版本 ${envelope.optString("expected_revision")}")
            } }, confirmButton = {
                Button(enabled = !busy, onClick = {
                    if (busy || originalIntent != null) return@Button
                    val intent = envelope.getString("intent_id")
                    if (!preferences.edit().putString("intent_id", intent).putString("supplier_id", selectedId).commit()) {
                        message = "无法保存恢复标记，尚未提交"
                        return@Button
                    }
                    originalIntent = intent
                    submittedPlan = envelope.getString("plan_id")
                    busy = true
                    plan = null
                    client.call("confirm", JSONObject().put("plan_id", envelope.getString("plan_id"))) { resolved(it) }
                }, modifier = Modifier.testTag("supplier-confirm")) { Text("确认写入") }
            }, dismissButton = { TextButton(enabled = !busy, onClick = { closePreview() }) { Text("返回修改") } })
    }
    if (discard) AlertDialog(onDismissRequest = { discard = false }, title = { Text("放弃未保存草稿？") },
        text = { Text("草稿尚未写入供应商库。") }, confirmButton = {
            TextButton(onClick = { draft = null; discard = false }) { Text("放弃") }
        }, dismissButton = { TextButton(onClick = { discard = false }) { Text("继续编辑") } })
}
