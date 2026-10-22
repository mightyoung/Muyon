package com.mightyoung.muyon.product.ui.shell

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import org.junit.Rule
import org.junit.Test

class ConfigurationPreviewHostTest {
    @get:Rule val compose = createComposeRule()
    @Test fun publicDocumentEntryKeepsFutureCapabilitiesClosed() {
        compose.setContent { DocumentCapabilitiesScreen {} }
        compose.onNodeWithText("公共文档阅读（等待授权接口）").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("批注编辑与保存（尚不可用）").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("打开现有项目资料").performScrollTo().assertIsEnabled()
        compose.onNodeWithText("公共阅读尚未连接已授权文件。接通后可查看 PDF 页面和 Word、PPT、Excel 文本预览；Office 预览不保留原版式。").assertExists()
    }

    @Test fun previewEntryRetainsUnsentTextAndDoesNotOfferCreation() {
        val state = ShellConfigurationState().forScope("test-local-preview")
        compose.setContent { ConfigurationPreviewHost(state) {} }
        compose.onNodeWithText("Bot 配置预览").performClick()
        compose.onNodeWithText("名称").performTextInput("用户草稿")
        compose.onNodeWithText("稍后配置 · 保留内存草稿").performScrollTo().performClick()
        compose.onNodeWithText("Bot 配置预览").performClick()
        compose.onNodeWithText("名称").assertTextContains("用户草稿")
        compose.onNodeWithText("持久保存 · 尚不可用").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("恢复存储草稿 · 尚不可用").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("核查原保存结果 · 尚不可用").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("稍后配置 · 保留内存草稿").performScrollTo().performClick()
        compose.onNodeWithText("群组配置预览").performClick()
        compose.onNodeWithText("请选择协作方式；没有默认选择。").assertExists()
        compose.onNodeWithText("保存设置（尚未接线）").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText("运行群组（不可用）").performScrollTo().assertIsNotEnabled()
    }
}
