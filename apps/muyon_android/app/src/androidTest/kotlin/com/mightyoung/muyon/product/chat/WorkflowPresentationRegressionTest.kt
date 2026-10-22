package com.mightyoung.muyon.product.chat

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.mightyoung.muyon.product.agents.visibleName
import com.mightyoung.muyon.product.design.MuyonTheme
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class WorkflowPresentationRegressionTest {
    @get:Rule val compose = createComposeRule()

    @Test fun remoteAnswerIsReadableAndMetadataRequiresAnotherAction() {
        val result = JSONObject().put("answer", "实际模型回答 A-17").put("input_tokens", 127).put("output_tokens", 11)
        compose.setContent { MuyonTheme { WorkflowResult(result) } }
        compose.onNodeWithText("实际模型回答 A-17").assertIsDisplayed()
        compose.onNodeWithText("input_tokens", substring = true).assertDoesNotExist()
        compose.onNodeWithTag("workflow-result-metadata").performClick()
        compose.onNodeWithText("input_tokens", substring = true).assertExists()
    }

    @Test fun countsExcludeRootAndInvisibleNamesHaveReadableFallbacks() {
        val runs = JSONArray().put(JSONObject().put("id", "root").put("parent_id", JSONObject.NULL))
        assertEquals(0, workflowChildCount(JSONObject().put("runs", runs)))
        runs.put(JSONObject().put("id", "child1").put("parent_id", "root"))
        runs.put(JSONObject().put("id", "child2").put("parent_id", "root"))
        assertEquals(2, workflowChildCount(JSONObject().put("runs", runs)))
        assertEquals(0, workflowChildCount(null))
        assertEquals("未命名智能体", visibleName("\u200b\u200d\u2060\u00a0", "未命名智能体"))
        assertEquals("助手", visibleName("\u202e助手\u200b", "未命名智能体"))
        assertEquals("保留用户消息", agentUserInput("保留用户消息", "", ""))
        val input = agentUserInput("user-message-U18", "role-R16", "instructions-S17")
        assertTrue(input.contains("instructions-S17"))
        assertTrue(input.contains("role-R16"))
        assertTrue(input.endsWith("user-message-U18"))
        assertTrue(input.contains("不增加权限"))
    }
}
