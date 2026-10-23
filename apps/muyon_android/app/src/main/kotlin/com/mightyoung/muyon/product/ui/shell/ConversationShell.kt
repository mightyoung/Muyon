package com.mightyoung.muyon.product.ui.shell

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.mightyoung.muyon.product.R

/** Entries are opened local conversation identities, never invented transcript history. */
data class ShellConversation(
    val key: String, val title: String, val main: Boolean = false,
    val pinned: Boolean = false, val group: Boolean = false,
)

@Composable
fun ConversationShell(
    destination: String,
    title: String,
    selectedConversation: String,
    conversations: List<ShellConversation>,
    onSelectDestination: (String) -> Unit,
    onSelectConversation: (String) -> Unit,
    onTogglePin: (String) -> Unit,
    notice: String = "",
    content: @Composable (openMenu: () -> Unit) -> Unit,
) {
    var menuOpen by rememberSaveable { mutableStateOf(false) }
    val keyboard = LocalSoftwareKeyboardController.current
    val openMenu = { keyboard?.hide(); menuOpen = true }
    BackHandler(menuOpen) { menuOpen = false }
    BoxWithConstraints(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        val menuWidth = maxWidth * .78f
        Column(Modifier.fillMaxSize().safeDrawingPadding()
            .then(if (menuOpen) Modifier.clearAndSetSemantics {} else Modifier)) {
            if (destination != "chat") ConversationHeader(title, openMenu)
            Box(Modifier.weight(1f).fillMaxWidth()) { content(openMenu) }
        }
        if (menuOpen) Dialog(onDismissRequest = { menuOpen = false },
            properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
            Box(Modifier.fillMaxSize()) {
                // A separate modal window also prevents keyboard focus entering the body.
                // Full overlay intercepts touches; body remains composed to retain live state.
                Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.scrim.copy(alpha = .42f))
                    .clickable(onClickLabel = "关闭菜单") { menuOpen = false })
                Surface(Modifier.width(menuWidth).fillMaxHeight().testTag("shell-menu")
                    .semantics { paneTitle = "工作空间导航" }, color = MaterialTheme.colorScheme.background, contentColor = MaterialTheme.colorScheme.onBackground) {
                    Column(Modifier.safeDrawingPadding().verticalScroll(rememberScrollState()).padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Image(painterResource(R.drawable.muyon_brand_icon), contentDescription = null,
                                modifier = Modifier.size(40.dp).testTag("shell-original-brand-icon"), contentScale = ContentScale.Fit)
                            Text("Muyon", style = MaterialTheme.typography.headlineMedium)
                        }
                        if (notice.isNotBlank()) Text(notice, Modifier.padding(12.dp).semantics { liveRegion = LiveRegionMode.Polite }, color = MaterialTheme.colorScheme.error)
                        Text("主 Agent 与置顶", Modifier.padding(12.dp).semantics { heading() }, style = MaterialTheme.typography.titleSmall)
                        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            conversations.filter { it.main || it.pinned }.sortedBy { !it.main }.forEach { item ->
                                PinnedConversationCard(item, destination == "chat" && selectedConversation == item.key,
                                    { onSelectConversation(item.key); menuOpen = false }, { onTogglePin(item.key) })
                            }
                        }
                        HorizontalDivider(Modifier.padding(vertical = 8.dp))
                        Text("最近会话", Modifier.padding(12.dp).semantics { heading() }, style = MaterialTheme.typography.titleSmall)
                        val ordinary = conversations.filterNot { it.main || it.pinned }
                        if (ordinary.isEmpty()) Text("尚无其他已打开的会话", Modifier.padding(12.dp), style = MaterialTheme.typography.bodyMedium)
                        ordinary.forEach { item ->
                            ConversationEntry(item, destination == "chat" && selectedConversation == item.key,
                                { onSelectConversation(item.key); menuOpen = false }, { onTogglePin(item.key) })
                        }
                        HorizontalDivider(Modifier.padding(vertical = 8.dp))
                        listOf("agents" to "智能体与群组", "supplier" to "供应商", "research" to "科研工作台", "configuration" to "配置预览（未保存）", "documents" to "公共文档").forEach { (id, label) ->
                            TextButton(onClick = { onSelectDestination(id); menuOpen = false },
                                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("nav-$id")
                                    .semantics { selected = destination == id }) { Text(label) }
                        }
                    }
                }
                IconButton(onClick = { menuOpen = false }, modifier = Modifier.align(Alignment.TopEnd)
                    .statusBarsPadding().padding(4.dp).size(48.dp)) {
                    Surface(shape = RoundedCornerShape(24.dp), color = MaterialTheme.colorScheme.surface, contentColor = MaterialTheme.colorScheme.onSurface) {
                        Box(Modifier.size(48.dp), contentAlignment = Alignment.Center) {
                            Text("×", Modifier.semantics { contentDescription = "关闭菜单" }, style = MaterialTheme.typography.headlineSmall)
                        }
                    }
                }
            }
        }
    }
}

