package com.mightyoung.muyon.androidlab.conversation

import androidx.compose.foundation.clickable
import androidx.compose.foundation.Image
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.mightyoung.muyon.androidlab.*
import kotlinx.coroutines.launch

/** A local notebook until an execution projection is supplied by the integration owner. */
@Composable
internal fun ConversationPage(
    local: LocalUiState,
    scroll: LazyListState,
    draftFocus: FocusRequester,
    inputActions: LocalInputActions,
    onMounted: (Boolean) -> Unit,
    onSave: () -> Unit,
    onOptions: () -> Unit,
    onNote: (Int) -> Unit,
    availability: PortAvailability,
    sample: Boolean = false,
    onSampleChange: (Boolean) -> Unit = {},
    restorationNotice: String? = null,
) {
    val active = local.active
    val sampleScroll = rememberLazyListState()
    val messageScroll = if (sample) sampleScroll else scroll
    val scope = rememberCoroutineScope()
    var priorCount by remember(active.id) { mutableIntStateOf(active.notes.size) }
    var unseen by remember(active.id) { mutableStateOf(false) }
    val atBottom by remember(messageScroll) { derivedStateOf { !messageScroll.canScrollForward } }
    LaunchedEffect(active.id, active.notes.size) {
        if (active.notes.size > priorCount && !sample) {
            if (atBottom) messageScroll.jumpConversationToBottom() else unseen = true
        }
        priorCount = active.notes.size
    }
    LaunchedEffect(atBottom) { if (atBottom) unseen = false }
    Column(Modifier.fillMaxSize()) {
        if (restorationNotice != null) Text(restorationNotice, style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp).semantics { liveRegion = LiveRegionMode.Polite })
        Row(Modifier.fillMaxWidth().padding(start=20.dp,end=8.dp), verticalAlignment=Alignment.CenterVertically) {
            Text(if (sample) "离线视觉样例 · 非真实回复" else when(availability) {
                PortAvailability.NOT_CONNECTED -> "本地模式 · 执行服务未连接"
            }, style=MaterialTheme.typography.labelSmall, color=MaterialTheme.colorScheme.onSurfaceVariant,
                modifier=Modifier.weight(1f).testTag(if(sample) "sample-disclaimer" else "port-disconnected").semantics { liveRegion=LiveRegionMode.Polite })
            TextButton(onClick={onSampleChange(!sample)}, modifier=Modifier.testTag("toggle-chat-sample")) {
                Text(if(sample) "返回会话" else "查看样例", style=MaterialTheme.typography.labelSmall)
            }
        }
        Box(Modifier.weight(1f).fillMaxWidth()) {
            LazyColumn(state=messageScroll, modifier=Modifier.fillMaxSize().testTag("local-chat-list"),
                contentPadding=PaddingValues(start=20.dp,end=20.dp,top=20.dp,bottom=28.dp), verticalArrangement=Arrangement.spacedBy(26.dp),
                horizontalAlignment=Alignment.CenterHorizontally) {
                if (sample) {
                    item("fixture-user") { UserMessage("帮我整理一下这个项目的下一步。", "离线样例 · 用户") }
                    item("fixture-assistant") {
                        AssistantMessage("可以从三个方向开始：\n\n**明确目标**，先确认这次交付要解决的问题。\n\n• 整理待办与优先级\n• 记录尚未确认的约束\n• 留下可检查的交付结果\n\n以下代码和链接只用于检查排版：\n```kotlin\nval nextStep = \"review\"\nprintln(nextStep)\n```\n参考 [Android 文档](https://developer.android.com)。")
                    }
                    item("fixture-tools") { ToolSample() }
                    item("fixture-stopped") { SampleStatus("已停止", "离线样例：停止后的内容保留。这里没有运行中的请求。") }
                    item("fixture-failed") { SampleStatus("请求失败", "离线样例：服务未连接，无法重试。", failed=true) }
                } else if (active.notes.isEmpty()) {
                    item("empty") {
                        Column(Modifier.widthIn(max=640.dp).fillMaxWidth().padding(top=24.dp,bottom=24.dp), horizontalAlignment=Alignment.Start) {
                            Image(painterResource(R.drawable.muyon_welcome), contentDescription=null,
                                modifier=Modifier.size(128.dp).padding(bottom=12.dp))
                            Text("从一个想法开始", style=MaterialTheme.typography.headlineMedium, fontWeight=FontWeight.Medium,
                                modifier=Modifier.semantics { heading() })
                            Spacer(Modifier.height(14.dp))
                            Text("写下你想做的事。", style=MaterialTheme.typography.bodyLarge, color=MaterialTheme.colorScheme.onSurfaceVariant)
                            Spacer(Modifier.height(8.dp))
                            Text("当前可以保存本地记录；模型、附件与工具尚未接入。", style=MaterialTheme.typography.bodyMedium,
                                color=MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                } else items(active.notes, key={"note-${it.id}"}) { note ->
                    UserMessage(note.text, "你 · 本地记录，未发送", Modifier.testTag("chat-note-${note.id}").clickable(onClick={onNote(note.id)}))
                }
            }
            if (!atBottom && messageScroll.layoutInfo.totalItemsCount > 0) {
                FilledTonalButton(onClick={scope.launch { messageScroll.jumpConversationToBottom(); unseen=false }},
                    modifier=Modifier.align(Alignment.BottomCenter).padding(bottom=10.dp).testTag("jump-latest")) {
                    ChatGlyph(ChatGlyphKind.DOWN); Spacer(Modifier.width(8.dp)); Text(if(unseen) "有新记录" else "回到底部")
                }
            }
        }
        key(active.id) { DisposableEffect(active.id) { onMounted(true); onDispose { onMounted(false) } } }
        Column(Modifier.fillMaxWidth().imePadding().padding(horizontal=16.dp,vertical=10.dp),horizontalAlignment=Alignment.CenterHorizontally) {
            Surface(shape=RoundedCornerShape(26.dp), color=MaterialTheme.colorScheme.surfaceContainerLow,
                border=androidx.compose.foundation.BorderStroke(1.dp,MaterialTheme.colorScheme.outlineVariant),
                modifier=Modifier.widthIn(max=720.dp).fillMaxWidth()) {
                Column(Modifier.padding(start=16.dp,end=10.dp,top=16.dp,bottom=8.dp)) {
                    BasicTextField(value=active.memory.draft, onValueChange=inputActions.draftChanged,
                        textStyle=MaterialTheme.typography.bodyLarge.copy(color=MaterialTheme.colorScheme.onSurface),
                        minLines=2,maxLines=6, readOnly=sample, modifier=Modifier.fillMaxWidth().testTag("assistant-draft").focusRequester(draftFocus)
                            .onFocusChanged { if(it.isFocused && !sample) inputActions.draftFocused() }.semantics { contentDescription="消息草稿" },
                        decorationBox={ field -> Box { if(active.memory.draft.isEmpty()) Text("写下想法…",color=MaterialTheme.colorScheme.onSurfaceVariant); field() } })
                    Row(Modifier.fillMaxWidth(), verticalAlignment=Alignment.CenterVertically) {
                        IconButton(onClick=onOptions,modifier=Modifier.testTag("input-options").semantics { contentDescription="附件与输入能力说明" }) { ChatGlyph(ChatGlyphKind.ADD) }
                        Text(if(sample) "样例只读" else "本地记录",style=MaterialTheme.typography.labelSmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.weight(1f))
                        TextButton(onClick={},enabled=false,modifier=Modifier.testTag("send-unavailable")) { Text("发送") }
                        Button(onClick=onSave,enabled=local.canSaveLocalNote && !sample,modifier=Modifier.testTag("save-local-note").semantics { contentDescription="保存本地记录，不发送" }) { Text("保存") }
                    }
                }
            }
            Text(if(sample) "返回会话后可编辑和保存 · 样例不发送请求" else "仅保存在当前内存中 · 不会生成助手回复",style=MaterialTheme.typography.labelSmall,color=MaterialTheme.colorScheme.onSurfaceVariant,
                modifier=Modifier.padding(top=8.dp))
        }
    }
}

/** Aligns the actual final edge, including a single message taller than the viewport. */
internal suspend fun LazyListState.jumpConversationToBottom() {
    // A newly saved note may not have reached LazyColumn's layout at the click boundary.
    withFrameNanos { }
    val lastIndex = layoutInfo.totalItemsCount - 1
    if (lastIndex < 0) return
    animateScrollToItem(lastIndex)
    withFrameNanos { }
    val measured = layoutInfo
    val last = measured.visibleItemsInfo.lastOrNull { it.index == lastIndex } ?: return
    val remaining = (last.offset.toLong() + last.size.toLong() + measured.afterContentPadding.toLong() -
        measured.viewportEndOffset.toLong()).coerceAtLeast(0L)
    if (remaining > 0) animateScrollBy(remaining.toFloat())
}

@Composable
private fun UserMessage(text: String, label: String, modifier: Modifier=Modifier) {
    Column(Modifier.widthIn(max=720.dp).fillMaxWidth(),horizontalAlignment=Alignment.End) {
        Surface(shape=RoundedCornerShape(22.dp,22.dp,6.dp,22.dp),color=MaterialTheme.colorScheme.surfaceContainerHigh,
            modifier=modifier.widthIn(max=560.dp)) {
            SelectionContainer { Text(text,style=MaterialTheme.typography.bodyLarge,modifier=Modifier.padding(horizontal=18.dp,vertical=14.dp)) }
        }
        Text(label,style=MaterialTheme.typography.labelSmall,color=MaterialTheme.colorScheme.onSurfaceVariant,modifier=Modifier.padding(top=7.dp,end=4.dp))
    }
}

@Composable
private fun AssistantMessage(text: String) {
    Column(Modifier.widthIn(max=720.dp).fillMaxWidth().testTag("fixture-long-message"),verticalArrangement=Arrangement.spacedBy(12.dp)) {
        Text("Muyon · 离线排版样例",style=MaterialTheme.typography.labelMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
        RichContent(text)
    }
}

/** Deliberately small native renderer: paragraphs, bullets, emphasis, fenced code and safe URL links. */
@Composable
private fun RichContent(text: String) {
    val blocks=remember(text) { text.split("```") }
    val linkColor=MaterialTheme.colorScheme.primary
    SelectionContainer {
        Column(verticalArrangement=Arrangement.spacedBy(14.dp)) {
            blocks.forEachIndexed { index, block ->
                if(index % 2 == 1) {
                    val language=block.substringBefore('\n').trim()
                    Surface(shape=RoundedCornerShape(14.dp),color=MaterialTheme.colorScheme.surfaceContainer) {
                        Column(Modifier.fillMaxWidth().padding(14.dp)) {
                            Text(language.ifBlank { "code" },style=MaterialTheme.typography.labelSmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(block.substringAfter('\n',block).trimEnd(),fontFamily=FontFamily.Monospace,style=MaterialTheme.typography.bodyMedium,
                                modifier=Modifier.padding(top=10.dp).horizontalScroll(rememberScrollState()).testTag("fixture-code"))
                        }
                    }
                } else if(block.isNotBlank()) {
                    val annotated=buildAnnotatedString {
                        val token=Regex("\\*\\*(.+?)\\*\\*|\\[([^]]+)]\\((https?://[^ )]+)\\)")
                        var cursor=0
                        token.findAll(block.trim()).forEach { match ->
                            append(block.trim().substring(cursor,match.range.first))
                            if(match.groupValues[1].isNotEmpty()) withStyle(SpanStyle(fontWeight=FontWeight.SemiBold)) { append(match.groupValues[1]) }
                            else withLink(LinkAnnotation.Url(match.groupValues[3])) { withStyle(SpanStyle(color=linkColor)) { append(match.groupValues[2]) } }
                            cursor=match.range.last+1
                        }
                        append(block.trim().substring(cursor))
                    }
                    Text(annotated,style=MaterialTheme.typography.bodyLarge,modifier=if(block.contains("https://")) Modifier.testTag("fixture-link") else Modifier)
                }
            }
        }
    }
}

@Composable
private fun ToolSample() {
    var expanded by rememberSaveable { mutableStateOf(false) }
    Surface(shape=RoundedCornerShape(16.dp),color=MaterialTheme.colorScheme.surfaceContainerLow,modifier=Modifier.widthIn(max=720.dp).fillMaxWidth()) {
        Column {
            Row(Modifier.fillMaxWidth().clickable { expanded=!expanded }.padding(16.dp).testTag("tool-toggle")
                .semantics { role=Role.Button; stateDescription=if(expanded) "已展开" else "已折叠" },verticalAlignment=Alignment.CenterVertically) {
                ChatGlyph(ChatGlyphKind.TOOL); Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) { Text("工具过程",style=MaterialTheme.typography.labelLarge); Text("状态未知 · 离线样例",style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant,modifier=Modifier.testTag("unknown-tool").semantics { contentDescription="离线视觉样例，工具执行状态未知" }) }
                ChatGlyph(if(expanded) ChatGlyphKind.DOWN else ChatGlyphKind.CHEVRON)
            }
            if(expanded) Text("unknown：尚未收到可信执行状态。\n不推断工具是否执行，也不显示成功。",modifier=Modifier.padding(start=16.dp,end=16.dp,bottom=16.dp).testTag("tool-details"),style=MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
private fun SampleStatus(title:String, detail:String, failed:Boolean=false) {
    Column(Modifier.widthIn(max=720.dp).fillMaxWidth().semantics { contentDescription="离线视觉样例：$title" },verticalArrangement=Arrangement.spacedBy(6.dp)) {
        Text(title,style=MaterialTheme.typography.labelLarge,color=if(failed) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
        Text(detail,style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
        if(failed) TextButton(onClick={},enabled=false,modifier=Modifier.testTag("sample-retry-unavailable")) { Text("重试（未接入）") }
    }
}
