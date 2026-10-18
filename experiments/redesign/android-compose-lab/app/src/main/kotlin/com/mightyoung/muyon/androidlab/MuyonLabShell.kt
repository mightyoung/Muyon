package com.mightyoung.muyon.androidlab

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.activity.ComponentActivity
import androidx.lifecycle.ViewModelProvider
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Alignment
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.res.painterResource
import com.mightyoung.muyon.androidlab.conversation.ConversationPage
import com.mightyoung.muyon.androidlab.conversation.ConversationDrawer
import com.mightyoung.muyon.androidlab.conversation.ChatGlyph
import com.mightyoung.muyon.androidlab.conversation.ChatGlyphKind
import com.mightyoung.muyon.androidlab.conversation.ConversationUiMemory
import kotlinx.coroutines.launch
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.graphics.Color
import kotlinx.coroutines.flow.collect
import com.mightyoung.muyon.androidlab.agentipc.AgentRuntimePanel

/** Original adjustable layout. User-created local notes never represent sent requests or results. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MuyonLabShell(
    port: RustUiPort = DisconnectedRustUiPort,
    windowWidthDp: Float? = null,
    initialState: ShellState = ShellState(),
    diagnostics: RustDiagnosticCoordinator? = null,
) {
    val diagnosticCoordinator = diagnostics ?: (LocalContext.current.applicationContext as MuyonLabApplication).diagnostics
    var diagnosticOpen by remember { mutableStateOf(false) }
    var agentOpen by remember { mutableStateOf(false) }
    var selectedName by rememberSaveable { mutableStateOf(initialState.selected.name) }
    val shell = initialState.select(Destination.valueOf(selectedName))
    val activity = checkNotNull(LocalActivity.current as? ComponentActivity)
    val retained = remember(activity) { ViewModelProvider(activity)[ConversationUiMemory::class.java] }
    val uiSaver = remember(retained) { Saver<ConversationUiMemory, ArrayList<String>>(
        save = {
            ArrayList(it.state.platformConversationSnapshot())
        },
        restore = { snapshot -> retained.apply {
            if (!initialized) {
                state = restoreConversationSnapshot(snapshot) ?: LocalUiState()
                initialized = true
                if (snapshot.firstOrNull() == CONVERSATION_SNAPSHOT_TOO_LARGE) restorationNotice = "上次内容超过系统恢复上限，未恢复。长记录仅在当前进程内保留。"
            }
        } },
    ) }
    val memory = rememberSaveable(saver = uiSaver) { retained.apply {
        if (!initialized) { state = LocalUiState().updateMemory(initialState.memory(Destination.ASSISTANT)); initialized = true }
    } }
    var local by memory.observableState
    var sample by rememberSaveable { mutableStateOf(false) }
    val drawer = rememberDrawerState(DrawerValue.Closed)
    val scope = rememberCoroutineScope()
    val width = windowWidthDp ?: LocalConfiguration.current.screenWidthDp.toFloat()
    val layout = navigationLayout(windowWidthDp ?: LocalConfiguration.current.screenWidthDp.toFloat())
    val conversationScrolls = remember { mutableMapOf<Int, LazyListState>() }
    val conversation = local.active
    val inputActions = localInputActions(conversation.id, readState = { local }, writeState = { local = it })
    val assistantScroll = conversationScrolls.getOrPut(conversation.id) {
        LazyListState(conversation.memory.firstVisibleItemIndex, conversation.memory.firstVisibleItemOffset)
    }
    val fixtureScroll = rememberLazyListState()
    val taskScroll = rememberLazyListState()
    val dataScroll = rememberLazyListState()
    val settingsScroll = rememberLazyListState()
    val draftFocus = remember { FocusRequester() }
    var draftMounted by remember { mutableStateOf(false) }
    val focusManager = LocalFocusManager.current
    val availability = remember(port) { port.availability() }
    val systemDark = isSystemInDarkTheme()
    val dark = when (local.theme) { LabTheme.SYSTEM -> systemDark; LabTheme.DARK -> true; LabTheme.LIGHT -> false }
    val colors = if (dark) darkColorScheme(primary = Color.White, onPrimary = Color.Black,
        surface = Color(0xFF171717), background = Color(0xFF171717), onSurface = Color(0xFFF2F2F0),
        surfaceContainerLow = Color(0xFF202020), surfaceContainer = Color(0xFF262626),
        surfaceContainerHigh = Color(0xFF303030), surfaceContainerHighest = Color(0xFF383838),
        onSurfaceVariant = Color(0xFFB9B9B4), outlineVariant = Color(0xFF42423F))
        else lightColorScheme(primary = Color(0xFF20201E), onPrimary = Color.White,
            surface = Color(0xFFFCFCFB), background = Color(0xFFFCFCFB), onSurface = Color(0xFF20201E),
            surfaceContainerLow = Color(0xFFF5F5F2), surfaceContainer = Color(0xFFF0F0ED),
            surfaceContainerHigh = Color(0xFFEAEAE6), surfaceContainerHighest = Color(0xFFE3E3DF),
            onSurfaceVariant = Color(0xFF64645E), outlineVariant = Color(0xFFDDDDD7))

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
    fun select(destination: Destination) { diagnosticOpen = false; agentOpen = false; focusManager.clearFocus(); selectedName = destination.name; local = local.copy(overlay = null); scope.launch { drawer.close() } }
    fun show(overlay: LocalOverlay) { focusManager.clearFocus(); local = local.copy(overlay = overlay) }
    fun closeHistory() { scope.launch { drawer.close() } }
    fun openHistory() { focusManager.clearFocus(); local = local.copy(overlay = null); scope.launch { drawer.open() } }
    BackHandler(enabled = drawer.isOpen) { closeHistory() }

    MaterialTheme(colorScheme = colors) {
        ModalNavigationDrawer(
            drawerState = drawer,
            gesturesEnabled = shell.selected == Destination.ASSISTANT && local.overlay == null,
            drawerContent = {
                ConversationDrawer(local, width,
                    onClose = ::closeHistory,
                    onCreate = { local = local.createConversation(); sample = false; select(Destination.ASSISTANT) },
                    onQuery = { local = local.copy(historyQuery = it) },
                    onSelect = { local = local.selectConversation(it); sample = false; select(Destination.ASSISTANT) },
                    onRename = { closeHistory(); show(LocalOverlay.Rename(it, local.conversations.first { c -> c.id == it }.title)) },
                    onSettings = { select(Destination.SETTINGS) },
                )
            },
        ) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Row(verticalAlignment = Alignment.CenterVertically) {
                        if (shell.selected == Destination.ASSISTANT) {
                            Image(painterResource(R.drawable.muyon_ready), contentDescription = "Muyon 吉祥物 · 本地模式",
                                modifier = Modifier.size(32.dp).padding(2.dp))
                            Spacer(Modifier.width(10.dp))
                        }
                        Column {
                        Text(if (shell.selected == Destination.ASSISTANT) local.active.title else shell.selected.label,
                            maxLines = 1, overflow = TextOverflow.Ellipsis,
                            style = MaterialTheme.typography.titleMedium,
                            modifier = Modifier.testTag(if (shell.selected == Destination.ASSISTANT) "conversation-title" else "page-title"))
                        if (shell.selected == Destination.ASSISTANT) Text("Muyon", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    } } },
                    navigationIcon = {
                        if (shell.selected == Destination.ASSISTANT) TextButton(onClick = ::openHistory,
                            modifier = Modifier.testTag("open-history").semantics { contentDescription = "打开会话侧栏" }) { ChatGlyph(ChatGlyphKind.SIDE_PANEL) }
                    },
                    actions = {
                        if (shell.selected == Destination.ASSISTANT) {
                            IconButton(onClick = { local = local.createConversation(); sample = false },
                                modifier = Modifier.testTag("new-conversation").semantics { contentDescription = "新建本地会话" }) { ChatGlyph(ChatGlyphKind.ADD) }
                        }
                    },
                )
            },
            bottomBar = {
                if (layout == NavigationLayout.BOTTOM_BAR) NavigationBar(Modifier.testTag("bottom-nav")) {
                    Destination.entries.forEach { destination ->
                        NavigationBarItem(selected = shell.selected == destination, onClick = { select(destination) },
                            icon = { ChatGlyph(destination.glyph()) }, label = { Text(destination.label) },
                            modifier = Modifier.testTag("destination-${destination.name}"))
                    }
                }
            },
        ) { padding ->
            Row(Modifier.fillMaxSize().padding(padding)) {
                if (layout == NavigationLayout.RAIL) NavigationRail(Modifier.testTag("rail")) {
                    Destination.entries.forEach { destination ->
                        NavigationRailItem(selected = shell.selected == destination, onClick = { select(destination) },
                            icon = { ChatGlyph(destination.glyph()) }, label = { Text(destination.label) },
                            modifier = Modifier.testTag("destination-${destination.name}"))
                    }
                }
                Box(Modifier.weight(1f).fillMaxSize()) {
                    when (shell.selected) {
                        Destination.ASSISTANT -> ConversationPage(
                            local, if (sample) fixtureScroll else assistantScroll, draftFocus,
                            inputActions = inputActions,
                            onMounted = { draftMounted = it },
                            onSave = { local = local.saveLocalNote() },
                            onOptions = { show(LocalOverlay.Capabilities) },
                            onNote = { id -> local = local.openNote(conversation.id, id) },
                            availability = availability,
                            sample = sample,
                            onSampleChange = { sample = it },
                            restorationNotice = memory.restorationNotice,
                        )
                        Destination.TASKS -> TasksLocalPage(local.taskFilter, taskScroll,
                            onFilter = { local = local.copy(taskFilter = it) }, onOptions = { show(LocalOverlay.Capabilities) })
                        Destination.DATA -> RecordsLocalPage(local, dataScroll,
                            onQuery = { local = local.copy(recordQuery = it) },
                            onNote = { ref -> local = local.openNote(ref.conversationId, ref.note.id) })
                        Destination.SETTINGS -> SettingsLocalPage(local, settingsScroll,
                            onTheme = { local = local.copy(theme = it) }, onOptions = { show(LocalOverlay.Capabilities) },
                            onDiagnostic = { agentOpen = false; diagnosticOpen = true },
                            onAgent = { diagnosticOpen = false; agentOpen = true })
                    }
                }
            }
        }
        }
        if (diagnosticOpen && shell.selected == Destination.SETTINGS) DiagnosticPanel(diagnosticCoordinator) { diagnosticOpen = false }
        if(agentOpen && shell.selected==Destination.SETTINGS) AgentRuntimePanel((LocalContext.current.applicationContext as MuyonLabApplication).agents){agentOpen=false}
        LocalOverlays(
            local,
            onDismiss = { local = local.copy(overlay = null) },
            onHistoryQuery = { local = local.copy(historyQuery = it) },
            onCreate = { local = local.createConversation(); select(Destination.ASSISTANT) },
            onSelect = { local = local.selectConversation(it); select(Destination.ASSISTANT) },
            onRename = { local = local.openRename(it) },
            onRenameDraft = { local = local.renameDraft(it) },
            onConfirmRename = { local = local.confirmRename() },
            onOpenConversation = { local = local.openInspectedConversation(); select(Destination.ASSISTANT) },
        )
    }
}

private fun Destination.glyph() = when (this) {
    Destination.ASSISTANT -> ChatGlyphKind.CHAT
    Destination.TASKS -> ChatGlyphKind.TASKS
    Destination.DATA -> ChatGlyphKind.FILES
    Destination.SETTINGS -> ChatGlyphKind.SETTINGS
}
