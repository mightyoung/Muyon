package com.mightyoung.muyon.product

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.Button
import androidx.compose.material3.TextButton
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.mightyoung.muyon.product.agentipc.ProductClient
import com.mightyoung.muyon.product.supplier.SupplierScreen
import com.mightyoung.muyon.product.research.ResearchScreen
import com.mightyoung.muyon.product.chat.ChatScreen
import com.mightyoung.muyon.product.agents.AgentCatalog
import com.mightyoung.muyon.product.agents.AgentLibraryScreen
import com.mightyoung.muyon.product.agents.visibleName
import com.mightyoung.muyon.product.design.MuyonTheme
import com.mightyoung.muyon.product.design.WorkbenchShell

class MainActivity : ComponentActivity() {
    private lateinit var client: ProductClient
    private var connected by mutableStateOf(false)
    private var initialized by mutableStateOf(false)
    private var existing by mutableStateOf(false)
    private var status by mutableStateOf("正在连接本地内核")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        client = ProductClient(this) { ready ->
            connected = ready
            if (ready) { existing = client.workspaceExists; client.call("health") { reply ->
                initialized = reply.optString("status") == "ok"
                status = if (initialized) "本地工作台已连接" else if (existing) "工作台暂不可用，请重试连接" else "请创建新工作台"
            } } else { initialized = false; status = "连接已断开；未确认的操作请查询原结果" }
        }
        setContent {
            MuyonTheme {
                var tab by rememberSaveable { mutableStateOf("chat") }
                var conversationKey by rememberSaveable { mutableStateOf("default") }
                var conversationTitle by rememberSaveable { mutableStateOf("Muyon 助手") }
                var memberNames by rememberSaveable { mutableStateOf(arrayListOf<String>()) }
                var navigationError by remember { mutableStateOf("") }
                val title = when (tab) {
                    "supplier" -> "供应商管理"
                    "research" -> "研究空间"
                    "agents" -> "智能体与群组"
                    else -> conversationTitle
                }
                WorkbenchShell(tab, title, status, onSelect = { tab = it }) {
                    Column(Modifier.fillMaxSize()) {
                        if (!connected || !initialized) {
                            Text(status, Modifier.padding(24.dp), style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        if (!connected) TextButton(onClick = { recreate() }) { Text("重试连接") }
                        if (connected && !initialized) Button(onClick = {
                            client.call(if (existing) "health" else "initialize") { reply ->
                                initialized = reply.optString("status") == "ok"
                                if (initialized) existing = true
                                status = if (initialized) "本地工作台已连接" else reply.optString("error")
                            }
                        }) { Text(if (existing) "重试连接" else "创建新工作台") }
                        if (navigationError.isNotEmpty()) Text(navigationError, Modifier.padding(16.dp), color = MaterialTheme.colorScheme.error)
                        if (connected && initialized) {
                            when (tab) {
                                "supplier" -> SupplierScreen(client)
                                "research" -> ResearchScreen(client)
                                "agents" -> AgentLibraryScreen { agentId, groupId ->
                                    try {
                                        val catalog = AgentCatalog(this@MainActivity).read()
                                        if (groupId != null) {
                                            val group = catalog.groups.single { it.id == groupId && !it.archived }
                                            val members = group.members.map { id -> visibleName(catalog.agents.single { it.id == id && !it.archived }.name, "未命名智能体") }
                                            conversationKey = "group:${group.id}"
                                            conversationTitle = visibleName(group.name, "未命名群组")
                                            memberNames = ArrayList(members)
                                        } else {
                                            val agent = catalog.agents.single { it.id == agentId && !it.archived }
                                            conversationKey = "agent:${agent.id}"
                                            conversationTitle = visibleName(agent.name, "未命名智能体")
                                            memberNames = arrayListOf()
                                        }
                                        navigationError = ""; tab = "chat"
                                    } catch (_: Exception) {
                                        navigationError = "会话身份暂不可用，请返回目录核实智能体与成员。"
                                    }
                                }
                                else -> {
                                    val selectedAgent = if (conversationKey.startsWith("agent:")) try {
                                        AgentCatalog(this@MainActivity).activeAgent(conversationKey.removePrefix("agent:"))
                                    } catch (_: Exception) { null } else null
                                    if (conversationKey.startsWith("agent:") && selectedAgent == null) {
                                        Column(Modifier.padding(24.dp)) {
                                            Text("智能体配置暂不可用，请返回目录核实后重新打开对话。")
                                            TextButton(onClick = { tab = "agents" }) { Text("返回智能体目录") }
                                        }
                                    } else ChatScreen(client,
                                    getSharedPreferences("muyon_product_research_v2", 0).getString("project_id", null),
                                    conversationKey, conversationTitle, memberNames,
                                    selectedAgent?.role.orEmpty(), selectedAgent?.instructions.orEmpty())
                                }
                            }
                        }
                    }
                }
            }
        }
        client.bind()
    }
    override fun onDestroy() { client.close(); super.onDestroy() }
}
