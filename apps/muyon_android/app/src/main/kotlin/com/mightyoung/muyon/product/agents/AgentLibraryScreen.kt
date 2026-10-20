package com.mightyoung.muyon.product.agents

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.mightyoung.muyon.product.R
import java.util.UUID

private val Ink: Color
    @Composable get() = MaterialTheme.colorScheme.onSurface
private val SecondaryInk: Color
    @Composable get() = MaterialTheme.colorScheme.onSurfaceVariant
private val CanvasColor: Color
    @Composable get() = MaterialTheme.colorScheme.background
private val QuietSurface: Color
    @Composable get() = MaterialTheme.colorScheme.surfaceVariant
private val DividerColor: Color
    @Composable get() = MaterialTheme.colorScheme.outlineVariant
private val ActionBlue: Color
    @Composable get() = MaterialTheme.colorScheme.primary

@OptIn(ExperimentalLayoutApi::class)
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
    fun close() { agentDraft = null; groupDraft = null; detailAgent = null; detailGroup = null; step = 0 }
    fun write(action: () -> Unit) {
        try { action(); reload(); close() }
        catch (failure: Exception) { error = failure.message ?: "保存失败" }
    }
    LaunchedEffect(catalog) { reload() }
    BackHandler(agentDraft != null || groupDraft != null || detailAgent != null || detailGroup != null) { close() }
    Box(Modifier.fillMaxSize().background(CanvasColor), contentAlignment = Alignment.TopCenter) {
        BoxWithConstraints(Modifier.widthIn(max = 1152.dp).fillMaxWidth().verticalScroll(rememberScrollState()).padding(20.dp)) {
            val columns = if (maxWidth >= 720.dp) 2 else 1
            Column(verticalArrangement = Arrangement.spacedBy(24.dp)) {
                error?.let {
                    Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("agent_catalog_error"))
                    TextButton(onClick = { reload() }) { Text("重新读取") }
                }
                if (!readable) return@Column
                val activeAgents = snapshot.agents.filterNot { it.archived }
                val agent = agentDraft
                val group = groupDraft
                when {
                    agent != null -> {
                        EditorHeader(if (snapshot.agents.any { it.id == agent.id }) "编辑智能体" else "创建智能体", step, ::close)
                        FormPanel {
                            when (step) {
                                0 -> {
                                    Avatar(agent, Modifier.size(64.dp))
                                    QuietField(agent.name, { agentDraft = agent.copy(name = it) }, "名称", "agent_name")
                                    QuietField(agent.role, { agentDraft = agent.copy(role = it) }, "身份与职责", "agent_role", minLines = 2)
                                    Text("头像", style = MaterialTheme.typography.labelLarge, color = SecondaryInk)
                                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                        listOf("✦", "◈", "✺", "◎").forEach { glyph ->
                                            val selected = agent.avatar == glyph
                                            Box(Modifier.size(48.dp).clip(RoundedCornerShape(12.dp)).background(if (selected) MaterialTheme.colorScheme.surface else QuietSurface)
                                                .border(1.dp, if (selected) ActionBlue else Color.Transparent, RoundedCornerShape(12.dp))
                                                .clickable { agentDraft = agent.copy(avatar = glyph) }.semantics { contentDescription = "头像 $glyph" }, contentAlignment = Alignment.Center) {
                                                if (glyph == "✦") Image(painterResource(R.drawable.muyon_avatar), null, Modifier.size(32.dp)) else Text(glyph, color = Ink)
                                            }
                                        }
                                    }
                                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                        listOf("#7564D8", "#34866C", "#C37543", "#427BB8").forEach { accent ->
                                            Box(Modifier.size(48.dp).clip(CircleShape).clickable { agentDraft = agent.copy(accent = accent) }
                                                .semantics { contentDescription = "头像颜色 $accent${if (agent.accent == accent) "，已选中" else ""}" }.padding(8.dp)
                                                .background(Color(android.graphics.Color.parseColor(accent)), CircleShape)
                                                .border(if (agent.accent == accent) 2.dp else 0.dp, Ink, CircleShape))
                                        }
                                    }
                                }
                                1 -> QuietField(agent.instructions, { agentDraft = agent.copy(instructions = it) }, "指令", "agent_instructions", 8)
                                else -> {
                                    IdentityReview(agent)
                                    Text("本地角色配置；保存不会连接模型或启动任务。", color = SecondaryInk, style = MaterialTheme.typography.bodySmall)
                                }
                            }
                            EditorActions(step, { step-- }, { if (step < 2) step++ else write { catalog.saveAgent(agent) } },
                                agent.name.isNotBlank() && agent.name.length <= 60 && agent.role.isNotBlank() && agent.role.length <= 160 && agent.instructions.length <= 8000, "agent_next")
                        }
                    }
                    group != null -> {
                        EditorHeader("${if (snapshot.groups.any { it.id == group.id }) "编辑" else "创建"}群组", step, ::close)
                        FormPanel {
                            when (step) {
                                0 -> QuietField(group.name, { groupDraft = group.copy(name = it) }, "群组名称", "group_name")
                                1 -> {
                                    Text("成员 · ${group.members.size}/20", style = MaterialTheme.typography.titleMedium, color = Ink)
                                    if (activeAgents.isEmpty()) Text("请先创建智能体。", color = SecondaryInk)
                                    activeAgents.forEach { member ->
                                        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(QuietSurface).clickable {
                                            groupDraft = group.copy(members = if (member.id in group.members) group.members - member.id else group.members + member.id)
                                        }.padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                            Avatar(member)
                                            Column(Modifier.weight(1f)) { Text(member.name, color = Ink); Text(member.role, color = SecondaryInk, style = MaterialTheme.typography.bodySmall, maxLines = 2, overflow = TextOverflow.Ellipsis) }
                                            Checkbox(member.id in group.members, { checked -> groupDraft = group.copy(members = if (checked) (group.members + member.id).distinct() else group.members - member.id) },
                                                colors = CheckboxDefaults.colors(checkedColor = ActionBlue), modifier = Modifier.semantics { contentDescription = "选择成员 ${member.name}" })
                                        }
                                    }
                                }
                                else -> {
                                    CatalogCard { Text(group.name, style = MaterialTheme.typography.headlineSmall, color = Ink); GroupMembers(group, snapshot) }
                                    Text("群组仅组织角色与会话，不会自动执行多智能体任务。", color = SecondaryInk, style = MaterialTheme.typography.bodySmall)
                                }
                            }
                            EditorActions(step, { step-- }, { if (step < 2) step++ else write { catalog.saveGroup(group) } },
                                group.name.isNotBlank() && group.name.length <= 60 && (step == 0 || group.members.size in 1..20), "group_next")
                        }
                    }
                    detailAgent != null -> {
                        TextButton({ close() }) { Text("返回目录", color = SecondaryInk) }
                        snapshot.agents.firstOrNull { it.id == detailAgent }?.let { selected ->
                            FormPanel {
                                IdentityReview(selected)
                                if (!selected.archived) {
                                    PrimaryAction("打开对话", { onOpenChat(selected.id, null) })
                                    OutlinedButton({ agentDraft = selected; step = 0 }, shape = CircleShape) { Text("编辑智能体", color = Ink) }
                                    TextButton({ write { catalog.archiveAgent(selected.id) } }) { Text("归档智能体", color = SecondaryInk) }
                                } else PrimaryAction("恢复智能体", { write { catalog.saveAgent(selected.copy(archived = false)) } })
                            }
                        }
                    }
                    detailGroup != null -> {
                        TextButton({ close() }) { Text("返回目录", color = SecondaryInk) }
                        snapshot.groups.firstOrNull { it.id == detailGroup }?.let { selected ->
                            FormPanel {
                                CatalogCard { Text(selected.name, style = MaterialTheme.typography.headlineSmall, color = Ink); GroupMembers(selected, snapshot) }
                                if (!selected.archived) {
                                    PrimaryAction("打开群组会话", { onOpenChat(null, selected.id) })
                                    OutlinedButton({ groupDraft = selected; step = 0 }, shape = CircleShape) { Text("编辑群组与成员", color = Ink) }
                                    TextButton({ write { catalog.archiveGroup(selected.id) } }) { Text("归档群组", color = SecondaryInk) }
                                } else PrimaryAction("恢复群组", { write { catalog.saveGroup(selected.copy(archived = false)) } })
                            }
                        }
                    }
                    else -> {
                        FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text(if (groupsTab) "群组" else "智能体", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.SemiBold, color = Ink)
                            PrimaryAction(if (groupsTab) "＋ 创建群组" else "＋ 创建智能体", {
                                step = 0
                                if (groupsTab) groupDraft = AgentGroup(UUID.randomUUID().toString(), "", emptyList())
                                else agentDraft = AgentProfile(UUID.randomUUID().toString(), "", "", "")
                            }, modifier = Modifier.testTag("catalog_create"))
                        }
                        FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            FlowRow(Modifier.clip(CircleShape).background(QuietSurface).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Segment("智能体", !groupsTab) { groupsTab = false }
                                Segment("群组", groupsTab) { groupsTab = true }
                            }
                            Segment("已归档", archived) { archived = !archived }
                        }
                        if (groupsTab) {
                            val groups = snapshot.groups.filter { it.archived == archived }
                            if (groups.isEmpty()) EmptyCatalog("还没有${if (archived) "归档" else ""}群组")
                            CatalogGrid(groups, columns) { item ->
                                CatalogCard(Modifier.heightIn(min = 256.dp).clickable { detailGroup = item.id }.testTag("group_card_${item.id}")) {
                                    Row(Modifier.heightIn(min = 80.dp), verticalAlignment = Alignment.Top) {
                                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                            Text(item.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, color = Ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                            Text("${item.members.size} 位成员", style = MaterialTheme.typography.bodyMedium, color = SecondaryInk)
                                        }
                                        Chevron()
                                    }
                                    GroupMembers(item, snapshot)
                                }
                            }
                        } else {
                            val agents = snapshot.agents.filter { it.archived == archived }
                            if (agents.isEmpty()) EmptyCatalog("还没有${if (archived) "归档" else ""}智能体")
                            CatalogGrid(agents, columns) { item ->
                                CatalogCard(Modifier.heightIn(min = 256.dp).clickable { detailAgent = item.id }.testTag("agent_card_${item.id}")) {
                                    Row(Modifier.heightIn(min = 80.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
                                        Avatar(item)
                                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                            Text(item.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, color = Ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                            Text(item.role, style = MaterialTheme.typography.bodyMedium, color = SecondaryInk, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                        }
                                        Chevron()
                                    }
                                    if (item.instructions.isNotBlank()) Text(item.instructions, style = MaterialTheme.typography.bodyMedium, color = SecondaryInk, maxLines = 4, overflow = TextOverflow.Ellipsis)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun <T> CatalogGrid(items: List<T>, columns: Int, content: @Composable (T) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        items.chunked(columns).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                row.forEach { item -> Box(Modifier.weight(1f)) { content(item) } }
                repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun EditorHeader(title: String, step: Int, onCancel: () -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold, color = Ink)
        TextButton(onCancel) { Text("取消", color = SecondaryInk) }
    }
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        listOf("简介", "定义", "检查").forEachIndexed { index, label ->
            Text("${index + 1}  $label", Modifier.clip(CircleShape).background(if (index == step) QuietSurface else Color.Transparent).padding(horizontal = 14.dp, vertical = 10.dp),
                color = if (index == step) Ink else SecondaryInk, style = MaterialTheme.typography.labelLarge)
        }
    }
}

@Composable
private fun FormPanel(content: @Composable ColumnScope.() -> Unit) {
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.widthIn(max = 640.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(20.dp), content = content)
    }
}

@Composable
private fun QuietField(value: String, onChange: (String) -> Unit, label: String, tag: String, minLines: Int = 1) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(label, style = MaterialTheme.typography.labelLarge, color = Ink)
        OutlinedTextField(value, onChange, modifier = Modifier.fillMaxWidth().testTag(tag).semantics { contentDescription = label }, minLines = minLines,
            shape = RoundedCornerShape(12.dp), colors = OutlinedTextFieldDefaults.colors(
                focusedContainerColor = QuietSurface, unfocusedContainerColor = QuietSurface,
                focusedBorderColor = ActionBlue, unfocusedBorderColor = DividerColor, focusedTextColor = Ink, unfocusedTextColor = Ink,
                cursorColor = ActionBlue))
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun EditorActions(step: Int, onBack: () -> Unit, onNext: () -> Unit, enabled: Boolean, tag: String) {
    FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.End), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (step > 0) TextButton(onBack) { Text("上一步", color = SecondaryInk) }
        PrimaryAction(if (step == 2) "确认保存" else "下一步", onNext, enabled, Modifier.testTag(tag))
    }
}

