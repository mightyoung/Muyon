package muyon.rd.p08.android

// SOURCE ONLY: Android/Compose dependencies and native host composition are absent.
// This page is deliberately excluded from run-jvm-tests.sh. No native build/render claim.
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp

/** Inject an existing model and its trusted host port. This function never creates a transport,
 * intent, plan, candidate, grant or receipt. Port callbacks must arrive on the Android UI thread. */
@Composable
fun SupplierPage(model: SupplierScreenModel) {
    var renderVersion by remember(model) { mutableIntStateOf(0) }
    DisposableEffect(model) {
        model.onChanged = { renderVersion++ }
        onDispose { model.onChanged = {} }
    }
    val page = remember(model, renderVersion) { model.page }
    BackHandler(enabled = page != ScreenPage.LIST) { model.back() }
    // One scroll surface with in-flow buttons: large fonts and IME need no fixed footer.
    Column(
        Modifier.fillMaxSize().safeDrawingPadding().imePadding()
            .verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("RD-P08 合成供应商实验 · Android 源码", style = MaterialTheme.typography.labelLarge)
        Text("原生编译/运行未验证；M03 blocked_contract", style = MaterialTheme.typography.bodySmall)
        Text(model.projection.capability)
        if (page != ScreenPage.LIST) Action("返回", enabled = !model.busy, action = model::back)
        when (page) {
            ScreenPage.LIST -> SupplierList(model)
            ScreenPage.DETAIL -> SupplierDetail(model)
            ScreenPage.EDITOR -> SupplierEditor(model)
        }
        model.transportMessage?.let { Text(it, Modifier.semantics { liveRegion = LiveRegionMode.Polite }) }
        if (model.busy) Text("正在等待主机响应；尚不能据此认定保存成功。")
        Action("刷新当前主机投影", enabled = !model.busy, action = model::refresh)
        if (model.projection.recoverable_sessions.isNotEmpty()) {
            Heading("恢复原实验会话")
            Text("选择原会话并只读恢复；结果未知时继续核对原操作。未同步输入须先刷新同步或显式放弃，才能切换会话。")
            model.projection.recoverable_sessions.forEach { recoverable ->
                key(recoverable.session) {
                    Action(
                        "恢复 ${recoverable.session} · 对象 ${recoverable.supplier ?: "未选择"} · ${recoverable.status ?: "无编辑"}",
                        enabled = model.canRestoreSession
                    ) { model.restoreOriginalSession(recoverable.session) }
                }
            }
        }
        Spacer(Modifier.height(16.dp))
    }
    if (model.discardConfirmation) {
        AlertDialog(
            onDismissRequest = model::keepEditing,
            title = { Text("放弃未保存的名称草稿？") },
            text = { Text("将请求主机丢弃此编辑缓冲；当前供应商的保存值不会因此改名。确认前保留原输入。") },
            confirmButton = { TextButton(onClick = model::confirmDiscard, enabled = model.canCancel) { Text("放弃草稿") } },
            dismissButton = { TextButton(onClick = model::keepEditing) { Text("继续编辑") } }
        )
    }
}

