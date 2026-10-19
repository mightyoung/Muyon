package com.mightyoung.muyon.androidlab

import androidx.compose.runtime.*
import androidx.compose.material3.*
import androidx.compose.foundation.layout.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp

@Composable internal fun SearchSettingsCard(port:SearchSettingsPort) {
    var view by remember(port){mutableStateOf(port.read())}
    var enabled by remember(view.settings){mutableStateOf(view.settings.enabled)}
    var connection by remember(view.settings){mutableStateOf(view.settings.connection)}
    Column(verticalArrangement=Arrangement.spacedBy(8.dp),modifier=Modifier.testTag("search-settings")) {
        Text("网页搜索",style=MaterialTheme.typography.titleMedium)
        Text("DeepSeek Search · 独立搜索接口")
        Row {Switch(checked=enabled,onCheckedChange={enabled=it},modifier=Modifier.testTag("search-enabled"));Text("允许当前聊天使用网页搜索")}
        Text("连接引用（不保存密钥）")
        FilterChip(selected=connection.isEmpty(),onClick={connection=""},label={Text("未选择")},modifier=Modifier.testTag("search-connection-none"))
        view.installedConnections.forEach { ref->FilterChip(selected=connection==ref,onClick={connection=ref},label={Text(if(view.synthetic)"离线合成连接" else ref)},modifier=Modifier.testTag("search-connection-$ref")) }
        if(view.installedConnections.isEmpty())Text("当前未安装可信连接；真实 SearchHost 集成尚未完成。")
        Text(searchSettingsStatus(view),modifier=Modifier.testTag("search-settings-status"))
        Text("保存仅更新本机配置，不发送查询、不检测余额。真实调用需独立搜索预算；不使用聊天预算。",style=MaterialTheme.typography.bodySmall)
        if(view.synthetic)Text("此构建仅有无网络合成服务；来源与费用为合成账本证据。",style=MaterialTheme.typography.bodySmall)
        Button(onClick={view=port.save(enabled,connection)},modifier=Modifier.testTag("search-settings-save")){Text("保存搜索配置")}
        if(view.message.isNotEmpty())Text(view.message,modifier=Modifier.testTag("search-settings-message"))
    }
}
