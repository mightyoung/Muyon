package com.mightyoung.muyon.product.ui.shell

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp

/** Plain immutable observations, deliberately not an actionable ReceiptCard. */
@Composable
fun ReadOnlySnapshotPanel(snapshot: ReadOnlySnapshot?, notice: String, reading: Boolean, onRead: (() -> Unit)?) {
    Column(Modifier.fillMaxWidth().testTag("chat-read-only-snapshot"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("原请求只读快照", style = MaterialTheme.typography.titleSmall)
        Text("按需读取本机原请求记录，不发送或重试请求；不是当前业务记录状态。", style = MaterialTheme.typography.bodySmall)
        snapshot?.let {
            Text("原请求状态：${it.nativeStatus ?: "未提供"}")
            Text("执行状态：${it.executionStatus}（unavailable 不代表执行中）", style = MaterialTheme.typography.bodySmall)
            Text("原生请求会话：${it.requestConversation}", style = MaterialTheme.typography.bodySmall)
            Text("预占：${it.reservedMicroCny?.let { value -> "$value 微人民币" } ?: "未知"}")
            val actual = if (it.settlementObserved && it.nativeStatus == "completed") it.chargedMicroCny else null
            Text("实际费用：${actual?.let { value -> "$value 微人民币" } ?: "未知"}")
            if (it.cancellationStatus == "intent_recorded_outcome_unknown") Text("已记录取消意图；尚未确认取消；不代表回滚。")
            if (it.cancellationStatus == "confirmed_cancelled") Text("原请求记录：已确认取消；不代表回滚。")
        }
        Text("任务、来源与可操作卡片：缺完整可信事实，暂不可用。", style = MaterialTheme.typography.bodySmall)
        if (reading) Text("正在读取本机状态…", style = MaterialTheme.typography.bodySmall)
        if (notice.isNotBlank()) Text(notice, color = MaterialTheme.colorScheme.onSurfaceVariant)
        OutlinedButton(onClick = { onRead?.invoke() }, enabled = onRead != null && !reading,
            modifier = Modifier.heightIn(min = 48.dp)) { Text("查询只读候选与状态") }
    }
}