/** Only host-provided, already opened identities appear here. Pinning remains a host callback. */
@Composable
private fun PinnedConversationCard(item: ShellConversation, active: Boolean, onOpen: () -> Unit, onPin: () -> Unit) {
    Surface(color = if (active) MaterialTheme.colorScheme.surfaceVariant else MaterialTheme.colorScheme.surface,
        contentColor = MaterialTheme.colorScheme.onSurface, shape = RoundedCornerShape(20.dp)) {
        Column(Modifier.width(112.dp)) {
            Column(Modifier.fillMaxWidth().heightIn(min = 144.dp)
                .testTag(if (item.main) "nav-chat" else "shell-conversation-${item.key}")
                .semantics {
                    selected = active
                    contentDescription = "${item.title}，${if (active) "当前会话，" else ""}${if (item.main) "主 Agent" else "已置顶"}${if (item.group) "，群组，仅本地组织" else ""}"
                }.clickable(role = Role.Tab, onClick = onOpen).padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                if (item.main) Image(painterResource(R.drawable.muyon_brand_mascot_front), contentDescription = null,
                    modifier = Modifier.size(48.dp), contentScale = ContentScale.Fit)
                else Icon(painterResource(R.drawable.wb_chat), contentDescription = null, modifier = Modifier.size(48.dp))
                Text((if (active) "• " else "") + item.title, style = MaterialTheme.typography.bodyLarge,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center, maxLines = 3, overflow = TextOverflow.Ellipsis)
                Text(if (item.main) "主 Agent" else if (item.group) "群组 · 已置顶" else "单聊 · 已置顶",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (!item.main) IconButton(onClick = onPin, modifier = Modifier.align(Alignment.End).size(48.dp)) {
                Text("◆", Modifier.semantics { contentDescription = "取消置顶${item.title}" })
            } else Spacer(Modifier.height(48.dp))
        }
    }
}

@Composable
private fun ConversationEntry(item: ShellConversation, active: Boolean, onOpen: () -> Unit, onPin: () -> Unit) {
    Surface(color = if (active) MaterialTheme.colorScheme.surfaceVariant else MaterialTheme.colorScheme.surface,
        contentColor = MaterialTheme.colorScheme.onSurface, shape = RoundedCornerShape(20.dp)) {
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(painterResource(R.drawable.wb_chat), contentDescription = null,
                modifier = Modifier.padding(start = 12.dp).size(32.dp))
            Column(Modifier.weight(1f).testTag(if (item.main) "nav-chat" else "shell-conversation-${item.key}")
                .semantics { selected = active; contentDescription = "${item.title}，${if (active) "当前会话，" else ""}${if (item.main) "主 Agent" else if (item.pinned) "已置顶" else "普通会话"}" }
                .clickable(role = Role.Tab, onClick = onOpen).padding(12.dp)) {
                Text((if (active) "• " else "") + item.title, style = MaterialTheme.typography.bodyLarge)
                Text((if (item.group) "群组 · 仅本地组织" else if (item.main) "主 Agent" else "单聊") + (if (item.pinned) " · 已置顶" else ""),
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (!item.main) IconButton(onClick = onPin, modifier = Modifier.size(48.dp)) {
                Text(if (item.pinned) "◆" else "◇", Modifier.semantics {
                    contentDescription = "${if (item.pinned) "取消置顶" else "置顶"}${item.title}"
                })
            }
        }
    }
}

/** Natural height at large font sizes; body is laid out below, never behind the header. */
@Composable
fun ConversationHeader(title: String, onOpenMenu: () -> Unit, onMore: (() -> Unit)? = null, mainAgent: Boolean = false, moreMenu: @Composable () -> Unit = {}) {
    Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).testTag("shell-header").padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onOpenMenu, modifier = Modifier.size(48.dp)) {
            Icon(painterResource(R.drawable.wb_menu), "打开工作空间导航")
        }
        Column(Modifier.weight(1f).padding(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            if (mainAgent) Image(painterResource(R.drawable.muyon_brand_mascot_front), contentDescription = null,
                modifier = Modifier.size(48.dp).testTag("shell-original-mascot"), contentScale = ContentScale.Fit)
            Text(title, modifier = Modifier.semantics { heading() }, style = MaterialTheme.typography.titleMedium,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center, maxLines = 3, overflow = TextOverflow.Ellipsis)
        }
        if (onMore != null) Box {
            IconButton(onClick = onMore, modifier = Modifier.size(48.dp).testTag("chat-more")) {
                Text("···", Modifier.semantics { contentDescription = "更多会话操作" }, style = MaterialTheme.typography.titleLarge)
            }
            moreMenu()
        } else Spacer(Modifier.width(48.dp))
    }
}
