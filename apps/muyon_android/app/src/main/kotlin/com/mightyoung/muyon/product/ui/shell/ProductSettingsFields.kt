package com.mightyoung.muyon.product.ui.shell

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp

/** Presentation only. The host retains credential clearing, confirmation and budget authority. */
@Composable
fun ProductSettingsFields(
    credential: String, onCredential: (String) -> Unit,
    budget: String, onBudget: (String) -> Unit,
    calls: String, onCalls: (String) -> Unit,
    availability: String, accounting: String,
) {
    var detailsOpen by remember { mutableStateOf(false) }
    Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("仅配置，不会发送请求。此工作台的助手与群组共享模型配置和累计预算。",
            style = MaterialTheme.typography.bodyMedium)
        OutlinedTextField(credential, onCredential, Modifier.fillMaxWidth().testTag("settings-credential"),
            label = { Text("API 密钥（仅本次运行）") }, singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password))
        OutlinedTextField(budget, onBudget, Modifier.fillMaxWidth().testTag("settings-budget"),
            label = { Text("累计预算（微人民币）") }, singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
        OutlinedTextField(calls, onCalls, Modifier.fillMaxWidth().testTag("settings-calls"),
            label = { Text("累计请求次数上限") }, singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
        Text("1 元 = 1,000,000 微人民币。更换配置不会清零已用费用或未知结果的保留占额。",
            style = MaterialTheme.typography.bodySmall)
        Text(availability, Modifier.testTag("chat-availability"), style = MaterialTheme.typography.bodySmall)
        if (accounting.isNotEmpty()) Text(accounting, style = MaterialTheme.typography.bodySmall)
        TextButton(onClick = { detailsOpen = !detailsOpen }) { Text(if (detailsOpen) "收起说明" else "配置与计费说明") }
        if (detailsOpen) {
            Text("供应商：DeepSeek；端点固定为 api.deepseek.com。不会读取历史凭据或预算。")
            Text("凭据仅保留在当前 Service 内存，重启后需重新输入。成员资料不会自动发送给模型，也不会自动调度成员。")
            Text("当前托管聊天计费上界与搜索价格证明尚未安装，预览会明确阻止外发。每次确认先保留经可信证明的请求成本上界；未知结果保留占额。填写预算不能替代真实计费证明。")
        }
    }
}
