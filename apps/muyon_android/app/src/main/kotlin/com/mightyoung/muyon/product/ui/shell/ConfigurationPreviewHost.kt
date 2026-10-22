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
import androidx.lifecycle.ViewModel
import com.mightyoung.muyon.product.agents.setup.BotSetupDraft
import com.mightyoung.muyon.product.ui.configuration.*

/** Activity ViewModel retains local buffers across navigation/rotation, never dispatches. */
class ShellConfigurationState : ViewModel() {
    private val scopes = mutableMapOf<String, ConfigurationPreviewState>()
    fun forScope(scope: String): ConfigurationPreviewState = scopes.getOrPut(scope) {
        ConfigurationPreviewState(BotConfigurationEditor(BotSetupDraft(scope)))
    }
}

class ConfigurationPreviewState(val editor: BotConfigurationEditor) {
    var panel by mutableStateOf("")
    var groupMode by mutableStateOf<String?>(null)
    var coordinator by mutableStateOf("")
}

/** The scope labels local preview buffers only; no trusted account/group snapshot is available. */
@Composable
fun ConfigurationPreviewHost(state: ConfigurationPreviewState, onLeave: () -> Unit) {
    val keyboard = LocalSoftwareKeyboardController.current
    val focus = LocalFocusManager.current
    val imeVisible = WindowInsets.ime.getBottom(LocalDensity.current) > 0
    when (state.panel) {
        "bot" -> BotConfigurationScreen(state.editor, state.editor.draft.snapshot(),
            onLeaveWithDraft = { state.panel = "" })
        "group" -> GroupConfigurationScreen(
            GroupGovernanceDisplay(null, null, null, null, null, null, emptyList()),
            state.groupMode, { mode ->
                state.groupMode = mode
                if (mode != "fixed") state.coordinator = ""
            }, state.coordinator, { state.coordinator = it }, onLeaveWithDraft = { state.panel = "" })
        else -> Column(Modifier.fillMaxSize().padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("配置预览", style = MaterialTheme.typography.headlineSmall)
            Text("仅本机内存草稿，未接入保存、创建或运行。进程退出后不能恢复；不读取或改变现有智能体。")
            Button(onClick = { state.panel = "bot" }, modifier = Modifier.heightIn(min = 48.dp)) { Text("Bot 配置预览") }
            Button(onClick = { state.panel = "group" }, modifier = Modifier.heightIn(min = 48.dp)) { Text("群组配置预览") }
            TextButton(onClick = onLeave, modifier = Modifier.heightIn(min = 48.dp)) { Text("返回目录") }
        }
    }
    // Registered after child handlers: an open IME consumes the first Back.
    // Otherwise the Bot editor owns its step transition; group/chooser return locally.
    BackHandler(enabled = imeVisible || state.panel != "bot") {
        if (imeVisible) { keyboard?.hide(); focus.clearFocus() }
        else if (state.panel.isNotEmpty()) state.panel = ""
        else onLeave()
    }
}
