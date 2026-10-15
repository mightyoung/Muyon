package com.mightyoung.muyon.androidlab

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import org.junit.Rule
import org.junit.Test

/** Source-only until an explicitly authorized Android test run. No backend fixture. */
class ShellComposeTest {
    @get:Rule val compose = createComposeRule()

    @Test fun draftAndFocusSurviveNavigationAndRailChange() {
        var width by mutableFloatStateOf(899f)
        compose.setContent { MuyonLabShell(windowWidthDp = width) }
        compose.onNodeWithTag("bottom-nav").assertExists()
        compose.onNodeWithTag("assistant-draft").performClick().performTextInput("未发送 e\u0301")
        compose.onNodeWithTag("destination-TASKS").performClick()
        compose.onNodeWithTag("assistant-draft").assertDoesNotExist()
        compose.onNodeWithTag("destination-ASSISTANT").performClick()
        compose.onNodeWithTag("assistant-draft").assert(SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString("未发送 e\u0301"))).assertIsFocused()
        compose.runOnIdle { width = 900f }
        compose.onNodeWithTag("bottom-nav").assertDoesNotExist()
        compose.onNodeWithTag("rail").assertExists()
        compose.onNodeWithTag("assistant-draft").assert(SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString("未发送 e\u0301"))).assertIsFocused()
        compose.onNodeWithTag("port-disconnected").assertExists()
    }

    @Test fun savedUserNoteAppearsInRecordsAndReturnsToItsConversation() {
        compose.setContent { MuyonLabShell(windowWidthDp = 390f) }
        compose.onNodeWithTag("send-unavailable").assertIsNotEnabled()
        compose.onNodeWithTag("save-local-note").assertIsNotEnabled()
        compose.onNodeWithTag("assistant-draft").performTextInput("用户自己的本地记录")
        compose.onNodeWithTag("save-local-note").performClick()
        compose.onNodeWithTag("chat-note-1").assertExists()
        compose.onNodeWithTag("assistant-draft").assert(SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString("")))
        compose.onNodeWithTag("destination-DATA").performClick()
        compose.onNodeWithTag("record-1-1").performClick()
        compose.onNodeWithTag("note-details").assertExists()
        compose.onNodeWithTag("note-open-conversation").performClick()
        compose.onNodeWithTag("conversation-title").assertTextEquals("新的本地会话")
        compose.onNodeWithTag("chat-note-1").assertExists()
        compose.onNodeWithTag("send-unavailable").assertIsNotEnabled()
    }

    @Test fun switchingLocalConversationsRetainsDraftAndRenameCanBeCancelled() {
        compose.setContent { MuyonLabShell(windowWidthDp = 390f) }
        compose.onNodeWithTag("assistant-draft").performTextInput("第一份未保存草稿")
        compose.onNodeWithTag("new-conversation").performClick()
        compose.onNodeWithTag("assistant-draft").performTextInput("第二份草稿")
        compose.onNodeWithTag("open-history").performClick()
        compose.onNodeWithTag("history-conversation-1").performClick()
        compose.onNodeWithTag("assistant-draft").assert(SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString("第一份未保存草稿")))
        compose.onNodeWithTag("open-history").performClick()
        compose.onNodeWithTag("rename-conversation-1").performClick()
        compose.onNodeWithTag("rename-input").performTextReplacement("取消的名称")
        compose.onNodeWithTag("rename-cancel").performClick()
        compose.onNodeWithTag("conversation-title").assertTextEquals("新的本地会话")
        compose.onNodeWithTag("open-history").performClick()
        compose.onNodeWithTag("rename-conversation-1").performClick()
        compose.onNodeWithTag("rename-input").performTextReplacement("我的本地会话")
        compose.onNodeWithTag("rename-confirm").performClick()
        compose.onNodeWithTag("conversation-title").assertTextEquals("我的本地会话")
    }

    @Test fun localPreferencesAndCapabilitySheetNeverEnableSending() {
        compose.setContent { MuyonLabShell(windowWidthDp = 390f) }
        compose.onNodeWithTag("assistant-draft").performTextInput("保留输入")
        compose.onNodeWithTag("destination-SETTINGS").performClick()
        compose.onNodeWithTag("theme-DARK").performClick().assertIsSelected()
        compose.onNodeWithTag("destination-TASKS").performClick()
        compose.onNodeWithTag("task-filter-WAITING_CONFIRMATION").performClick().assertIsSelected()
        compose.onNodeWithTag("destination-ASSISTANT").performClick()
        compose.onNodeWithTag("assistant-draft").assert(SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString("保留输入")))
        compose.onNodeWithTag("input-options").performClick()
        compose.onNodeWithTag("model-unavailable").assertIsNotEnabled()
        compose.onNodeWithTag("attachment-unavailable").assertIsNotEnabled()
        compose.onNodeWithTag("capabilities-close").performClick()
        compose.onNodeWithTag("send-unavailable").assertIsNotEnabled()
    }
}
