package com.mightyoung.muyon.product.ui.shell

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@Composable
fun RequestCandidatePanel(candidate: RequestCandidate, canRead: Boolean, onReadOriginal: () -> Unit) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("原请求候选 · 只读", style = MaterialTheme.typography.titleSmall)
        Text("请求：${candidate.snapshot.requestId}", style = MaterialTheme.typography.bodySmall)
        Text("配置来源：${candidate.configurationId ?: "未提供"}", style = MaterialTheme.typography.bodySmall)
        Text("缺少可信卡片身份与修订，执行和取消不可用。此处仅查询显示中的原请求。")
        OutlinedButton(onClick = onReadOriginal, enabled = canRead) { Text("读取此原请求") }
    }
}
