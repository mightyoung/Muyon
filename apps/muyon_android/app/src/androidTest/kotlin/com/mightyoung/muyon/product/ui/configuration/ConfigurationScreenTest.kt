package com.mightyoung.muyon.product.ui.configuration

import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.mightyoung.muyon.product.agents.setup.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class ConfigurationScreenTest {
    @get:Rule val compose = createComposeRule()

    @Test fun backAndLaterRetainUserDraft() {
        val editor = BotConfigurationEditor(BotSetupDraft("test-scope"))
        var leaves = 0
        compose.setContent { BotConfigurationScreen(editor, editor.draft.snapshot(), { leaves++ }) }
        compose.onNodeWithText("名称（最多60字符）").performTextInput("我的助手")
        compose.onNodeWithText("下一步").performScrollTo().performClick()
        compose.onNodeWithText("用途（最多8000字符）").performTextInput("整理论文")
        compose.onNodeWithText("下一步").performScrollTo().performClick()
        compose.onNodeWithText("角色（可修改，最多160字符）").performTextInput("手工角色")
        compose.onNodeWithText("返回").performScrollTo().performClick()
        compose.onNodeWithText("用途（最多8000字符）").assertTextContains("整理论文")
        compose.onNodeWithText("下一步").performScrollTo().performClick()
        compose.onNodeWithText("角色（可修改，最多160字符）").assertTextContains("手工角色")
        compose.onNodeWithText("下一步").performScrollTo().performClick()
        compose.onNodeWithText("保存 / 创建（尚未接线）").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("启动任务（不可用）").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("稍后配置 · 保留内存草稿").performScrollTo().performClick()
        compose.runOnIdle { assertEquals(1, leaves); assertEquals("手工角色", editor.preview()!!.role) }
    }

    @Test fun unknownQueriesOriginalIntentWithoutRecreating() {
        val draft = BotSetupDraft("test-scope")
        draft.editName("助手"); draft.next(); draft.editPurpose("整理"); draft.next()
        draft.editRole("整理助手"); draft.next()
        draft.observePendingCreation("test-original", draft.snapshot().revision)
        draft.observeCreationResult("test-original", CreationStatus.UNKNOWN)
        var queried: String? = null
        compose.setContent { BotConfigurationScreen(BotConfigurationEditor(draft), draft.snapshot(), {}, { queried = it }) }
        compose.onNodeWithText("查询原意图回执").performScrollTo().performClick()
        compose.onNodeWithText("下一步").assertDoesNotExist()
        compose.runOnIdle {
            assertEquals("test-original", queried)
            assertEquals(CreationStatus.UNKNOWN, draft.snapshot().creation.status)
        }
    }

    @Test fun hostReceiptRefreshChangesUnknownToCreatedWithoutRecreation() {
        val draft = BotSetupDraft("test-scope")
        draft.editName("助手"); draft.next(); draft.editPurpose("整理"); draft.next()
        draft.editRole("整理助手"); draft.next()
        val editor = BotConfigurationEditor(draft)
        val hostSnapshot = mutableStateOf(draft.snapshot())
        compose.setContent { BotConfigurationScreen(editor, hostSnapshot.value, {}) }
        compose.runOnIdle {
            draft.observePendingCreation("test-original", draft.snapshot().revision)
            draft.observeCreationResult("test-original", CreationStatus.UNKNOWN)
            hostSnapshot.value = draft.snapshot()
        }
        compose.onNodeWithText("创建结果未知；不编辑、不重建，只查询原意图回执。").assertExists()
        compose.runOnIdle {
            draft.observeCreationResult("test-original", CreationStatus.CREATED, "test-agent")
            hostSnapshot.value = draft.snapshot()
        }
        compose.onNodeWithText("宿主回执表示已创建；没有自动启动。").assertExists()
        compose.onNodeWithText("创建结果未知；不编辑、不重建，只查询原意图回执。").assertDoesNotExist()
        compose.onNodeWithText("下一步").assertDoesNotExist()
    }

    @Test fun groupModesHaveNoDefaultAndNeverEnableRun() {
        compose.setContent {
            var mode by remember { mutableStateOf<String?>(null) }
            GroupConfigurationScreen(GroupGovernanceDisplay(null, null, null, null, null, null, emptyList()),
                mode, { mode = it }, "", null, {})
        }
        compose.onNodeWithText("请选择协作方式；没有默认选择。").assertExists()
        compose.onNodeWithText("固定协调者 · fixed").performScrollTo().performClick()
        compose.onNodeWithText("协调成员 ID（仅草稿）").assertExists()
        compose.onNodeWithText("保存设置（尚未接线）").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("运行群组（不可用）").performScrollTo().assertIsNotEnabled()
    }
}
