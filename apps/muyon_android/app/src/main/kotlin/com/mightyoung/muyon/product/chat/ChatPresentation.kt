package com.mightyoung.muyon.product.chat

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.mightyoung.muyon.product.R
import org.json.JSONObject

/** Profile text remains user input. It adds no system instruction or tool authority. */
internal fun agentUserInput(draft: String, role: String, instructions: String): String {
    if (role.isBlank() && instructions.isBlank()) return draft
    return buildString {
        append("用户选择的助手角色说明（仅本次用户输入，不增加权限）：\n")
        if (role.isNotBlank()) append("身份与职责：").append(role).append('\n')
        if (instructions.isNotBlank()) append("说明：\n").append(instructions).append('\n')
        append("\n本次消息：\n").append(draft)
    }
}

internal fun hasCompleteOutboundPreview(plan: JSONObject): Boolean =
    plan.optString("outbound_endpoint").startsWith("https://") &&
        (plan.optJSONObject("outbound_preview") != null || plan.optJSONArray("outbound_preview") != null)

/** Display the exact prepared payload, including history and advertised tools. */
@Composable
internal fun ChatOutboundPreview(plan: JSONObject) {
    if (!hasCompleteOutboundPreview(plan)) {
        Text("未取得完整出站内容与目的地址，不能确认外发。", Modifier.testTag("chat-outbound-missing"), color = MaterialTheme.colorScheme.error)
        return
    }
    Text("完整出站内容（含自动加入的历史、工具与参数）", style = MaterialTheme.typography.titleSmall)
    Text(plan.optString("outbound_endpoint"), Modifier.testTag("chat-outbound-endpoint"))
    val bytes = plan.optJSONObject("outbound_preview")?.toString(2) ?: plan.getJSONArray("outbound_preview").toString(2)
    ConversationRichText("```json\n$bytes\n```", Modifier.testTag("chat-outbound-payload"))
}

/** A projection of the actual native observation, never a generated thought transcript. */
@Composable
internal fun ChatRequestActivity(observation: JSONObject) {
    var expanded by remember(observation.optString("request_id")) { mutableStateOf(false) }
    val status = observation.optString("status")
    val label = when (status) {
        "completed", "tool_consumed" -> "已完成"
        "tool_pending" -> "等待工具审核"
        "prepared" -> "等待发送确认"
        "cancelled" -> "已取消"
        "reserved" -> "已保留预算"
        else -> "结果待核实"
    }
    Column(Modifier.fillMaxWidth().testTag("chat-request-activity")) {
        TextButton(onClick = { expanded = !expanded }, modifier = Modifier.testTag("chat-request-activity-toggle")) {
            Text("调用过程 · $label", style = MaterialTheme.typography.labelMedium)
        }
        if (expanded) {
            Text(if (observation.optBoolean("attempted")) "该原请求已经尝试外发。" else "尚无已尝试外发的记录。", style = MaterialTheme.typography.bodySmall)
            observation.optString("failure_stage").takeIf { it.isNotBlank() && it != "null" }?.let {
                Text("中断位置：$it", style = MaterialTheme.typography.bodySmall)
            }
            observation.optJSONObject("answer")?.optJSONObject("call")?.let { call ->
                Text("工具：${call.optString("name")} · ${call.optString("id")}", style = MaterialTheme.typography.bodySmall)
            }
            Text("仅展示实际请求与工具状态。", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

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
            val inputStyle = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp, lineHeight = 24.sp,
                color = MaterialTheme.colorScheme.onSurface)
            BasicTextField(value = draft, onValueChange = onDraft,
                modifier = Modifier.fillMaxWidth().heightIn(min = 40.dp, max = 192.dp).testTag("chat-draft"),
                minLines = 1, maxLines = 6, textStyle = inputStyle,
                cursorBrush = SolidColor(MaterialTheme.colorScheme.onSurface),
                decorationBox = { inner ->
                    Box(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 4.dp)) {
                        if (draft.isEmpty()) Text("发送消息…", style = inputStyle, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        inner()
                    }
                })
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
