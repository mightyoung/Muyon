package com.mightyoung.muyon.product.agents

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import com.mightyoung.muyon.product.R
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import java.util.UUID

@Composable
fun AgentLibraryScreen(onOpenChat: (agentId: String?, groupId: String?) -> Unit) {
    val context = LocalContext.current
    val catalog = remember { AgentCatalog(context) }
    var snapshot by remember { mutableStateOf(CatalogSnapshot(emptyList(), emptyList())) }
    var error by remember { mutableStateOf<String?>(null) }
    var readable by remember { mutableStateOf(false) }
    var groupsTab by remember { mutableStateOf(false) }
    var agentDraft by remember { mutableStateOf<AgentProfile?>(null) }
    var groupDraft by remember { mutableStateOf<AgentGroup?>(null) }
    var detailAgent by remember { mutableStateOf<String?>(null) }
    var detailGroup by remember { mutableStateOf<String?>(null) }
    var archived by remember { mutableStateOf(false) }
    var step by remember { mutableIntStateOf(0) }
    fun reload() {
        try { snapshot = catalog.read(); readable = true; error = null }
        catch (failure: Exception) { error = failure.message; readable = false }
    }
    fun write(action: () -> Unit) {
        try { action(); reload(); agentDraft = null; groupDraft = null; detailAgent = null; detailGroup = null; step = 0 }
        catch (failure: Exception) { error = failure.message ?: "保存失败" }
    }
    LaunchedEffect(catalog) { reload() }
    BackHandler(agentDraft != null || groupDraft != null || detailAgent != null || detailGroup != null) {
        agentDraft = null; groupDraft = null; detailAgent = null; detailGroup = null; step = 0
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("你的智能体", style = MaterialTheme.typography.headlineMedium)
        Text("独立角色，有序协作", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        error?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("agent_catalog_error")); TextButton(onClick = { reload() }) { Text("重新读取") } }
        if (!readable) return@Column
        val activeAgents = snapshot.agents.filterNot { it.archived }
        if (agentDraft != null) {
            val draft = requireNotNull(agentDraft)
            EditorHeader("${if (snapshot.agents.any { it.id == draft.id }) "编辑" else "创建"}智能体", step) { agentDraft = null; step = 0 }
            if (step == 0) {
                Avatar(draft)
                OutlinedTextField(draft.name, { agentDraft = draft.copy(name = it) }, label = { Text("名称 · 最多 60 字") }, modifier = Modifier.fillMaxWidth().testTag("agent_name"))
                OutlinedTextField(draft.role, { agentDraft = draft.copy(role = it) }, label = { Text("身份与职责 · 最多 160 字") }, modifier = Modifier.fillMaxWidth().testTag("agent_role"))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("✦", "◈", "✺", "◎").forEach { glyph -> FilterChip(draft.avatar == glyph, { agentDraft = draft.copy(avatar = glyph) }, label = { Text(glyph) }, modifier = Modifier.semantics { contentDescription = "头像 $glyph" }) }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("#7564D8", "#34866C", "#C37543", "#427BB8").forEach { accent ->
                        val selected = draft.accent == accent
                        Box(Modifier.size(48.dp).padding(5.dp).background(Color(android.graphics.Color.parseColor(accent)), CircleShape)
                            .border(if (selected) 3.dp else 0.dp, MaterialTheme.colorScheme.onSurface, CircleShape)
                            .clickable { agentDraft = draft.copy(accent = accent) }.semantics { contentDescription = "头像颜色 $accent${if (selected) "，已选中" else ""}" })
                    }
                }
            } else if (step == 1) {
                Text("定义这个角色如何思考与回应。保存的指令仅为角色配置。")
                OutlinedTextField(draft.instructions, { agentDraft = draft.copy(instructions = it) }, label = { Text("独立指令 · 最多 8000 字") }, minLines = 6, modifier = Modifier.fillMaxWidth().testTag("agent_instructions"))
            } else {
                CatalogCard { Avatar(draft); Text(draft.name, style = MaterialTheme.typography.titleLarge); Text(draft.role); HorizontalDivider(); Text(draft.instructions.ifBlank { "未设置额外指令" }) }
                Text("本地角色配置；保存不会连接模型或启动任务。", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (step > 0) OutlinedButton({ step-- }) { Text("上一步") }
                Button({ if (step < 2) step++ else write { catalog.saveAgent(draft) } }, enabled = draft.name.isNotBlank() && draft.name.length <= 60 && draft.role.isNotBlank() && draft.role.length <= 160 && draft.instructions.length <= 8000, modifier = Modifier.testTag("agent_next")) { Text(if (step == 2) "确认保存" else "下一步") }
            }
        } else if (groupDraft != null) {
            val draft = requireNotNull(groupDraft)
            EditorHeader("组织群组", step) { groupDraft = null; step = 0 }
            if (step < 2) {
                OutlinedTextField(draft.name, { groupDraft = draft.copy(name = it) }, label = { Text("群组名称 · 最多 60 字") }, modifier = Modifier.fillMaxWidth().testTag("group_name"))
                Text("选择成员 · ${draft.members.size}/20")
                if (activeAgents.isEmpty()) Text("请先创建智能体，再组织群组。")
                activeAgents.forEach { agent ->
                    Row(Modifier.fillMaxWidth().clickable { groupDraft = draft.copy(members = if (agent.id in draft.members) draft.members - agent.id else draft.members + agent.id) }.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(agent.id in draft.members, { checked -> groupDraft = draft.copy(members = if (checked) (draft.members + agent.id).distinct() else draft.members - agent.id) }, modifier = Modifier.semantics { contentDescription = "选择成员 ${agent.name}" })
                        Avatar(agent); Spacer(Modifier.width(12.dp)); Text(agent.name)
                    }
                }
            } else {
                CatalogCard { Text(draft.name, style = MaterialTheme.typography.titleLarge); GroupMembers(draft, snapshot) }
            }
            Text("群组只用于组织角色和会话，不会自动执行多智能体任务，也不会新增网络请求。", color = MaterialTheme.colorScheme.onSurfaceVariant)
            Button({ if (step < 2) step = 2 else write { catalog.saveGroup(draft) } }, enabled = draft.name.isNotBlank() && draft.name.length <= 60 && draft.members.size in 1..20, modifier = Modifier.testTag("group_next")) { Text(if (step == 2) "确认保存" else "预览群组") }
            if (step == 2) TextButton({ step = 0 }) { Text("返回修改") }
        } else if (detailAgent != null) {
            val agent = snapshot.agents.firstOrNull { it.id == detailAgent }
            TextButton({ detailAgent = null }) { Text("返回目录") }
            agent?.let {
                CatalogCard { Avatar(it); Text(it.name, style = MaterialTheme.typography.headlineSmall); Text(it.role); HorizontalDivider(); Text("独立指令", style = MaterialTheme.typography.labelLarge); Text(it.instructions.ifBlank { "未设置额外指令" }) }
                Text("本地角色 · 未声明模型连接")
                if (!it.archived) {
                    Button({ onOpenChat(it.id, null) }) { Text("打开对话") }
                    OutlinedButton({ agentDraft = it; step = 0 }) { Text("编辑智能体") }
                    TextButton({ write { catalog.archiveAgent(it.id) } }) { Text("归档智能体") }
                } else Button({ write { catalog.saveAgent(it.copy(archived = false)) } }) { Text("恢复智能体") }
            }
        } else if (detailGroup != null) {
            val group = snapshot.groups.firstOrNull { it.id == detailGroup }
            TextButton({ detailGroup = null }) { Text("返回目录") }
            group?.let {
                CatalogCard { Text(it.name, style = MaterialTheme.typography.headlineSmall); GroupMembers(it, snapshot) }
                Text("角色组织会话；成员不会自动轮流执行。归档群组不删除智能体或聊天。")
                if (!it.archived) {
                    Button({ onOpenChat(null, it.id) }) { Text("打开群组会话") }
                    OutlinedButton({ groupDraft = it; step = 0 }) { Text("编辑群组与成员") }
                    TextButton({ write { catalog.archiveGroup(it.id) } }) { Text("归档群组") }
                } else Button({ write { catalog.saveGroup(it.copy(archived = false)) } }) { Text("恢复群组") }
            }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(!groupsTab, { groupsTab = false }, { Text("智能体") })
                FilterChip(groupsTab, { groupsTab = true }, { Text("群组") })
                FilterChip(archived, { archived = !archived }, { Text("已归档") })
            }
            Button({ step = 0; if (groupsTab) groupDraft = AgentGroup(UUID.randomUUID().toString(), "", emptyList()) else agentDraft = AgentProfile(UUID.randomUUID().toString(), "", "", "") }, modifier = Modifier.testTag("catalog_create")) { Text(if (groupsTab) "＋ 创建群组" else "＋ 创建智能体") }
            if (groupsTab) {
                val groups = snapshot.groups.filter { it.archived == archived }
                if (groups.isEmpty()) EmptyCatalog("还没有${if (archived) "归档" else ""}群组", "把不同角色组织在一起，保留各自身份与指令。")
                groups.forEach { group -> CatalogCard(Modifier.clickable { detailGroup = group.id }.testTag("group_card_${group.id}")) { Text(group.name, style = MaterialTheme.typography.titleMedium); GroupMembers(group, snapshot) } }
            } else {
                val agents = snapshot.agents.filter { it.archived == archived }
                if (agents.isEmpty()) EmptyCatalog("还没有${if (archived) "归档" else ""}智能体", "从一个清晰的身份和职责开始。")
                agents.forEach { agent -> CatalogCard(Modifier.clickable { detailAgent = agent.id }.testTag("agent_card_${agent.id}")) {
                    Row(verticalAlignment = Alignment.CenterVertically) { Avatar(agent); Spacer(Modifier.width(12.dp)); Column(Modifier.weight(1f)) { Text(agent.name, style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis); Text(agent.role, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 3, overflow = TextOverflow.Ellipsis) } }
                    Text("独立指令 · 本地角色", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                } }
            }
        }
    }
}

