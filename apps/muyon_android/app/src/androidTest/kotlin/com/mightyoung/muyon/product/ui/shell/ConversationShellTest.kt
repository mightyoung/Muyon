package com.mightyoung.muyon.product.ui.shell

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.foundation.layout.Column
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

/** No ProductClient, model call, search or synthetic transcript. */
class ConversationShellTest {
    @get:Rule val compose = createComposeRule()

    @Test fun menuUsesRealEntriesAndSeparatesPinnedFromOrdinary() {
        var opened = ""
        var pinned = ""
        compose.setContent {
            MaterialTheme {
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
            MaterialTheme {
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
}
