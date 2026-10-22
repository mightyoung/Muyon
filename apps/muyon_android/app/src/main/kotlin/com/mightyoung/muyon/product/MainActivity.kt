package com.mightyoung.muyon.product

import android.os.Bundle
import android.content.SharedPreferences
import android.content.res.Configuration
import com.mightyoung.muyon.product.ui.shell.ActivityReaderSurface
import androidx.lifecycle.ViewModelProvider
import com.mightyoung.muyon.product.ui.shell.ShellConfigurationState
import com.mightyoung.muyon.product.ui.shell.configurationBufferScope
import com.mightyoung.muyon.product.ui.shell.ConfigurationPreviewHost
import com.mightyoung.muyon.product.ui.shell.DocumentCapabilitiesScreen
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
import com.mightyoung.muyon.product.ui.system.FoundationTheme
import com.mightyoung.muyon.product.ui.shell.ConversationShell
import com.mightyoung.muyon.product.ui.shell.ConversationHeader
import com.mightyoung.muyon.product.ui.shell.ShellConversation
import androidx.compose.runtime.saveable.rememberSaveableStateHolder

class MainActivity : ComponentActivity() {
    private lateinit var client: ProductClient
    private lateinit var readerSurface: ActivityReaderSurface
    private var readerProject by mutableStateOf<String?>(null)
    private val readerProjectListener = SharedPreferences.OnSharedPreferenceChangeListener { preferences, key ->
        if (key == "project_id" && ::readerSurface.isInitialized) {
            readerProject = preferences.getString("project_id", null)
            readerSurface.projectChanged(readerProject)
        }
    }
    private val configurationDrafts by lazy { ViewModelProvider(this)[ShellConfigurationState::class.java] }
    private var connected by mutableStateOf(false)
    private var initialized by mutableStateOf(false)
    private var workspaceId by mutableStateOf<String?>(null)
    private var existing by mutableStateOf(false)
    private var status by mutableStateOf("正在连接本地内核")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        readerSurface = ActivityReaderSurface.attach(this)
        readerProject = getSharedPreferences("muyon_product_research_v2", 0).getString("project_id", null)
        readerSurface.projectChanged(readerProject)
        getSharedPreferences("muyon_product_research_v2", 0).registerOnSharedPreferenceChangeListener(readerProjectListener)
        client = ProductClient(this) { ready ->
            connected = ready
            if (ready) { existing = client.workspaceExists; client.call("health") { reply ->
                initialized = reply.optString("status") == "ok"
                workspaceId = if (initialized) (reply.optJSONObject("data")?.opt("workspace") as? String)?.takeIf { it.isNotBlank() } else null
                readerSurface.bindActualWorkspace(workspaceId)
                status = if (initialized) "本地工作台已连接" else if (existing) "工作台暂不可用，请重试连接" else "请创建新工作台"
            } } else { initialized = false; workspaceId = null; readerSurface.connectionLost(); status = "连接已断开；未确认的操作请查询原结果" }
        }
        setContent {
            FoundationTheme {
                var tab by rememberSaveable { mutableStateOf("chat") }
                var conversationKey by rememberSaveable { mutableStateOf("default") }
                var conversationTitle by rememberSaveable { mutableStateOf("Muyon 助手") }
                var memberNames by rememberSaveable { mutableStateOf(arrayListOf<String>()) }
                fun navigate(destination: String) {
                    if (tab == "documents" && destination != "documents") readerSurface.leaveForNavigation()
                    tab = destination
                }
                var navigationError by remember { mutableStateOf("") }
                val shellPreferences = remember { getSharedPreferences("muyon_ui_shell_v1", 0) }
                var shellRevision by remember { mutableIntStateOf(0) }
                val stateHolder = rememberSaveableStateHolder()
                // Re-read only committed local identities; a broken catalog is never overwritten.
                val conversations = remember(tab, conversationKey, shellRevision) {
                    val opened = shellPreferences.getStringSet("opened", emptySet()).orEmpty()
                    val pinned = shellPreferences.getStringSet("pinned", emptySet()).orEmpty()
                    val catalog = try { AgentCatalog(this@MainActivity).read() } catch (_: Exception) { null }
                    listOf(ShellConversation("default", "Muyon 助手", main = true)) +
                        catalog?.agents.orEmpty().filter { !it.archived && "agent:${it.id}" in opened }.map {
                            ShellConversation("agent:${it.id}", visibleName(it.name, "未命名智能体"), pinned = "agent:${it.id}" in pinned)
                        } + catalog?.groups.orEmpty().filter { !it.archived && "group:${it.id}" in opened }.map {
                            ShellConversation("group:${it.id}", visibleName(it.name, "未命名群组"), pinned = "group:${it.id}" in pinned, group = true)
                        }
                }
                fun rememberOpened(key: String) {
                    val opened = shellPreferences.getStringSet("opened", emptySet()).orEmpty() + key
                    if (!shellPreferences.edit().putStringSet("opened", opened).commit()) {
                        navigationError = "会话菜单保存失败；对话身份未更改。"
                    }
                    shellRevision++
                }
                val title = when (tab) {
                    "supplier" -> "供应商管理"
                    "research" -> "研究空间"
                    "agents" -> "智能体与群组"
                    "configuration" -> "配置预览"
                    "documents" -> "公共文档"
                    else -> conversationTitle
                }
                ConversationShell(tab, title, conversationKey, conversations,
                    onSelectDestination = { navigate(it) },
                    onSelectConversation = { key ->
                        try {
                            val catalog = if (key == "default") null else AgentCatalog(this@MainActivity).read()
                            when {
                                key == "default" -> { conversationTitle = "Muyon 助手"; memberNames = arrayListOf() }
                                key.startsWith("agent:") -> {
                                    val agent = requireNotNull(catalog).agents.single { "agent:${it.id}" == key && !it.archived }
                                    conversationTitle = visibleName(agent.name, "未命名智能体"); memberNames = arrayListOf()
                                }
                                else -> {
                                    val group = requireNotNull(catalog).groups.single { "group:${it.id}" == key && !it.archived }
                                    conversationTitle = visibleName(group.name, "未命名群组")
                                    memberNames = ArrayList(group.members.map { id -> visibleName(catalog.agents.single { it.id == id && !it.archived }.name, "未命名智能体") })
                                }
                            }
                            conversationKey = key; navigationError = ""; navigate("chat")
                        } catch (_: Exception) { navigationError = "会话身份暂不可用，请返回目录核实。" }
                    },
                    notice = navigationError,
                    onTogglePin = { key ->
                        val pins = shellPreferences.getStringSet("pinned", emptySet()).orEmpty()
                        val next = if (key in pins) pins - key else pins + key
                        if (shellPreferences.edit().putStringSet("pinned", next).commit()) {
                            shellRevision++
                            if (navigationError == "置顶状态未能保存，请重试。") navigationError = ""
                        } else navigationError = "置顶状态未能保存，请重试。"
                    }) { openMenu ->
                    Column(Modifier.fillMaxSize()) {
                        if (tab == "chat" && (!connected || !initialized)) ConversationHeader(title, openMenu, mainAgent = conversationKey == "default")
                        if (!connected || !initialized) {
                            Text(status, Modifier.padding(24.dp), style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        if (!connected) TextButton(onClick = { recreate() }) { Text("重试连接") }
                        if (connected && !initialized) Button(onClick = {
                            client.call(if (existing) "health" else "initialize") { reply ->
                                initialized = reply.optString("status") == "ok"
                                workspaceId = if (initialized) (reply.optJSONObject("data")?.opt("workspace") as? String)?.takeIf { it.isNotBlank() } else null
                                readerSurface.bindActualWorkspace(workspaceId)
                                if (initialized) existing = true
                                status = if (initialized) "本地工作台已连接" else reply.optString("error")
                            }
                        }) { Text(if (existing) "重试连接" else "创建新工作台") }
                        if (navigationError.isNotEmpty()) Text(navigationError, Modifier.padding(16.dp), color = MaterialTheme.colorScheme.error)
                        if (connected && initialized) {
                            stateHolder.SaveableStateProvider("$tab:$conversationKey") {
                            when (tab) {
                                "supplier" -> SupplierScreen(client)
                                "research" -> ResearchScreen(client)
                                "documents" -> DocumentCapabilitiesScreen(readerSurface, readerProject) { navigate("research") }
                                "configuration" -> {
                                    val project = getSharedPreferences("muyon_product_research_v2", 0).getString("project_id", null)
                                    val preference = if (conversationKey == "default") "conversation" else "conversation:$conversationKey"
                                    val conversation = getSharedPreferences("product-chat-state", 0).getString(preference, null)?.takeIf { it.isNotBlank() }
                                    val workspace = workspaceId
                                    if (workspace == null || conversation == null) {
                                        Text("配置草稿缺少已核实的工作台或会话身份，请先打开对应对话。", Modifier.padding(20.dp))
                                        TextButton(onClick = { navigate("chat") }) { Text("返回对话") }
                                    } else {
                                        val scope = configurationBufferScope(workspace, conversation, project)
                                        ConfigurationPreviewHost(configurationDrafts.forScope(scope), client, workspace, conversation, project) { navigate("agents") }
                                    }
                                }
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
                                        navigationError = ""
                                        rememberOpened(conversationKey)
                                        navigate("chat")
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
                                            ConversationHeader(conversationTitle, openMenu)
                                            Text("智能体配置暂不可用，请返回目录核实后重新打开对话。")
                                            TextButton(onClick = { navigate("agents") }) { Text("返回智能体目录") }
                                        }
                                    } else ChatScreen(client,
                                    getSharedPreferences("muyon_product_research_v2", 0).getString("project_id", null),
                                    conversationKey, conversationTitle, memberNames,
                                    selectedAgent?.role.orEmpty(), selectedAgent?.instructions.orEmpty(), openMenu)
                                }
                            }
                            }
                        }
                    }
                }
            }
        }
        client.bind()
    }
    override fun onPause() {
        if (::readerSurface.isInitialized) readerSurface.pausing()
        super.onPause()
    }
    override fun onStop() {
        if (::readerSurface.isInitialized) readerSurface.stopping()
        super.onStop()
    }
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (::readerSurface.isInitialized) readerSurface.windowChanged()
    }
    override fun onMultiWindowModeChanged(isInMultiWindowMode: Boolean, newConfig: Configuration) {
        super.onMultiWindowModeChanged(isInMultiWindowMode, newConfig)
        if (::readerSurface.isInitialized) readerSurface.windowChanged()
    }
    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (::readerSurface.isInitialized) readerSurface.windowChanged()
    }
    override fun onDestroy() {
        if (::readerSurface.isInitialized) readerSurface.destroy()
        getSharedPreferences("muyon_product_research_v2", 0).unregisterOnSharedPreferenceChangeListener(readerProjectListener)
        client.close()
        super.onDestroy()
    }
}