@Composable
private fun EditorHeader(title: String, step: Int, onCancel: () -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) { Text(title, style = MaterialTheme.typography.titleLarge); TextButton(onCancel) { Text("取消") } }
    Text(listOf("01  简介", "02  定义", "03  检查").mapIndexed { index, label -> if (index == step) "[$label]" else label }.joinToString("   ·   "), style = MaterialTheme.typography.labelLarge)
}

@Composable
private fun CatalogCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth().border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(16.dp)).background(MaterialTheme.colorScheme.surface, RoundedCornerShape(16.dp)).padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
}

@Composable
private fun Avatar(agent: AgentProfile) {
    Box(Modifier.size(44.dp).background(Color(android.graphics.Color.parseColor(agent.accent)).copy(alpha = .14f), RoundedCornerShape(14.dp)).semantics { contentDescription = "${agent.name.ifBlank { "智能体" }}的头像" }, contentAlignment = Alignment.Center) {
        Text(agent.avatar, color = Color(android.graphics.Color.parseColor(agent.accent)), style = MaterialTheme.typography.titleLarge)
    }
}

@Composable
private fun GroupMembers(group: AgentGroup, snapshot: CatalogSnapshot) {
    Row(horizontalArrangement = Arrangement.spacedBy((-10).dp), modifier = Modifier.semantics { contentDescription = "群组组合头像，${group.members.size} 位成员" }) { group.members.take(4).forEach { id -> snapshot.agents.find { it.id == id }?.let { Avatar(it) } } }
    group.members.chunked(3).forEach { row ->
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            row.forEach { id ->
                snapshot.agents.find { it.id == id }?.let { agent ->
                    Surface(Modifier.weight(1f), shape = RoundedCornerShape(8.dp), color = MaterialTheme.colorScheme.surfaceVariant) {
                        Text(agent.name, Modifier.padding(8.dp), maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.labelMedium)
                    }
                }
            }
        }
    }
}

@Composable
private fun EmptyCatalog(title: String, description: String) {
    CatalogCard { Image(painterResource(R.drawable.muyon_avatar), null, Modifier.size(64.dp)); Text(title, style = MaterialTheme.typography.titleMedium); Text(description, color = MaterialTheme.colorScheme.onSurfaceVariant) }
}
