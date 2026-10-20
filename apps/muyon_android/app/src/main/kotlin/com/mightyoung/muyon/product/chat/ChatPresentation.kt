package com.mightyoung.muyon.product.chat

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.mightyoung.muyon.product.R

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
internal fun ChatPanel(content: @Composable ColumnScope.() -> Unit) {
    Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.onSurface.copy(alpha = .04f),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = .12f))) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp), content = content)
    }
}

@Composable
internal fun ChatEmptyState(name: String, members: List<String>) {
    Column(Modifier.fillMaxWidth().padding(vertical = 64.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        ChatAvatar(name, members)
        Text("今天想做些什么？", style = MaterialTheme.typography.headlineSmall)
        Text(if (members.isEmpty()) name else "$name · ${members.size} 位成员",
            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
internal fun ChatInputDock(draft: String, onDraft: (String) -> Unit, enabled: Boolean,
    onChat: () -> Unit, onMore: () -> Unit, moreMenu: @Composable () -> Unit) {
    Surface(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        shape = RoundedCornerShape(32.dp), color = MaterialTheme.colorScheme.surface,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = .14f))) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            OutlinedTextField(value = draft, onValueChange = onDraft, label = { Text("消息草稿") },
                modifier = Modifier.fillMaxWidth().heightIn(max = 192.dp), minLines = 1, maxLines = 6,
                textStyle = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp, lineHeight = 24.sp),
                shape = RoundedCornerShape(12.dp),
                colors = OutlinedTextFieldDefaults.colors(unfocusedBorderColor = Color.Transparent,
                    focusedBorderColor = Color.Transparent, unfocusedContainerColor = Color.Transparent,
                    focusedContainerColor = Color.Transparent))
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Box {
                    IconButton(onClick = onMore, modifier = Modifier.testTag("chat-more")) {
                        Icon(painterResource(R.drawable.wb_add), "更多聊天操作", Modifier.size(22.dp))
                    }
                    moreMenu()
                }
                Spacer(Modifier.weight(1f))
                IconButton(onClick = onChat, enabled = enabled, modifier = Modifier.testTag("chat-send").size(48.dp)) {
                    Surface(Modifier.size(32.dp), shape = CircleShape,
                        color = (if (isSystemInDarkTheme()) Color(0xFF0074E8) else Color(0xFFCBE5FF)).copy(alpha = if (enabled) 1f else .4f),
                        contentColor = (if (isSystemInDarkTheme()) Color.White else Color(0xFF111112)).copy(alpha = if (enabled) 1f else .4f)) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(painterResource(R.drawable.wb_send), "预览聊天请求", Modifier.size(18.dp))
                        }
                    }
                }
            }
        }
    }
}
