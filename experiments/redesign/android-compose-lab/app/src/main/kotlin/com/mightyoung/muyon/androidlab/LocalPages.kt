@file:OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)

package com.mightyoung.muyon.androidlab

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

@Composable
internal fun LocalConnectionNotice(availability: PortAvailability = PortAvailability.NOT_CONNECTED) {
    when (availability) {
        PortAvailability.NOT_CONNECTED -> Surface(color = MaterialTheme.colorScheme.surfaceContainer, modifier = Modifier.fillMaxWidth()) {
            Text("执行服务未连接 · 内容仅保存在当前内存中", style = MaterialTheme.typography.labelMedium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp).testTag("port-disconnected")
                    .semantics { liveRegion = LiveRegionMode.Polite })
        }
    }
}

@Composable
internal fun AssistantLocalPage(
    state: LocalUiState,
    scroll: LazyListState,
    draftFocus: FocusRequester,
    onMemory: (PageMemory) -> Unit,
    onMounted: (Boolean) -> Unit,
    onSave: () -> Unit,
    onOptions: () -> Unit,
    onNote: (Int) -> Unit,
    availability: PortAvailability,
) {
    val conversation = state.active
    var renderedCount by remember(conversation.id) { mutableIntStateOf(conversation.notes.size) }
    LaunchedEffect(conversation.id, conversation.notes.size) {
        if (conversation.notes.size > renderedCount) scroll.animateScrollToItem(conversation.notes.lastIndex)
        renderedCount = conversation.notes.size
    }
    Column(Modifier.fillMaxSize()) {
        LocalConnectionNotice(availability)
        Text(conversation.title, style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp).testTag("conversation-title").semantics { heading() })
        LazyColumn(state = scroll, modifier = Modifier.weight(1f).fillMaxWidth().testTag("local-chat-list"),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (conversation.notes.isEmpty()) item("empty") {
                Column(Modifier.padding(vertical = 24.dp)) {
                    Text("从一条本地记录开始", style = MaterialTheme.typography.headlineSmall)
                    Spacer(Modifier.height(8.dp))
                    Text("写下想法并保存，或从右上角新建、切换会话。这里不会生成助手回复，也不会派发任务。",
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            items(conversation.notes, key = { it.id }) { note ->
                LocalNoteCard(note, onClick = { onNote(note.id) }, modifier = Modifier.testTag("chat-note-${note.id}"))
            }
        }
        HorizontalDivider()
        LocalComposer(conversation.id, onMounted) {
            Column(Modifier.fillMaxWidth().imePadding().padding(horizontal = 12.dp, vertical = 8.dp)) {
                OutlinedTextField(
                    value = conversation.memory.draft,
                    onValueChange = { onMemory(conversation.memory.copy(draft = it)) },
                    label = { Text("写下内容") },
                    supportingText = { Text("本地记录 · 未发送给模型 · 关闭后不保证保留") },
                    minLines = 2, maxLines = 6,
                    modifier = Modifier.fillMaxWidth().testTag("assistant-draft").focusRequester(draftFocus)
                        .onFocusChanged { if (it.isFocused) onMemory(conversation.memory.copy(focus = FocusSlot.DRAFT)) },
                )
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton(onClick = onOptions, modifier = Modifier.testTag("input-options")) { Text("输入选项") }
                    Spacer(Modifier.weight(1f))
                    OutlinedButton(onClick = {}, enabled = false, modifier = Modifier.testTag("send-unavailable")) { Text("发送") }
                    Button(onClick = onSave, enabled = state.canSaveLocalNote, modifier = Modifier.testTag("save-local-note")) { Text("保存记录") }
                }
            }
        }
    }
}

@Composable
private fun LocalComposer(id: Int, onMounted: (Boolean) -> Unit, content: @Composable () -> Unit) {
    androidx.compose.runtime.key(id) {
        DisposableEffect(id) { onMounted(true); onDispose { onMounted(false) } }
        content()
    }
}

@Composable
internal fun LocalNoteCard(note: LocalNote, onClick: () -> Unit, modifier: Modifier = Modifier, conversationTitle: String? = null) {
    OutlinedCard(onClick = onClick, modifier = modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(conversationTitle ?: "你 · 本地记录（未发送）", style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(note.text, maxLines = 8, overflow = TextOverflow.Ellipsis)
            Text("查看记录", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
internal fun TasksLocalPage(filter: LocalTaskFilter, scroll: LazyListState, onFilter: (LocalTaskFilter) -> Unit, onOptions: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        LocalConnectionNotice()
        LazyColumn(state = scroll, modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            item { Text("任务", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() }) }
            item {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    LocalTaskFilter.entries.forEach { value ->
                        FilterChip(selected = filter == value, onClick = { onFilter(value) }, label = { Text(taskFilterLabel(value)) },
                            modifier = Modifier.testTag("task-filter-${value.name}"))
                    }
                }
            }
            item {
                Text("尚未连接任务服务", style = MaterialTheme.typography.titleMedium)
                Text("无法读取真实任务。这里仅保留你的筛选选择，不表示已查询到空任务列表。", modifier = Modifier.padding(top = 8.dp))
            }
            item { OutlinedButton(onClick = {}, enabled = false) { Text("刷新任务（未接入）") } }
            item { TextButton(onClick = onOptions) { Text("查看当前可用能力") } }
        }
    }
}

private fun taskFilterLabel(filter: LocalTaskFilter) = when (filter) {
    LocalTaskFilter.ALL -> "全部"
    LocalTaskFilter.RUNNING -> "进行中"
    LocalTaskFilter.WAITING_CONFIRMATION -> "待确认"
}

@Composable
internal fun RecordsLocalPage(state: LocalUiState, scroll: LazyListState, onQuery: (String) -> Unit, onNote: (LocalNoteRef) -> Unit) {
    val notes = state.filteredNotes()
    Column(Modifier.fillMaxSize()) {
        LocalConnectionNotice()
        Text("本地记录", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.padding(16.dp).semantics { heading() })
        Text("仅包含你在本次会话中保存的文字；未读取文件、知识库或业务资料。", style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.padding(horizontal = 16.dp))
        OutlinedTextField(value = state.recordQuery, onValueChange = onQuery, label = { Text("搜索本地记录") }, singleLine = true,
            modifier = Modifier.fillMaxWidth().padding(16.dp).testTag("record-search"))
        LazyColumn(state = scroll, modifier = Modifier.fillMaxSize().testTag("local-record-list"), contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (notes.isEmpty()) item("empty") { Text(if (state.recordQuery.isEmpty()) "还没有本地记录，在助手页输入并保存后会显示在这里。" else "没有匹配的本地记录。") }
            items(notes, key = { "${it.conversationId}-${it.note.id}" }) { ref ->
                LocalNoteCard(ref.note, onClick = { onNote(ref) }, conversationTitle = "${ref.conversationTitle} · 未发送",
                    modifier = Modifier.testTag("record-${ref.conversationId}-${ref.note.id}"))
            }
        }
    }
}

@Composable
internal fun SettingsLocalPage(state: LocalUiState, scroll: LazyListState, onTheme: (LabTheme) -> Unit, onOptions: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        LocalConnectionNotice()
        LazyColumn(state = scroll, modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            item { Text("设置", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() }) }
            item {
                Text("界面主题", style = MaterialTheme.typography.titleMedium)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    LabTheme.entries.forEach { value ->
                        FilterChip(selected = state.theme == value, onClick = { onTheme(value) }, label = {
                            Text(when (value) { LabTheme.SYSTEM -> "跟随系统"; LabTheme.LIGHT -> "浅色"; LabTheme.DARK -> "深色" })
                        }, modifier = Modifier.testTag("theme-${value.name}"))
                    }
                }
                Text("只影响本次界面；主题选择尚未持久化。", style = MaterialTheme.typography.bodySmall)
            }
            item { HorizontalDivider() }
            item {
                Text("本次本地内容", style = MaterialTheme.typography.titleMedium)
                Text("${state.conversations.size} 个本地会话 · ${state.conversations.sumOf { it.notes.size }} 条用户记录")
                Text("内容仅在内存中，关闭或重建应用后不保证保留。", style = MaterialTheme.typography.bodySmall)
            }
            item { TextButton(onClick = onOptions) { Text("模型、附件与执行能力") } }
            item { Text("Muyon", style = MaterialTheme.typography.titleMedium); Text("原创可调整布局；未验证与参考应用的完整页面像素一致性。", style = MaterialTheme.typography.bodySmall) }
        }
    }
}
