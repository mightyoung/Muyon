package com.mightyoung.muyon.product.chat

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.mightyoung.muyon.product.design.MuyonTheme
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class ChatOutboundPreviewTest {
    @get:Rule val compose = createComposeRule()

    @Test fun actualHistoryAndToolsAreDisplayedInsteadOfOnlyCurrentInput() {
        val payload = JSONObject().put("messages", JSONArray()
            .put(JSONObject().put("role", "user").put("content", "自动加入的历史 H-17"))
            .put(JSONObject().put("role", "user").put("content", "当前输入 C-22")))
            .put("tools", JSONArray().put(JSONObject().put("name", "paper_list")))
        val plan = JSONObject().put("outbound_endpoint", "https://api.deepseek.com/chat/completions").put("outbound_preview", payload)
        assertTrue(hasCompleteOutboundPreview(plan))
        compose.setContent { MuyonTheme { ChatOutboundPreview(plan) } }
        compose.onNodeWithText("自动加入的历史 H-17", substring = true).assertTextContains("自动加入的历史 H-17", substring = true)
            .assertTextContains("当前输入 C-22", substring = true).assertTextContains("paper_list", substring = true)
        compose.onNodeWithTag("chat-outbound-endpoint").assertTextEquals("https://api.deepseek.com/chat/completions")
        assertFalse(hasCompleteOutboundPreview(JSONObject().put("input_preview", "只有当前输入")))
        assertFalse(hasCompleteOutboundPreview(JSONObject().put("outbound_preview", payload)))
        assertFalse(hasCompleteOutboundPreview(JSONObject().put("outbound_endpoint", "https://api.deepseek.com")))
    }
}
