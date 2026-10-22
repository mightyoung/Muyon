package com.mightyoung.muyon.product.ui.shell

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.unit.dp
import com.mightyoung.muyon.product.agentipc.ProductClient
import com.mightyoung.muyon.product.ui.configuration.GroupConfigurationScreen
import com.mightyoung.muyon.product.ui.configuration.GroupGovernanceDisplay
import org.json.JSONObject

/** A mounted view owns its controller; ViewModel retains text, never a live session handle. */
@Composable
fun ConfigurationPreviewHost(state: ConfigurationPreviewState, client: ProductClient? = null,
    workspace: String? = null, conversation: String? = null, project: String? = null, onLeave: () -> Unit) {
    val keyboard = LocalSoftwareKeyboardController.current
    val focus = LocalFocusManager.current
    val imeVisible = WindowInsets.ime.getBottom(LocalDensity.current) > 0
    val bot = state.panel == "bot"
    DisposableEffect(state, client, workspace, conversation, project, bot, state.draftEpoch) {
        var mounted = true
        var owned: HostSetupController? = null
        state.controller = null; state.hostSnapshot = state.recovery
        state.hostBusy = false; state.hostNeedsRead = state.recovery != null; state.hostNotice = ""
        if (bot && client != null && !workspace.isNullOrBlank() && !conversation.isNullOrBlank()) {
            state.hostBusy = true
            client.call("chat_scope", JSONObject().put("conversation_id", conversation).put("project_id", project ?: JSONObject.NULL)) { reply ->
                if (mounted) {
                    val generation = when (val value = reply.optJSONObject("data")?.opt("scope_generation")) {
                        is Int -> value.toLong().takeIf { it >= 0 }; is Long -> value.takeIf { it >= 0 }; else -> null
                    }
                    if (reply.opt("status") != "ok" || generation == null) {
                        state.hostBusy = false; state.hostNotice = "宿主范围不可用，文本尚未提交。"
                    } else {
                        val currentScope = HostSetupScope(workspace, conversation, project, generation)
                        val recovery = state.recovery
                        if (recovery != null && recovery.scope != currentScope) {
                            state.hostBusy = false; state.hostNeedsRead = true
                            state.hostNotice = "原内存草稿所属宿主会话或范围已失效，不能恢复；原身份和未提交文本保留。不会自动替换成新草稿。"
                            return@call
                        }
                        val controller = HostSetupController(currentScope,
                            { method, payload, callback -> client.call(method, payload, callback) }, {
                                owned?.let { if (mounted && state.controller === it) state.observeHost(it) }
                            }, recovery)
                        owned = controller; state.controller = controller
                        if (recovery == null) controller.open() else controller.readOriginal()
                    }
                }
            }
        }
        onDispose {
            mounted = false; owned?.close()
            if (state.controller === owned) {
                state.controller = null; state.hostBusy = false; state.hostNeedsRead = state.recovery != null
            }
        }
    }
    when (state.panel) {
        "bot" -> HostSetupScreen(state) { state.panel = "" }
        "group" -> GroupConfigurationScreen(
            GroupGovernanceDisplay(null, null, null, null, null, null, emptyList()),
            state.groupMode, { mode -> state.groupMode = mode; if (mode != "fixed") state.coordinator = "" },
            state.coordinator, { state.coordinator = it }, onLeaveWithDraft = { state.panel = "" })
        else -> Column(Modifier.fillMaxSize().padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("配置草稿", style = MaterialTheme.typography.headlineSmall)
            Text("Bot 步骤由当前宿主内存草稿核实。未持久保存，未接入创建或运行；群组仅展示不可执行的配置预览。")
            Button(onClick = { state.panel = "bot" }) { Text("Bot 配置预览") }
            Button(onClick = { state.panel = "group" }) { Text("群组配置预览") }
            TextButton(onClick = onLeave) { Text("返回目录") }
        }
    }
    BackHandler {
        if (imeVisible) { keyboard?.hide(); focus.clearFocus() }
        else {
            val shown = state.hostSnapshot
            val controller = state.controller
            if (bot && shown != null && "back" in shown.operations && !state.hostBusy && !state.hostNeedsRead)
                controller?.mutate(shown, "back")
            else if (state.panel.isNotEmpty()) state.panel = ""
            else onLeave()
        }
    }
}
