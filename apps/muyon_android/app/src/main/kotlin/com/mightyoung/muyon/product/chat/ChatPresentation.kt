package com.mightyoung.muyon.product.chat

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.mightyoung.muyon.product.R

private val ChatAccent = Color(0xFF599CE7)

@Composable
internal fun ChatAvatar(name: String, members: List<String> = emptyList()) {
    if (members.isEmpty()) {
        Surface(shape = RoundedCornerShape(14.dp), color = MaterialTheme.colorScheme.onSurface.copy(alpha = .08f)) {
            Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) {
                if (name == "Muyon 助手") Image(painterResource(R.drawable.muyon_avatar), null, Modifier.size(40.dp))
                else Text(name.take(1).ifBlank { "M" }, style = MaterialTheme.typography.titleLarge)
            }
        }
    } else {
        Box(Modifier.size(44.dp)) {
            members.take(2).forEachIndexed { index, member ->
                Surface(Modifier.size(29.dp).align(if (index == 0) Alignment.TopStart else Alignment.BottomEnd),
                    shape = CircleShape, color = MaterialTheme.colorScheme.surfaceContainerHigh,
                    border = BorderStroke(2.dp, MaterialTheme.colorScheme.surface)) {
                    Box(contentAlignment = Alignment.Center) { Text(member.take(1), style = MaterialTheme.typography.labelMedium) }
                }
            }
        }
    }
}

@Composable
internal fun ChatMemberChip(name: String) {
    Surface(shape = RoundedCornerShape(8.dp), color = MaterialTheme.colorScheme.onSurface.copy(alpha = .06f)) {
        Text(name, Modifier.padding(horizontal = 10.dp, vertical = 5.dp), style = MaterialTheme.typography.labelMedium)
    }
}

@Composable
internal fun ChatPanel(content: @Composable ColumnScope.() -> Unit) {
    Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.onSurface.copy(alpha = .04f),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = .12f))) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp), content = content)
    }
}

@Composable
internal fun ChatMessage(name: String, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(name, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp), content = content)
    }
}

@Composable
internal fun ChatDetails(title: String, content: @Composable ColumnScope.() -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    ChatPanel {
        TextButton(onClick = { expanded = !expanded }, modifier = Modifier.fillMaxWidth()) {
            Text(title, Modifier.weight(1f))
            Text(if (expanded) "收起" else "展开")
        }
        if (expanded) content()
    }
}

@Composable
internal fun ChatEmptyState(name: String, members: List<String>, enabled: Boolean, hasProject: Boolean,
    onSuppliers: () -> Unit, onPapers: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(vertical = 26.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        ChatAvatar(name, members)
        Text("和 $name 一起处理工作", style = MaterialTheme.typography.titleLarge)
        Text(if (members.isEmpty()) "从当前工作台的真实记录开始。" else "成员仅用于组织会话；不会自动执行或互相发送消息。",
            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        OutlinedButton(onClick = onSuppliers, enabled = enabled, shape = RoundedCornerShape(12.dp)) { Text("先查看供应商记录") }
        OutlinedButton(onClick = onPapers, enabled = enabled && hasProject, shape = RoundedCornerShape(12.dp)) { Text("先查看项目论文") }
    }
}

@Composable
internal fun ChatInputDock(draft: String, onDraft: (String) -> Unit, enabled: Boolean,
    onChat: () -> Unit, onSearch: () -> Unit) {
    Surface(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp),
        shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surfaceContainerLow,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = .20f))) {
        Column(Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            OutlinedTextField(value = draft, onValueChange = onDraft, label = { Text("消息草稿") },
                modifier = Modifier.fillMaxWidth(), minLines = 1, maxLines = 4,
                shape = RoundedCornerShape(12.dp),
                colors = OutlinedTextFieldDefaults.colors(unfocusedBorderColor = Color.Transparent,
                    focusedBorderColor = ChatAccent, unfocusedContainerColor = Color.Transparent))
            val searchButton: @Composable (Modifier) -> Unit = { modifier ->
                TextButton(onClick = onSearch, enabled = enabled, modifier = modifier) { Text("预览搜索请求") }
            }
            val sendButton: @Composable (Modifier) -> Unit = { modifier ->
                Button(onClick = onChat, enabled = enabled, modifier = modifier.testTag("chat-send"),
                    shape = RoundedCornerShape(12.dp), colors = ButtonDefaults.buttonColors(containerColor = ChatAccent,
                        contentColor = Color(0xFF10233A))) { Text("预览聊天请求") }
            }
            if (LocalDensity.current.fontScale >= 1.4f) {
                Column(Modifier.fillMaxWidth()) { searchButton(Modifier.fillMaxWidth()); sendButton(Modifier.fillMaxWidth()) }
            } else Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                searchButton(Modifier.weight(1f)); sendButton(Modifier)
            }
        }
    }
}
