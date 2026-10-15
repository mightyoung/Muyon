package com.mightyoung.muyon.androidlab

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.graphics.Color
import kotlinx.coroutines.flow.collect

/** Original adjustable layout. User-created local notes never represent sent requests or results. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MuyonLabShell(
    port: RustUiPort = DisconnectedRustUiPort,
    windowWidthDp: Float? = null,
    initialState: ShellState = ShellState(),
) {
    var shell by remember { mutableStateOf(initialState) }
    var local by remember { mutableStateOf(LocalUiState().updateMemory(initialState.memory(Destination.ASSISTANT))) }
    val layout = navigationLayout(windowWidthDp ?: LocalConfiguration.current.screenWidthDp.toFloat())
    val conversationScrolls = remember { mutableMapOf<Int, LazyListState>() }
    val conversation = local.active
    val assistantScroll = conversationScrolls.getOrPut(conversation.id) {
        LazyListState(conversation.memory.firstVisibleItemIndex, conversation.memory.firstVisibleItemOffset)
    }
    val taskScroll = rememberLazyListState()
    val dataScroll = rememberLazyListState()
    val settingsScroll = rememberLazyListState()
    val draftFocus = remember { FocusRequester() }
    var draftMounted by remember { mutableStateOf(false) }
    val focusManager = LocalFocusManager.current
    val availability = remember(port) { port.availability() }
    val systemDark = isSystemInDarkTheme()
    val dark = when (local.theme) { LabTheme.SYSTEM -> systemDark; LabTheme.DARK -> true; LabTheme.LIGHT -> false }
    val colors = if (dark) darkColorScheme(primary = Color.White, onPrimary = Color.Black)
        else lightColorScheme(primary = Color.Black, onPrimary = Color.White)

    LaunchedEffect(conversation.id, assistantScroll) {
        val id = conversation.id
        snapshotFlow { assistantScroll.firstVisibleItemIndex to assistantScroll.firstVisibleItemScrollOffset }
            .collect { (index, offset) ->
                val memory = local.conversations.firstOrNull { it.id == id }?.memory
                if (memory != null) local = local.storeMemory(id, memory.copy(firstVisibleItemIndex = index, firstVisibleItemOffset = offset))
            }
    }
    LaunchedEffect(shell.selected, conversation.id, draftMounted, local.overlay) {
        if (shell.selected == Destination.ASSISTANT && draftMounted && local.overlay == null && local.active.memory.focus == FocusSlot.DRAFT) draftFocus.requestFocus()
    }
    fun select(destination: Destination) { focusManager.clearFocus(); shell = shell.select(destination); local = local.copy(overlay = null) }
    fun show(overlay: LocalOverlay) { focusManager.clearFocus(); local = local.copy(overlay = overlay) }

    MaterialTheme(colorScheme = colors) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("Muyon · ${shell.selected.label}") },
                    actions = {
                        if (shell.selected == Destination.ASSISTANT) {
                            TextButton(onClick = { show(LocalOverlay.History) }, modifier = Modifier.testTag("open-history")) { Text("会话") }
                            TextButton(onClick = { local = local.createConversation() }, modifier = Modifier.testTag("new-conversation")) { Text("新建") }
                        }
                    },
                )
            },
            bottomBar = {
                if (layout == NavigationLayout.BOTTOM_BAR) NavigationBar(Modifier.testTag("bottom-nav")) {
                    Destination.entries.forEach { destination ->
                        NavigationBarItem(selected = shell.selected == destination, onClick = { select(destination) },
                            icon = { Text(destination.label.take(1)) }, label = { Text(destination.label) },
                            modifier = Modifier.testTag("destination-${destination.name}"))
                    }
                }
            },
        ) { padding ->
            Row(Modifier.fillMaxSize().padding(padding)) {
                if (layout == NavigationLayout.RAIL) NavigationRail(Modifier.testTag("rail")) {
                    Destination.entries.forEach { destination ->
                        NavigationRailItem(selected = shell.selected == destination, onClick = { select(destination) },
                            icon = { Text(destination.label.take(1)) }, label = { Text(destination.label) },
                            modifier = Modifier.testTag("destination-${destination.name}"))
                    }
                }
                Box(Modifier.weight(1f).fillMaxSize()) {
                    when (shell.selected) {
                        Destination.ASSISTANT -> AssistantLocalPage(
                            local, assistantScroll, draftFocus,
                            onMemory = { memory -> local = local.storeMemory(conversation.id, memory) },
                            onMounted = { draftMounted = it },
                            onSave = { local = local.saveLocalNote() },
                            onOptions = { show(LocalOverlay.Capabilities) },
                            onNote = { id -> local = local.openNote(conversation.id, id) },
                            availability = availability,
                        )
                        Destination.TASKS -> TasksLocalPage(local.taskFilter, taskScroll,
                            onFilter = { local = local.copy(taskFilter = it) }, onOptions = { show(LocalOverlay.Capabilities) })
                        Destination.DATA -> RecordsLocalPage(local, dataScroll,
                            onQuery = { local = local.copy(recordQuery = it) },
                            onNote = { ref -> local = local.openNote(ref.conversationId, ref.note.id) })
                        Destination.SETTINGS -> SettingsLocalPage(local, settingsScroll,
                            onTheme = { local = local.copy(theme = it) }, onOptions = { show(LocalOverlay.Capabilities) })
                    }
                }
            }
        }
        LocalOverlays(
            local,
            onDismiss = { local = local.copy(overlay = null) },
            onHistoryQuery = { local = local.copy(historyQuery = it) },
            onCreate = { local = local.createConversation(); shell = shell.select(Destination.ASSISTANT) },
            onSelect = { local = local.selectConversation(it); shell = shell.select(Destination.ASSISTANT) },
            onRename = { local = local.openRename(it) },
            onRenameDraft = { local = local.renameDraft(it) },
            onConfirmRename = { local = local.confirmRename() },
            onOpenConversation = { local = local.openInspectedConversation(); shell = shell.select(Destination.ASSISTANT) },
        )
    }
}
