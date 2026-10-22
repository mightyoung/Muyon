package com.mightyoung.muyon.product.ui.shell

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/** Text buffers are unsent until explicitly applied to the displayed host revision. */
@Composable
fun HostSetupScreen(state: ConfigurationPreviewState, onLeave: () -> Unit) {
    val displayed = state.hostSnapshot
    val controller = state.controller
    val available = controller != null && displayed != null && !state.hostBusy && !state.hostNeedsRead
    fun allowed(action: String) = available && action in displayed!!.operations
    Column(Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Bot 草稿", style = MaterialTheme.typography.headlineSmall)
        Text("文本缓冲与宿主草稿分开。未提交文本只保留在本机内存；保存、恢复与原保存结果核查当前不可用。未创建智能体、未启动任务。")
        if (state.hostNotice.isNotEmpty()) Text(state.hostNotice, color = MaterialTheme.colorScheme.error)
        if (state.hostBusy) Text("正在核对本地内存状态…")
        if (displayed == null) {
            Text("宿主草稿尚不可用。可保留未提交的名称文本，不能推进步骤。")
            OutlinedTextField(state.name, { state.name = it }, label = { Text("名称") }, modifier = Modifier.fillMaxWidth())
        } else {
            Text("步骤 ${displayed.step} · 内存修订 ${displayed.revision}")
            hostPersistenceMessages(displayed, state.name, state.purpose, state.role).forEach { Text(it) }
            if (displayed.cancelled) {
                Text("已停止编辑此内存草稿；尚未创建或执行任何任务。")
                Button(onClick = { controller?.mutate(displayed, "resume") }, enabled = allowed("resume")) { Text("恢复原内存草稿") }
            } else when (displayed.step) {
                "NAME" -> {
                    OutlinedTextField(state.name, { state.name = it }, label = { Text("名称") }, modifier = Modifier.fillMaxWidth())
                    Button(onClick = { controller?.mutate(displayed, "edit_name", state.name) },
                        enabled = allowed("edit_name") && state.name != displayed.name) { Text("确认名称到内存") }
                }
                "PURPOSE" -> {
                    OutlinedTextField(state.purpose, { state.purpose = it }, label = { Text("用途") }, modifier = Modifier.fillMaxWidth())
                    Button(onClick = { controller?.mutate(displayed, "edit_purpose", state.purpose) },
                        enabled = allowed("edit_purpose") && state.purpose != displayed.purpose) { Text("确认用途到内存") }
                }
                "CONFIGURATION" -> {
                    OutlinedTextField(state.role, { state.role = it }, label = { Text("角色") }, modifier = Modifier.fillMaxWidth())
                    Button(onClick = { controller?.mutate(displayed, "edit_role", state.role) },
                        enabled = allowed("edit_role") && state.role != displayed.role) { Text("确认角色到内存") }
                    Button(onClick = { controller?.mutate(displayed, "suggest_role") }, enabled = allowed("suggest_role")) { Text("查看本地角色模板") }
                    displayed.suggestion?.let { suggestion ->
                        Text("${suggestion.label} · v${suggestion.sourceVersion}\n${suggestion.role}")
                        Button(onClick = { controller?.mutate(displayed, "accept_role", suggestionToken = suggestion.requestId) },
                            enabled = available && canAcceptHostSuggestion(displayed, state.role)) { Text("采用此模板到内存") }
                        if (state.role != displayed.role) Text("存在未提交的手工角色，请先核对；模板不会覆盖该文本。")
                    }
                    Text("能力、材料与费用信息尚不可用；未授予权限。")
                }
                "REVIEW" -> {
                    Text("名称：${displayed.name}\n用途：${displayed.purpose}\n角色：${displayed.role}")
                    Text("能力与材料元数据尚不可用，不能创建或运行。")
                }
            }
            val buffersMatch = when (displayed.step) {
                "NAME" -> state.name == displayed.name
                "PURPOSE" -> state.purpose == displayed.purpose
                "CONFIGURATION" -> state.role == displayed.role
                else -> state.name == displayed.name && state.purpose == displayed.purpose && state.role == displayed.role
            }
            if (!buffersMatch) Text("有未提交文本；下一步需先将当前文本确认到内存。")
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                TextButton(onClick = { controller?.mutate(displayed, "back") }, enabled = allowed("back")) { Text("上一步") }
                Button(onClick = { controller?.mutate(displayed, "next") }, enabled = allowed("next") && buffersMatch) { Text("下一步") }
            }
            TextButton(onClick = { controller?.mutate(displayed, "cancel") }, enabled = allowed("cancel")) { Text("停止编辑此内存草稿") }
            TextButton(onClick = { controller?.readOriginal() }, enabled = controller != null && !state.hostBusy) { Text("读取原内存草稿") }
        }
        if (state.recovery != null && state.hostNeedsRead && !state.hostBusy) {
            TextButton(onClick = {
                controller?.close(); state.recovery = null; state.hostSnapshot = null; state.hostNeedsRead = false; state.draftEpoch++
            }) { Text("放弃本页恢复绑定，重新打开宿主草稿（保留文本）") }
        }
        Button(onClick = {}, enabled = false) { Text("持久保存 · 尚不可用") }
        Button(onClick = {}, enabled = false) { Text("恢复存储草稿 · 尚不可用") }
        Button(onClick = {}, enabled = false) { Text("核查原保存结果 · 尚不可用") }
        Button(onClick = {}, enabled = false) { Text("创建并启动 · 尚不可用") }
        TextButton(onClick = onLeave) { Text("稍后配置 · 保留内存草稿") }
    }
}
