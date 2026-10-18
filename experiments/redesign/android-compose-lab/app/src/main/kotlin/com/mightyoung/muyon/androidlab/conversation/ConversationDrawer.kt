package com.mightyoung.muyon.androidlab.conversation

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.mightyoung.muyon.androidlab.*

/** Candidate geometry, not measured Muse pixels. Product destinations remain in the shell. */
@Composable
internal fun ConversationDrawer(
    state: LocalUiState, widthDp: Float,
    onClose: () -> Unit, onCreate: () -> Unit, onQuery: (String) -> Unit,
    onSelect: (Int) -> Unit, onRename: (Int) -> Unit, onSettings: () -> Unit,
) {
    ModalDrawerSheet(
        modifier = Modifier.width((if (widthDp < 600f) widthDp - 80f else minOf(widthDp - 80f, 360f)).coerceAtLeast(200f).dp).fillMaxHeight().testTag("history-drawer"),
        drawerContainerColor = MaterialTheme.colorScheme.surfaceContainerLow,
        drawerShape = RoundedCornerShape(topEnd = 24.dp, bottomEnd = 24.dp),
    ) {
        Row(Modifier.fillMaxWidth().padding(start = 24.dp, end = 8.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Muyon", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f).semantics { heading() })
            TextButton(onClick = onClose, modifier = Modifier.testTag("close-history").semantics { contentDescription = "关闭会话侧栏" }) { Text("关闭") }
        }
        FilledTonalButton(onClick = onCreate, shape = RoundedCornerShape(16.dp),
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp).testTag("history-create")
                .semantics { contentDescription = "新建本地会话" }) {
            ChatGlyph(ChatGlyphKind.ADD); Spacer(Modifier.width(10.dp)); Text("新建会话")
        }
        OutlinedTextField(value = state.historyQuery, onValueChange = onQuery, singleLine = true,
            placeholder = { Text("搜索本地会话") }, shape = RoundedCornerShape(16.dp),
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).testTag("history-search")
                .semantics { contentDescription = "搜索会话名称和本地记录" })
        Text("本次使用", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 24.dp, top = 24.dp, bottom = 8.dp))
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp)) {
            val history = state.filteredConversations().asReversed()
            if (history.isEmpty()) item { Text("没有匹配的本地会话", Modifier.padding(16.dp), style = MaterialTheme.typography.bodyMedium) }
            items(history, key = { it.id }) { conversation ->
                Surface(onClick = { onSelect(conversation.id) }, shape = RoundedCornerShape(14.dp),
                    color = if (state.selectedConversationId == conversation.id) MaterialTheme.colorScheme.surfaceContainerHighest else MaterialTheme.colorScheme.surfaceContainerLow,
                    modifier = Modifier.fillMaxWidth().padding(vertical = 3.dp).testTag("history-conversation-${conversation.id}")
                        .semantics { selected = conversation.id == state.selectedConversationId }) {
                    Row(Modifier.padding(start = 14.dp, end = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f).padding(vertical = 14.dp)) {
                            Text(conversation.title, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyMedium)
                            if (conversation.memory.draft.isNotEmpty()) Text("草稿", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        TextButton(onClick = { onRename(conversation.id) }, modifier = Modifier.testTag("rename-conversation-${conversation.id}")
                            .semantics { contentDescription = "重命名 ${conversation.title}" }) { Text("改名", style = MaterialTheme.typography.labelSmall) }
                    }
                }
            }
        }
        HorizontalDivider(Modifier.padding(horizontal = 20.dp))
        TextButton(onClick = onSettings, modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).heightIn(min = 48.dp)) { Text("设置与能力") }
        Text("本地会话 · 未连接历史服务\n旋转可恢复；非持久存储", style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 24.dp, end = 24.dp, bottom = 20.dp))
    }
}
