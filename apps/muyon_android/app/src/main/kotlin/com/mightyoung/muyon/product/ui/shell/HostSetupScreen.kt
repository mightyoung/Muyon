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
        Text("输入内容仅在本次运行中保留。请应用当前修改后再继续；持久保存与恢复尚不可用，也不会创建智能体或启动任务。")
        if (state.hostNotice.isNotEmpty()) Text(state.hostNotice, color = MaterialTheme.colorScheme.error)
        if (state.hostBusy) Text("正在核对当前草稿…")
        if (displayed == null) {
            Text("当前草稿尚未就绪。输入仍在本页保留，暂不能进入下一步。")
            OutlinedTextField(state.name, { state.name = it }, label = { Text("名称") }, modifier = Modifier.fillMaxWidth())
        } else {
            Text(when (displayed.step) {
                "NAME" -> "第 1 步 · 名称"
                "PURPOSE" -> "第 2 步 · 用途"
                "CONFIGURATION" -> "第 3 步 · 角色与资料"
                "REVIEW" -> "第 4 步 · 检查草稿"
                else -> "草稿步骤暂不可用"
            }, style = MaterialTheme.typography.titleMedium)
            hostPersistenceMessages(displayed, state.name, state.purpose, state.role).forEach { Text(it) }
            if (displayed.cancelled) {
                Text("已停止编辑此内存草稿；尚未创建或执行任何任务。")
                Button(onClick = { controller?.mutate(displayed, "resume") }, enabled = allowed("resume")) { Text("恢复原内存草稿") }
            } else when (displayed.step) {
                "NAME" -> {
                    OutlinedTextField(state.name, { state.name = it }, label = { Text("名称") }, modifier = Modifier.fillMaxWidth())
                    Button(onClick = { controller?.mutate(displayed, "edit_name", state.name) },
                        enabled = allowed("edit_name") && state.name != displayed.name) { Text("应用名称到当前草稿") }
                }
                "PURPOSE" -> {
                    OutlinedTextField(state.purpose, { state.purpose = it }, label = { Text("用途") }, modifier = Modifier.fillMaxWidth())
                    Button(onClick = { controller?.mutate(displayed, "edit_purpose", state.purpose) },
                        enabled = allowed("edit_purpose") && state.purpose != displayed.purpose) { Text("应用用途到当前草稿") }
                }
                "CONFIGURATION" -> {
                    OutlinedTextField(state.role, { state.role = it }, label = { Text("角色") }, modifier = Modifier.fillMaxWidth())
                    Button(onClick = { controller?.mutate(displayed, "edit_role", state.role) },
                        enabled = allowed("edit_role") && state.role != displayed.role) { Text("应用角色到当前草稿") }
                    Button(onClick = { controller?.mutate(displayed, "suggest_role") }, enabled = allowed("suggest_role")) { Text("查看本地角色模板") }
                    displayed.suggestion?.let { suggestion ->
                        Text("${suggestion.label} · v${suggestion.sourceVersion}\n${suggestion.role}")
                        Button(onClick = { controller?.mutate(displayed, "accept_role", suggestionToken = suggestion.requestId) },
                            enabled = available && canAcceptHostSuggestion(displayed, state.role)) { Text("采用模板到当前草稿") }
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
            if (!buffersMatch) Text("当前修改尚未应用。请先应用到草稿，再继续下一步。")
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
