package com.mightyoung.muyon.product.ui.shell

import com.mightyoung.muyon.product.ui.system.FoundationTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toPixelMap
import com.mightyoung.muyon.product.ui.system.FoundationTokens
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionOnScreen
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.test.junit4.createComposeRule
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

/** No ProductClient, model call, search or synthetic transcript. */
class ConversationShellTest {
    @get:Rule val compose = createComposeRule()

    @Test fun mainHeaderHasOneOriginalMascotAboveTheBody() {
        compose.setContent {
            FoundationTheme {
                Column {
                    ConversationHeader("主助手", {}, mainAgent = true)
                    Text("正文保持可见", Modifier.testTag("test-reading-body"))
                }
            }
        }
        compose.onAllNodesWithTag("shell-original-mascot").assertCountEquals(1)
        compose.onNodeWithTag("shell-original-mascot").assertIsDisplayed()
        val identity = compose.onNodeWithTag("shell-header").fetchSemanticsNode().boundsInRoot
        val body = compose.onNodeWithTag("test-reading-body").fetchSemanticsNode().boundsInRoot
        org.junit.Assert.assertTrue("header must be laid out above reading body", identity.bottom <= body.top)
    }

    @Test fun ordinaryHeaderDoesNotRepeatMainMascot() {
        compose.setContent { FoundationTheme { ConversationHeader("用户配置的助手", {}) } }
        compose.onNodeWithTag("shell-original-mascot").assertDoesNotExist()
    }

    @Test fun menuUsesRealEntriesAndSeparatesPinnedFromOrdinary() {
        var opened = ""
        var pinned = ""
        compose.setContent {
            FoundationTheme {
                ConversationShell("chat", "Muyon 助手", "agent:a", listOf(
                    ShellConversation("default", "Muyon 助手", main = true),
                    ShellConversation("agent:a", "真实助手", pinned = true),
                    ShellConversation("group:g", "真实群组", group = true),
                ), onSelectDestination = {}, onSelectConversation = { opened = it },
                    onTogglePin = { pinned = it }) { openMenu ->
                    ConversationHeader("真实助手", openMenu, {})
                }
            }
        }
        compose.onNodeWithContentDescription("打开工作空间导航").performClick()
        compose.onNodeWithTag("shell-original-brand-icon").assertIsDisplayed()
        compose.onNodeWithTag("shell-conversation-agent:a").assertIsSelected()
        compose.onNodeWithText("主 Agent 与置顶").assertExists()
        compose.onNodeWithText("最近会话").assertExists()
        compose.onNodeWithText("群组 · 仅本地组织").assertExists()
        compose.onNodeWithContentDescription("取消置顶真实助手").performClick()
        assertEquals("agent:a", pinned)
        compose.onNodeWithTag("shell-conversation-group:g").performClick()
        assertEquals("group:g", opened)
        compose.onNodeWithTag("shell-menu").assertDoesNotExist()
    }

    @Test fun dismissKeepsMountedBodyAndDraft() {
        compose.setContent {
            FoundationTheme {
                ConversationShell("chat", "Muyon 助手", "default", emptyList(), {}, {}, {}) { openMenu ->
                    var draft by remember { mutableStateOf("") }
                    Column {
                        ConversationHeader("Muyon 助手", openMenu, {})
                        TextField(draft, { draft = it }, modifier = Modifier.testTag("test-draft"))
                    }
                }
            }
        }
        compose.onNodeWithTag("test-draft").performTextInput("真实本地草稿")
        compose.onNodeWithContentDescription("打开工作空间导航").performClick()
        compose.onNodeWithContentDescription("关闭菜单").performClick()
        compose.onNodeWithTag("test-draft").assertTextContains("真实本地草稿")
    }

    @Test fun draftHasStableAccessiblePurposeAfterTypingAndPreviewRemainsDisabled() {
        compose.setContent {
            FoundationTheme {
                var draft by remember { mutableStateOf("") }
                ShellInputDock(draft, { draft = it }, enabled = false, onChat = {}, onAttachments = {}, attachmentsMenu = {})
            }
        }
        compose.onNodeWithContentDescription("消息草稿").performTextInput("仅本地输入测试")
        compose.onNodeWithContentDescription("消息草稿").assertTextContains("仅本地输入测试")
        compose.onNodeWithTag("chat-send").assertIsNotEnabled()
    }

    @Test fun headerAndComposerHaveDistinctActions() {
        var headerClicks = 0
        var attachmentClicks = 0
        compose.setContent {
            FoundationTheme {
                Column {
                    ConversationHeader("真实会话", {}, onMore = { headerClicks++ })
                    ShellInputDock("", {}, false, {}, { attachmentClicks++ }, {})
                }
            }
        }
        compose.onNodeWithContentDescription("更多会话操作").performClick()
        assertEquals(1, headerClicks)
        assertEquals(0, attachmentClicks)
        compose.onNodeWithContentDescription("添加附件").performClick()
        assertEquals(1, headerClicks)
        assertEquals(1, attachmentClicks)
    }

