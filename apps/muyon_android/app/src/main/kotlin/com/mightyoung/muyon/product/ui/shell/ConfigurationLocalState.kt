package com.mightyoung.muyon.product.ui.shell

import androidx.compose.runtime.*
import androidx.lifecycle.ViewModel

fun configurationBufferScope(workspace: String, conversation: String, project: String?): String {
    require(workspace.isNotBlank() && conversation.isNotBlank())
    return "workspace:${workspace.length}:$workspace:conversation:${conversation.length}:$conversation:project:${project?.length ?: -1}:${project.orEmpty()}"
}

/** Only unsent UI text buffers. Host is the sole reducer and owns every flow transition. */
class ConfigurationPreviewState(val scope: String) {
    var panel by mutableStateOf("")
    var name by mutableStateOf("")
    var purpose by mutableStateOf("")
    var role by mutableStateOf("")
    var groupMode by mutableStateOf<String?>(null)
    var coordinator by mutableStateOf("")
    var recovery by mutableStateOf<HostSetupSnapshot?>(null)
    var draftEpoch by mutableIntStateOf(0)
    var controller by mutableStateOf<HostSetupController?>(null)
    var hostSnapshot by mutableStateOf<HostSetupSnapshot?>(null)
    var hostBusy by mutableStateOf(false)
    var hostNeedsRead by mutableStateOf(false)
    var hostNotice by mutableStateOf("")
    fun observeHost(value: HostSetupController) {
        val old = hostSnapshot
        val next = value.snapshot
        if (next != null && next != old) {
            // A late host response may update only buffers with no unsent manual edit.
            if ((old != null && name == old.name) || (old == null && name.isEmpty())) name = next.name
            if ((old != null && purpose == old.purpose) || (old == null && purpose.isEmpty())) purpose = next.purpose
            if ((old != null && role == old.role) || (old == null && role.isEmpty())) role = next.role
        }
        if (next != null) recovery = next
        hostSnapshot = next; hostBusy = value.busy; hostNeedsRead = value.needsRead; hostNotice = value.notice
    }
}

/** Retains the same buffers across tabs and rotation, never claims process persistence. */
class ShellConfigurationState : ViewModel() {
    private val scopes = mutableMapOf<String, ConfigurationPreviewState>()
    fun forScope(scope: String): ConfigurationPreviewState = scopes.getOrPut(scope) { ConfigurationPreviewState(scope) }
}
