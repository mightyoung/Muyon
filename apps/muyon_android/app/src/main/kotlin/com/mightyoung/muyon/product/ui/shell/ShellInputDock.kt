package com.mightyoung.muyon.product.ui.shell

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/** Uses host typography/colors so the foundation branch remains the sole token owner. */
@Composable
fun ShellInputDock(draft: String, onDraft: (String) -> Unit, enabled: Boolean,
    onChat: () -> Unit, onMore: () -> Unit, moreMenu: @Composable () -> Unit) {
    Surface(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
        shape = RoundedCornerShape(32.dp), color = MaterialTheme.colorScheme.surface) {
        Row(Modifier.padding(6.dp), verticalAlignment = Alignment.Bottom) {
            Box {
                IconButton(onClick = onMore, modifier = Modifier.size(48.dp)) {
                    Text("+", Modifier.semantics { contentDescription = "更多聊天操作" })
                }
                moreMenu()
            }
            TextField(value = draft, onValueChange = onDraft,
                modifier = Modifier.weight(1f).heightIn(max = 192.dp).testTag("chat-draft"),
                placeholder = { Text("继续提问…") }, minLines = 1, maxLines = 6,
                textStyle = MaterialTheme.typography.bodyLarge,
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = MaterialTheme.colorScheme.surface,
                    unfocusedContainerColor = MaterialTheme.colorScheme.surface,
                    focusedIndicatorColor = androidx.compose.ui.graphics.Color.Transparent,
                    unfocusedIndicatorColor = androidx.compose.ui.graphics.Color.Transparent))
            FilledIconButton(onClick = onChat, enabled = enabled,
                modifier = Modifier.size(48.dp).testTag("chat-send")) {
                Text("↑", Modifier.semantics { contentDescription = "预览聊天请求" })
            }
        }
    }
}