    @Test fun settingsShowFieldsBeforeExpandableDetailsAndKeepEdits() {
        compose.setContent {
            FoundationTheme {
                var credential by remember { mutableStateOf("") }
                var budget by remember { mutableStateOf("1000000") }
                var calls by remember { mutableStateOf("10") }
                androidx.compose.material3.AlertDialog(onDismissRequest = {},
                    title = { Text("模型与预算") }, confirmButton = {}, text = {
                        ProductSettingsFields(credential, { credential = it }, budget, { budget = it },
                            calls, { calls = it }, "连接状态未读取", "未知结果仍保留占额")
                    })
            }
        }
        compose.onNodeWithTag("settings-credential").assertIsDisplayed()
        compose.onNodeWithTag("settings-budget").assertIsDisplayed()
        compose.onNodeWithTag("settings-calls").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("settings-calls").performTextReplacement("12")
        compose.onNodeWithTag("settings-calls").assertTextContains("12")
        compose.onNodeWithText("供应商：DeepSeek；端点固定为 api.deepseek.com。不会读取历史凭据或预算。").assertDoesNotExist()
        compose.onNodeWithText("配置与计费说明").performScrollTo().performClick()
        compose.onNodeWithText("供应商：DeepSeek；端点固定为 api.deepseek.com。不会读取历史凭据或预算。").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("收起说明").performScrollTo().performClick()
        compose.onNodeWithTag("settings-calls").performScrollTo().assertTextContains("12")
    }

    @Test fun headerMenuIsAnchoredAboveComposerAndDismissesIndependently() {
        var popupBottom = Float.NaN
        var composerTop = Float.NaN
        compose.setContent {
            FoundationTheme {
                var more by remember { mutableStateOf(false) }
                var attachment by remember { mutableStateOf(false) }
                Column(Modifier.fillMaxSize()) {
                    ConversationHeader("真实会话", {}, onMore = { more = true }, moreMenu = {
                        androidx.compose.material3.DropdownMenu(more, { more = false }) {
                            androidx.compose.material3.DropdownMenuItem(text = { Text("本地会话设置", Modifier.onGloballyPositioned {
                                popupBottom = it.positionOnScreen().y + it.size.height
                            }) }, onClick = { more = false })
                        }
                    })
                    androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
                    androidx.compose.foundation.layout.Box(Modifier.onGloballyPositioned { composerTop = it.positionOnScreen().y }) {
                        ShellInputDock("", {}, false, {}, { attachment = true }, {
                            androidx.compose.material3.DropdownMenu(attachment, { attachment = false }) {
                                androidx.compose.material3.DropdownMenuItem(text = { Text("附件尚未接入") }, enabled = false, onClick = {})
                            }
                        })
                    }
                }
            }
        }
        compose.onNodeWithContentDescription("更多会话操作").performClick()
        compose.onNodeWithText("本地会话设置").assertIsDisplayed()
        compose.runOnIdle {
            org.junit.Assert.assertTrue("compare both windows in screen coordinates", popupBottom.isFinite() && composerTop.isFinite())
            org.junit.Assert.assertTrue("header menu stays above composer", popupBottom < composerTop)
        }
        compose.onNodeWithText("附件尚未接入").assertDoesNotExist()
        compose.onNodeWithText("本地会话设置").performClick()
        compose.onNodeWithContentDescription("添加附件").performClick()
        compose.onNodeWithText("本地会话设置").assertDoesNotExist()
        compose.onNodeWithText("附件尚未接入").assertIsNotEnabled()
    }

    @Test fun realPinnedConversationsShareTopRailAndOrdinaryStaysBelow() {
        compose.setContent {
            FoundationTheme {
                ConversationShell("chat", "主助手", "agent:a", listOf(
                    ShellConversation("default", "主助手", main = true),
                    ShellConversation("agent:a", "已打开助手", pinned = true),
                    ShellConversation("group:g", "已打开群组", group = true),
                ), {}, {}, {}) { open -> ConversationHeader("主助手", open) }
            }
        }
        compose.onNodeWithContentDescription("打开工作空间导航").performClick()
        val main = compose.onNodeWithTag("nav-chat").fetchSemanticsNode().boundsInRoot
        val pinned = compose.onNodeWithTag("shell-conversation-agent:a").fetchSemanticsNode().boundsInRoot
        val ordinary = compose.onNodeWithTag("shell-conversation-group:g").fetchSemanticsNode().boundsInRoot
        org.junit.Assert.assertEquals("main and pinned share a horizontal rail", main.top, pinned.top, 1f)
        org.junit.Assert.assertTrue("pinned follows main", pinned.left >= main.right)
        org.junit.Assert.assertTrue("ordinary remains below the pinned rail", ordinary.top > pinned.bottom)
        compose.onNodeWithTag("shell-conversation-agent:a").assertIsSelected()
    }

    @Test fun neutralComposerActionUsesThemeTextInsteadOfErrorInk() {
        compose.setContent {
            FoundationTheme(dark = false) {
                ShellInputDock("", {}, false, {}, {}, {})
            }
        }
        val pixels = compose.onNodeWithContentDescription("添加附件").captureToImage().toPixelMap()
        val ink = FoundationTokens.light.text
        var matching = 0
        for (x in 0 until pixels.width) for (y in 0 until pixels.height) {
            val p = pixels[x, y]
            if (kotlin.math.abs(p.red - ink.red) < .015f && kotlin.math.abs(p.green - ink.green) < .015f &&
                kotlin.math.abs(p.blue - ink.blue) < .015f) matching++
        }
        org.junit.Assert.assertTrue("a neutral composer action must render in neutral host text ink", matching > 0)
    }

    @Test fun navigationHeadingsAndFailureAnnouncementRemainDiscoverable() {
        compose.setContent {
            FoundationTheme {
                ConversationShell("chat", "测试标题", "default", emptyList(), {}, {}, {},
                    notice = "测试：置顶尚未保存") { open -> ConversationHeader("测试标题", open) }
            }
        }
        compose.onNodeWithText("测试标题").assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        compose.onNodeWithContentDescription("打开工作空间导航").performClick()
        compose.onNodeWithText("主 Agent 与置顶").assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        compose.onNodeWithText("最近会话").assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        compose.onNodeWithText("测试：置顶尚未保存")
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Polite))
    }

}
