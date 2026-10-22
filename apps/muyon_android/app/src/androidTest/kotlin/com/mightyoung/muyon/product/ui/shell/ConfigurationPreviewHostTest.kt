package com.mightyoung.muyon.product.ui.shell

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import org.junit.Rule
import org.junit.Test

class ConfigurationPreviewHostTest {
    @get:Rule val compose = createComposeRule()
    @Test fun publicDocumentEntryKeepsFutureCapabilitiesClosed() {
        compose.setContent { DocumentCapabilitiesScreen {} }
        compose.onNodeWithText("公共文档阅读（未接线）").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("适量编辑（未接线）").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("打开现有项目资料").performScrollTo().assertIsEnabled()
    }

    @Test fun previewEntryRetainsLocalEditorAndDoesNotOfferCreation() {
        val state = ShellConfigurationState().forScope("test-local-preview")
        compose.setContent { ConfigurationPreviewHost(state) {} }
        compose.onNodeWithText("Bot 配置预览").performClick()
        compose.onNodeWithText("名称（最多60字符）").performTextInput("用户草稿")
        compose.onNodeWithText("稍后配置 · 保留内存草稿").performScrollTo().performClick()
        compose.onNodeWithText("Bot 配置预览").performClick()
        compose.onNodeWithText("名称（最多60字符）").assertTextContains("用户草稿")
        compose.onNodeWithText("稍后配置 · 保留内存草稿").performScrollTo().performClick()
        compose.onNodeWithText("群组配置预览").performClick()
        compose.onNodeWithText("请选择协作方式；没有默认选择。").assertExists()
        compose.onNodeWithText("保存设置（尚未接线）").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("运行群组（不可用）").performScrollTo().assertIsNotEnabled()
    }
}