@Composable
private fun SupplierList(model: SupplierScreenModel) {
    Column(Modifier.testTag("D01.1-LIST"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Heading("供应商目录")
        Text("固定合成 S1/S2；列表来自分别读取，非原子快照。")
        when (model.projection.list_status) {
            "partial" -> Text("列表部分不可用；仅展示主机实际读取的记录。")
            "unavailable" -> Text("列表当前不可用，请刷新。")
        }
        model.projection.suppliers.forEach { row ->
            key(row.supplier) {
                Action("${row.name}\n供应商 ID ${row.supplier} · 版本 ${row.revision}", enabled = !model.busy) {
                    model.select(row.supplier)
                }
            }
        }
        model.projection.editor?.let { original ->
            Action("查看原编辑/结果：${original.supplier}", enabled = !model.busy, action = model::openOriginalEditor)
        }
    }
}

@Composable
private fun SupplierDetail(model: SupplierScreenModel) {
    Column(Modifier.testTag("D01.1-DETAIL"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Heading("供应商详情")
        model.projection.selected?.let { RowText("当前保存值", it) } ?: Text("当前对象读取不可用。")
        Action("编辑名称", enabled = model.canEdit, action = model::edit)
        model.projection.editor?.let { original ->
            Text("原编辑属于 ${original.supplier}；选择另一对象不会替换原意图。")
            Status(model)
            Action("打开原编辑/核对结果", enabled = !model.busy, action = model::openOriginalEditor)
        }
    }
}

@Composable
private fun SupplierEditor(model: SupplierScreenModel) {
    val editor = model.projection.editor ?: return
    Column(Modifier.testTag("D01.1-NAME-EDITOR"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Heading("修改供应商名称")
        Text("供应商 ID ${editor.supplier} · 原预期版本 ${editor.expected_revision}")
        Text("原意图 ${editor.intent}")
        editor.current?.let { RowText("当前保存值（单独读取）", it) } ?: Text("当前保存值不可用；不以旧回执补成当前值。")
        Status(model)
        editor.reason?.let { Text("主机原因：$it") }
        OutlinedTextField(
            value = model.buffer,
            onValueChange = model::changeRaw,
            modifier = Modifier.fillMaxWidth(),
            enabled = model.canChangeRaw,
            label = { Text("我的修改（原始输入）") },
            supportingText = { Text("原样交给主机/Rust；预览与保存分开。") },
            minLines = 3
        )
        editor.preview?.let { preview ->
            Column(Modifier.testTag("D01.1-DIFF"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Heading("Rust 校验预览")
                Text("当前保存值：${editor.current?.name ?: "不可用"}")
                Text("规范后候选：${preview.normalized_name}")
                Text("候选版本：${preview.candidate_revision}；实验绑定由主机分配，非正式授权。")
            }
        }
        if (editor.status == "conflict") Text("原输入和原预期版本已保留。取消此已核实的冲突后，可显式从当前保存值重新编辑。")
        if (model.canLookup || editor.status in setOf("saving", "unknown")) {
            Text("结果未知不代表失败；只核对原操作，不创建替代意图或重发保存。")
            Action("核对原回执", enabled = model.canLookup, action = model::lookup)
        } else {
            if (model.canPreview && editor.status == "unavailable") {
                Text("此预览尚未派发保存；保留原草稿，可重试预览或显式放弃。")
            }
            Action(if (editor.status == "unavailable" && model.canPreview) "重试预览" else "预览修改", enabled = model.canPreview, action = model::preview)
            Action("保存名称", enabled = model.canSave, action = model::save)
        }
        Action(if (model.saved) "结束本次编辑" else "取消编辑", enabled = model.canCancel, action = model::requestCancel)
        model.originalReceipt?.let { receipt ->
            Column(Modifier.testTag("D01.1-RECEIPT"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Heading("原提交回执（历史效果）")
                Text("由实验主机提供 P07 核实结果；当前保存值独立显示。")
                SelectionContainer {
                    Text(
                        "intent: ${receipt.intent}\nsource: ${receipt.source}\nsupplier: ${receipt.supplier}\n" +
                            "old_name: ${receipt.old_name}\nnew_name: ${receipt.new_name}\n" +
                            "old_revision: ${receipt.old_revision}\nnew_revision: ${receipt.new_revision}\n" +
                            "binding_sha256: ${receipt.binding_sha256}\n" +
                            "binding.domain: ${receipt.binding.domain}\nbinding.scope: ${receipt.binding.scope}\n" +
                            "binding.supplier: ${receipt.binding.supplier}\nbinding.intent: ${receipt.binding.intent}\n" +
                            "binding.operation: ${receipt.binding.operation}\n" +
                            "binding.raw_utf16: ${receipt.binding.raw_utf16}\n" +
                            "binding.expected_revision: ${receipt.binding.expected_revision}\n" +
                            "binding.plan: ${receipt.binding.plan}\nbinding.candidate: ${receipt.binding.candidate}"
                    )
                }
            }
        }
    }
}

@Composable
private fun Status(model: SupplierScreenModel) {
    Text(model.statusText, Modifier.semantics {
        stateDescription = model.statusText
        liveRegion = LiveRegionMode.Polite
    })
}

@Composable
private fun Heading(label: String) {
    Text(label, Modifier.semantics { heading() }, style = MaterialTheme.typography.titleLarge)
}

@Composable
private fun RowText(label: String, row: SupplierRow) {
    Text("$label：${row.name}\n供应商 ID ${row.supplier} · 版本 ${row.revision}")
}

@Composable
private fun Action(label: String, enabled: Boolean, action: () -> Unit) {
    Button(onClick = action, enabled = enabled, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text(label) }
}
