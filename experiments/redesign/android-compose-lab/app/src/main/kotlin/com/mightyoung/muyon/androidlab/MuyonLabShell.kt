package com.mightyoung.muyon.androidlab

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.flow.collect

/** Functional offline scaffold. No competitor assets, network, business actions or Rust transport. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MuyonLabShell(
    port: RustUiPort = DisconnectedRustUiPort,
    windowWidthDp: Float? = null,
    initialState: ShellState = ShellState(),
) {
    var state by remember { mutableStateOf(initialState) }
    val width = windowWidthDp ?: LocalConfiguration.current.screenWidthDp.toFloat()
    val layout = navigationLayout(width)
    val assistantScroll = rememberLazyListState(initialState.memory(Destination.ASSISTANT).firstVisibleItemIndex, initialState.memory(Destination.ASSISTANT).firstVisibleItemOffset)
    val taskScroll = rememberLazyListState(initialState.memory(Destination.TASKS).firstVisibleItemIndex, initialState.memory(Destination.TASKS).firstVisibleItemOffset)
    val dataScroll = rememberLazyListState(initialState.memory(Destination.DATA).firstVisibleItemIndex, initialState.memory(Destination.DATA).firstVisibleItemOffset)
    val settingsScroll = rememberLazyListState(initialState.memory(Destination.SETTINGS).firstVisibleItemIndex, initialState.memory(Destination.SETTINGS).firstVisibleItemOffset)
    val currentScroll: LazyListState = when (state.selected) {
        Destination.ASSISTANT -> assistantScroll
        Destination.TASKS -> taskScroll
        Destination.DATA -> dataScroll
        Destination.SETTINGS -> settingsScroll
    }
    val draftFocus = remember { FocusRequester() }
    var draftMounted by remember { mutableStateOf(false) }
    val focusManager = LocalFocusManager.current
    val availability = remember(port) { port.availability() }
    val selected = state.selected
    LaunchedEffect(selected, currentScroll) {
        snapshotFlow { currentScroll.firstVisibleItemIndex to currentScroll.firstVisibleItemScrollOffset }
            .collect { (index, offset) ->
                state = state.store(selected, state.memory(selected).copy(firstVisibleItemIndex = index, firstVisibleItemOffset = offset))
            }
    }
    LaunchedEffect(selected, draftMounted) {
        if (selected == Destination.ASSISTANT && draftMounted && state.memory(selected).focus == FocusSlot.DRAFT) draftFocus.requestFocus()
    }
    fun select(destination: Destination) {
        focusManager.clearFocus()
        state = state.select(destination)
    }
    // Neutral placeholders only. These are not measured WorkBuddy theme tokens.
    val colors = if (isSystemInDarkTheme()) darkColorScheme(primary = Color.White, onPrimary = Color.Black)
        else lightColorScheme(primary = Color.Black, onPrimary = Color.White)
    MaterialTheme(colorScheme = colors) {
        Scaffold(
            topBar = { TopAppBar(title = { Text("Muyon · 离线骨架") }) },
            bottomBar = {
                if (layout == NavigationLayout.BOTTOM_BAR) NavigationBar(Modifier.testTag("bottom-nav")) {
                    Destination.entries.forEach { destination ->
                        NavigationBarItem(
                            selected = selected == destination,
                            onClick = { select(destination) },
                            icon = { Text(destination.label.take(1)) },
                            label = { Text(destination.label) },
                            modifier = Modifier.testTag("destination-${destination.name}"),
                        )
                    }
                }
            },
        ) { padding ->
            Row(Modifier.fillMaxSize().padding(padding)) {
                if (layout == NavigationLayout.RAIL) NavigationRail(Modifier.testTag("rail")) {
                    Destination.entries.forEach { destination ->
                        NavigationRailItem(
                            selected = selected == destination,
                            onClick = { select(destination) },
                            icon = { Text(destination.label.take(1)) },
                            label = { Text(destination.label) },
                            modifier = Modifier.testTag("destination-${destination.name}"),
                        )
                    }
                }
                key("page-content") {
                    LazyColumn(Modifier.weight(1f).fillMaxSize().padding(16.dp), state = currentScroll) {
                        item("heading") { Text(selected.label, Modifier.semantics { heading() }, style = MaterialTheme.typography.titleLarge) }
                        item("connection") {
                            when (availability) {
                                PortAvailability.NOT_CONNECTED -> Text(
                                    "未连接执行服务；不能发送消息或读取任务。",
                                    Modifier.testTag("port-disconnected").semantics { liveRegion = LiveRegionMode.Polite },
                                )
                            }
                        }
                        if (selected == Destination.ASSISTANT) item("draft") {
                            DisposableEffect(Unit) {
                                draftMounted = true
                                onDispose { draftMounted = false }
                            }
                            OutlinedTextField(
                                value = state.memory(Destination.ASSISTANT).draft,
                                onValueChange = { raw -> state = state.store(Destination.ASSISTANT, state.memory(Destination.ASSISTANT).copy(draft = raw)) },
                                label = { Text("临时输入（未发送）") },
                                minLines = 3,
                                modifier = Modifier.fillMaxWidth().testTag("assistant-draft").focusRequester(draftFocus)
                                    .onFocusChanged { if (it.isFocused) state = state.store(Destination.ASSISTANT, state.memory(Destination.ASSISTANT).copy(focus = FocusSlot.DRAFT)) },
                            )
                        }
                        item("scope") {
                            Column {
                                Text("这是独立离线界面骨架；没有读取业务目录或生成任务结果。")
                                Text("输入仅在当前内存中保留，关闭或重建应用后不保证恢复。")
                            }
                        }
                    }
                }
            }
        }
    }
}
