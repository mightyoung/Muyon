package com.mightyoung.muyon.androidlab

import android.view.KeyEvent
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.text.AnnotatedString
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Rule
import org.junit.Test

/** Offline candidate contract. These are runtime checks, never evidence of a connected model. */
class MuseConversationTest {
    @get:Rule val compose = createComposeRule()

    private fun start() = compose.setContent { MuyonLabShell(windowWidthDp = 390f) }
    private fun draftEquals(raw: String) = compose.onNodeWithTag("assistant-draft").assert(
        SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString(raw)),
    )

    @Test fun drawerCloseAndSystemBackReturnToSameDraft() {
        start()
        compose.onNodeWithTag("assistant-draft").performTextInput("未发送的草稿")
        compose.onNodeWithTag("open-history").performClick()
        compose.onNodeWithTag("history-drawer").assertIsDisplayed()
        compose.onNodeWithTag("close-history").performClick()
        compose.onNodeWithTag("history-drawer").assertIsNotDisplayed()
        draftEquals("未发送的草稿")
        compose.onNodeWithTag("open-history").performClick()
        InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
        compose.waitForIdle()
        compose.onNodeWithTag("history-drawer").assertIsNotDisplayed()
        draftEquals("未发送的草稿")
    }

    @Test fun newAndSelectedConversationsKeepIndependentDrafts() {
        start()
        compose.onNodeWithTag("assistant-draft").performTextInput("第一份 e\u0301\n未发送")
        compose.onNodeWithTag("open-history").performClick()
        compose.onNodeWithTag("history-conversation-1").assertIsSelected()
        compose.onNodeWithTag("history-create").performClick()
        draftEquals("")
        compose.onNodeWithTag("assistant-draft").performTextInput("第二份 🐶")
        compose.onNodeWithTag("open-history").performClick()
        compose.onNodeWithTag("history-conversation-2").assertIsSelected()
        compose.onNodeWithTag("history-conversation-1").performClick()
        draftEquals("第一份 e\u0301\n未发送")
        compose.onNodeWithTag("open-history").performClick()
        compose.onNodeWithTag("history-conversation-2").performClick()
        draftEquals("第二份 🐶")
    }

    @Test fun searchFiltersHistoryWithoutReplacingActiveConversation() {
        start()
        compose.onNodeWithTag("assistant-draft").performTextInput("保留草稿")
        compose.onNodeWithTag("open-history").performClick()
        compose.onNodeWithTag("history-create").performClick()
        compose.onNodeWithTag("open-history").performClick()
        compose.onNodeWithTag("history-search").performTextInput("新的本地会话")
        compose.onNodeWithTag("history-conversation-1").assertExists()
        compose.onNodeWithTag("history-conversation-2").assertDoesNotExist()
        compose.onNodeWithTag("history-search").performTextReplacement("")
        compose.onNodeWithTag("history-conversation-2").assertIsSelected()
        compose.onNodeWithTag("history-conversation-1").performClick()
        draftEquals("保留草稿")
    }

    @Test fun renameCancelAndConfirmDoNotModifyDraftOrDispatch() {
        start()
        compose.onNodeWithTag("assistant-draft").performTextInput("仍未发送")
        compose.onNodeWithTag("open-history").performClick()
        compose.onNodeWithTag("rename-conversation-1").performClick()
        compose.onNodeWithTag("rename-input").performTextReplacement("取消的标题")
        compose.onNodeWithTag("rename-cancel").performClick()
        compose.onNodeWithTag("conversation-title").assertTextEquals("新的本地会话")
        compose.onNodeWithTag("open-history").performClick()
        compose.onNodeWithTag("rename-conversation-1").performClick()
        compose.onNodeWithTag("rename-input").performTextReplacement("我的本地会话")
        compose.onNodeWithTag("rename-confirm").performClick()
        compose.onNodeWithTag("conversation-title").assertTextEquals("我的本地会话")
        draftEquals("仍未发送")
        compose.onNodeWithTag("send-unavailable").assertIsNotEnabled()
    }

    @Test fun multilineUnicodeInputSurvivesPageChangesWithoutSending() {
        start()
        val raw = "  中文 e\u0301 🐶\n第二行\n```kotlin\nval x = 1\n```  "
        compose.onNodeWithTag("assistant-draft").performClick().performTextInput(raw)
        compose.onNodeWithTag("assistant-draft").assert(SemanticsMatcher.keyIsDefined(SemanticsActions.SetText))
        compose.onNodeWithTag("send-unavailable").assertIsNotEnabled()
        compose.onNodeWithTag("destination-TASKS").performClick()
        compose.onNodeWithTag("destination-ASSISTANT").performClick()
        draftEquals(raw)
        compose.onNodeWithTag("save-local-note").performClick()
        draftEquals("")
        compose.onNodeWithTag("send-unavailable").assertIsNotEnabled()
    }

    @Test fun longLocalMessageKeepsComposerReachable() {
        start()
        val raw = (1..100).joinToString("\n") { "第 $it 行：长内容与 https://example.invalid/ 仅为本地记录" }
        compose.onNodeWithTag("assistant-draft").performTextInput(raw)
        compose.onNodeWithTag("save-local-note").performClick()
        compose.onNodeWithTag("assistant-draft").assertIsDisplayed()
        compose.onNodeWithTag("assistant-draft").performTextInput("下一条草稿")
        draftEquals("下一条草稿")
        compose.onNodeWithTag("send-unavailable").assertIsNotEnabled()
    }

    @Test fun unknownToolFixtureNeverClaimsSuccessWhenExpandedOrCollapsed() {
        start()
        compose.onNodeWithTag("assistant-draft").performTextInput("样例外的草稿")
        compose.onNodeWithTag("toggle-chat-sample").performClick()
        compose.onNodeWithTag("sample-disclaimer").assertTextContains("非真实回复", substring = true)
        compose.onNodeWithTag("save-local-note").assertIsNotEnabled()
        compose.onNodeWithTag("local-chat-list").performScrollToNode(hasTestTag("tool-toggle"))
        compose.onNodeWithTag("unknown-tool", useUnmergedTree = true).assertTextContains("未知", substring = true)
        compose.onNodeWithTag("tool-toggle").performClick()
        compose.onNodeWithTag("unknown-tool", useUnmergedTree = true).assertTextContains("未知", substring = true)
        compose.onNodeWithTag("tool-toggle").performClick()
        compose.onNodeWithTag("unknown-tool", useUnmergedTree = true).assertTextContains("未知", substring = true)
        compose.onNodeWithTag("send-unavailable").assertIsNotEnabled()
        compose.onNodeWithTag("toggle-chat-sample").performClick()
        draftEquals("样例外的草稿")
    }

    @Test fun savedInstanceRestorationRetainsConversationDraftsAndRecords() {
        val restoration = StateRestorationTester(compose)
        restoration.setContent { MuyonLabShell(windowWidthDp = 390f) }
        compose.onNodeWithTag("assistant-draft").performTextInput("恢复后的本地记录")
        compose.onNodeWithTag("save-local-note").performClick()
        compose.onNodeWithTag("assistant-draft").performTextInput("第一份草稿 🐶")
        compose.onNodeWithTag("open-history").performClick()
        compose.onNodeWithTag("history-create").performClick()
        compose.onNodeWithTag("assistant-draft").performTextInput("第二份\n未发送 e\u0301")
        restoration.emulateSavedInstanceStateRestore()
        draftEquals("第二份\n未发送 e\u0301")
        compose.onNodeWithTag("open-history").performClick()
        compose.onNodeWithTag("history-conversation-2").assertIsSelected()
        compose.onNodeWithTag("history-conversation-1").performClick()
        draftEquals("第一份草稿 🐶")
        compose.onNodeWithTag("chat-note-1").assertExists()
        compose.onNodeWithTag("send-unavailable").assertIsNotEnabled()
    }

    @Test fun drawerAndComposerControlsHaveAccessibleNames() {
        start()
        compose.onNodeWithTag("open-history").assertContentDescriptionEquals("打开会话侧栏")
        compose.onNodeWithTag("assistant-draft").assertContentDescriptionEquals("消息草稿")
        compose.onNodeWithTag("open-history").performClick()
        compose.onNodeWithTag("close-history").assertContentDescriptionEquals("关闭会话侧栏")
        compose.onNodeWithTag("history-create").assertContentDescriptionEquals("新建本地会话")
    }
}