@Composable
private fun PrimaryAction(text: String, onClick: () -> Unit, enabled: Boolean = true, modifier: Modifier = Modifier) {
    Button(onClick, modifier.heightIn(min = 48.dp), enabled = enabled, shape = CircleShape,
        colors = ButtonDefaults.buttonColors(containerColor = ActionBlue, contentColor = MaterialTheme.colorScheme.onPrimary), contentPadding = PaddingValues(horizontal = 20.dp, vertical = 12.dp)) { Text(text) }
}

@Composable
private fun Segment(label: String, selected: Boolean, onClick: () -> Unit) {
    TextButton(onClick, Modifier.heightIn(min = 48.dp), shape = CircleShape, colors = ButtonDefaults.textButtonColors(containerColor = if (selected) MaterialTheme.colorScheme.surface else Color.Transparent, contentColor = if (selected) Ink else SecondaryInk),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp)) { Text(label) }
}

@Composable
private fun CatalogCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(MaterialTheme.colorScheme.surface).border(1.dp, DividerColor, RoundedCornerShape(16.dp)).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp), content = content)
}

@Composable
private fun IdentityReview(agent: AgentProfile) {
    CatalogCard {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Avatar(agent, Modifier.size(56.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(agent.name, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, color = Ink)
                Text(agent.role, color = SecondaryInk)
            }
        }
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(QuietSurface).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("指令", style = MaterialTheme.typography.labelLarge, color = SecondaryInk)
            Text(agent.instructions.ifBlank { "未设置额外指令" }, color = Ink, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
private fun Avatar(agent: AgentProfile, modifier: Modifier = Modifier.size(48.dp)) {
    Box(modifier.clip(RoundedCornerShape(12.dp)).background(Color(android.graphics.Color.parseColor(agent.accent)).copy(alpha = .12f))
        .semantics { contentDescription = "${agent.name.ifBlank { "智能体" }}的头像" }, contentAlignment = Alignment.Center) {
        if (agent.avatar == "✦") Image(painterResource(R.drawable.muyon_avatar), null, Modifier.fillMaxSize().padding(5.dp))
        else Text(agent.avatar, color = Color(android.graphics.Color.parseColor(agent.accent)), style = MaterialTheme.typography.titleLarge)
    }
}

@Composable
private fun GroupMembers(group: AgentGroup, snapshot: CatalogSnapshot) {
    Row(horizontalArrangement = Arrangement.spacedBy((-10).dp), modifier = Modifier.semantics { contentDescription = "群组组合头像，${group.members.size} 位成员" }) {
        group.members.take(4).forEach { id -> snapshot.agents.find { it.id == id }?.let { Avatar(it) } }
    }
    group.members.chunked(3).forEach { row ->
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            row.forEach { id -> snapshot.agents.find { it.id == id }?.let { member ->
                Surface(Modifier.weight(1f), shape = RoundedCornerShape(8.dp), color = QuietSurface) {
                    Text(member.name, Modifier.padding(8.dp), color = SecondaryInk, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.labelMedium)
                }
            } }
        }
    }
}

@Composable
private fun Chevron() {
    val color = SecondaryInk
    Canvas(Modifier.size(20.dp).padding(4.dp)) {
        drawLine(color, Offset(size.width * .3f, 0f), Offset(size.width * .8f, size.height * .5f), strokeWidth = 1.5.dp.toPx())
        drawLine(color, Offset(size.width * .8f, size.height * .5f), Offset(size.width * .3f, size.height), strokeWidth = 1.5.dp.toPx())
    }
}

@Composable
private fun EmptyCatalog(title: String) {
    CatalogCard(Modifier.heightIn(min = 256.dp)) {
        Image(painterResource(R.drawable.muyon_avatar), null, Modifier.size(64.dp))
        Text(title, style = MaterialTheme.typography.titleMedium, color = SecondaryInk)
    }
}
