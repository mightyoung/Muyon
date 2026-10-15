@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.mightyoung.muyon.androidlab

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

@Composable
internal fun LocalOverlays(
    state: LocalUiState,
    onDismiss: () -> Unit,
    onHistoryQuery: (String) -> Unit,
    onCreate: () -> Unit,
    onSelect: (Int) -> Unit,
    onRename: (Int) -> Unit,
    onRenameDraft: (String) -> Unit,
    onConfirmRename: () -> Unit,
    onOpenConversation: () -> Unit,
) {
    when (val overlay = state.overlay) {
        null -> Unit
        LocalOverlay.History -> ModalBottomSheet(onDismissRequest = onDismiss, modifier = Modifier.testTag("history-sheet")) {
            Column(Modifier.fillMaxWidth().heightIn(max = 600.dp).padding(horizontal = 16.dp)) {
                Text("本地会话", style = MaterialTheme.typography.titleLarge, modifier = Modifier.semantics { heading() })
                Text("仅当前内存中的草稿与用户记录，不是服务端会话历史。", style = MaterialTheme.typography.bodySmall)
                OutlinedTextField(value = state.historyQuery, onValueChange = onHistoryQuery, label = { Text("搜索会话或已保存文字") },
                    singleLine = true, modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp).testTag("history-search"))
                Button(onClick = onCreate, modifier = Modifier.fillMaxWidth().testTag("history-create")) { Text("新建本地会话") }
                LazyColumn(Modifier.weight(1f, fill = false).fillMaxWidth(), contentPadding = PaddingValues(vertical = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    val filtered = state.filteredConversations()
                    if (filtered.isEmpty()) item { Text("没有匹配的本地会话。") }
                    items(filtered, key = { it.id }) { conversation ->
                        OutlinedCard(onClick = { onSelect(conversation.id) }, modifier = Modifier.fillMaxWidth()
                            .testTag("history-conversation-${conversation.id}").semantics { selected = conversation.id == state.selectedConversationId }) {
                            Row(Modifier.fillMaxWidth().padding(start = 14.dp, end = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Column(Modifier.weight(1f).padding(vertical = 12.dp)) {
                                    Text(conversation.title, maxLines = 2, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleSmall)
                                    Text("${conversation.notes.size} 条本地记录" + if (conversation.memory.draft.isNotEmpty()) " · 有未保存输入" else "",
                                        style = MaterialTheme.typography.bodySmall)
                                }
                                TextButton(onClick = { onRename(conversation.id) }, modifier = Modifier.testTag("rename-conversation-${conversation.id}")) { Text("改名") }
                            }
                        }
                    }
                }
            }
        }
        is LocalOverlay.Rename -> AlertDialog(
            onDismissRequest = onDismiss,
            modifier = Modifier.testTag("rename-dialog"),
            title = { Text("修改本地会话名称") },
            text = { OutlinedTextField(value = overlay.titleDraft, onValueChange = onRenameDraft, label = { Text("会话名称") },
                modifier = Modifier.fillMaxWidth().testTag("rename-input")) },
            confirmButton = { TextButton(onClick = onConfirmRename, enabled = overlay.titleDraft.isNotBlank(), modifier = Modifier.testTag("rename-confirm")) { Text("保存名称") } },
            dismissButton = { TextButton(onClick = onDismiss, modifier = Modifier.testTag("rename-cancel")) { Text("取消") } },
        )
        LocalOverlay.Capabilities -> ModalBottomSheet(onDismissRequest = onDismiss, modifier = Modifier.testTag("capabilities-sheet")) {
            Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("当前输入能力", style = MaterialTheme.typography.titleLarge, modifier = Modifier.semantics { heading() })
                Text("本地记录可用", style = MaterialTheme.typography.titleMedium)
                Text("保存你输入的文字，不会向模型发送，也不会创建后端任务。")
                HorizontalDivider()
                OutlinedButton(onClick = {}, enabled = false, modifier = Modifier.fillMaxWidth().testTag("model-unavailable")) { Text("选择模型（未连接）") }
                OutlinedButton(onClick = {}, enabled = false, modifier = Modifier.fillMaxWidth().testTag("attachment-unavailable")) { Text("添加附件（未接入）") }
                Text("没有启用账号、模型、附件、授权、文件读取或执行能力。", style = MaterialTheme.typography.bodySmall)
                TextButton(onClick = onDismiss, modifier = Modifier.fillMaxWidth().testTag("capabilities-close")) { Text("关闭") }
                Spacer(Modifier.height(12.dp))
            }
        }
        is LocalOverlay.NoteDetails -> state.inspectedNote()?.let { ref ->
            AlertDialog(
                onDismissRequest = onDismiss, modifier = Modifier.testTag("note-details"),
                title = { Text("本地记录 · 未发送") },
                text = {
                    Column(Modifier.heightIn(max = 360.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(ref.conversationTitle, style = MaterialTheme.typography.labelMedium)
                        SelectionContainer { Text(ref.note.text) }
                        Text("这是你保存的用户文字，不是助手回复或执行结果。", style = MaterialTheme.typography.bodySmall)
                    }
                },
                confirmButton = { TextButton(onClick = onOpenConversation, modifier = Modifier.testTag("note-open-conversation")) { Text("打开会话") } },
                dismissButton = { TextButton(onClick = onDismiss) { Text("关闭") } },
            )
        }
    }
}
