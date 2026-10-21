package com.mightyoung.muyon.product.chat

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.mightyoung.muyon.product.design.MuyonTheme
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class ConversationRichTextTest {
    @get:Rule val compose = createComposeRule()

    @Test fun actualRequestActivityUsesObservedFactsAndResetsForAnotherRequest() {
        // Native Observation-shaped presentation fixture; this never dispatches a provider request.
        val observation = mutableStateOf(JSONObject().put("request_id", "request-observed-17")
            .put("status", "tool_pending").put("reserved_micro_cny", "1000").put("charged_micro_cny", "10")
            .put("cancelled", false).put("recovery_action", "review_tool").put("attempted", true)
            .put("failure_stage", JSONObject.NULL).put("http_status", 200)
            .put("answer", JSONObject().put("call", JSONObject().put("id", "tool-call-observed-17")
                .put("name", "supplier_list").put("arguments", JSONObject().put("limit", 10).put("offset", 0)))))
        compose.setContent { MuyonTheme { ChatRequestActivity(observation.value) } }
        compose.onNodeWithText("调用过程 · 等待工具审核").assertIsDisplayed()
        compose.onNodeWithText("工具：supplier_list · tool-call-observed-17").assertDoesNotExist()
        compose.onNodeWithText("思考", substring = true).assertDoesNotExist()
        compose.onNodeWithText("推理", substring = true).assertDoesNotExist()
        compose.onNodeWithText(observation.value.toString()).assertDoesNotExist()
        compose.onNodeWithTag("chat-request-activity-toggle").performClick()
        compose.onNodeWithText("工具：supplier_list · tool-call-observed-17").assertIsDisplayed()
        compose.onNodeWithText("该原请求已经尝试外发。").assertIsDisplayed()

        compose.runOnIdle {
            observation.value = JSONObject(observation.value.toString()).put("status", "unknown").put("failure_stage", "transport_interrupted")
        }
        compose.onNodeWithText("调用过程 · 结果待核实").assertIsDisplayed()
        compose.onNodeWithText("中断位置：transport_interrupted").assertIsDisplayed()
        compose.onNodeWithText("已完成", substring = true).assertDoesNotExist()

        compose.runOnIdle {
            observation.value = JSONObject(observation.value.toString()).put("request_id", "request-observed-18")
                .put("status", "tool_pending").put("failure_stage", JSONObject.NULL)
        }
        compose.onNodeWithText("调用过程 · 等待工具审核").assertIsDisplayed()
        compose.onNodeWithText("工具：supplier_list · tool-call-observed-17").assertDoesNotExist()
        compose.onNodeWithText("中断位置：transport_interrupted").assertDoesNotExist()
    }

    @Test fun longBilingualParagraphsAndMarkdownKeepTheirContent() {
        val paragraph = "中文科研阅读与 English research discussion。".repeat(80)
        val inlineSource = "**重点** / *emphasis* / _斜体_ / `**raw** [code](https://example.org)` / <b>原文</b>"
        val inline = conversationInline(inlineSource, SpanStyle())
        assertEquals("重点 / emphasis / 斜体 / **raw** [code](https://example.org) / <b>原文</b>", inline.text)
        assertTrue(inline.spanStyles.any { it.item.fontWeight == FontWeight.Bold && inline.text.substring(it.start, it.end) == "重点" })
        assertTrue(inline.spanStyles.any { it.item.fontStyle == FontStyle.Italic })
        assertTrue(inline.spanStyles.any { it.item.fontFamily == FontFamily.Monospace && inline.text.substring(it.start, it.end) == "**raw** [code](https://example.org)" })
        assertTrue(inline.getStringAnnotations("URL", 0, inline.length).isEmpty())
        listOf("**尚未结束", "**错误收尾*", "*尚未结束", "`尚未结束", "paper_revision_id").forEach {
            assertEquals(it, conversationInline(it, SpanStyle()).text)
        }
        val styledLink = conversationInline("[**来源**](https://example.org/paper)", SpanStyle())
        assertEquals("来源", styledLink.text)
        assertEquals("https://example.org/paper", styledLink.getStringAnnotations("URL", 0, styledLink.length).single().item)
        val text = "# 研究结果\n\n$paragraph\n\n$inlineSource\n\n- 第一个结论\n- Second conclusion\n\n> 引用原文"
        val blocks = conversationBlocks(text)
        assertEquals(paragraph, (blocks[1] as ConversationBlock.Prose).value)
        assertEquals(1, (blocks[0] as ConversationBlock.Prose).heading)
        compose.setContent { MuyonTheme { Column(Modifier.verticalScroll(rememberScrollState())) { ConversationRichText(text) } } }
        compose.onNodeWithText("研究结果").assertIsDisplayed()
        compose.onNodeWithText(inline.text).performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("引用原文").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText(paragraph).assertExists()
    }

    @Suppress("DEPRECATION")
    @Test fun fencedCodeCopiesExactBodyAndTablesScrollHorizontally() {
        val code = "fun 示例() = \"hello\"\n  return 42"
        var clipboard: androidx.compose.ui.platform.ClipboardManager? = null
        compose.setContent {
            clipboard = LocalClipboardManager.current
            MuyonTheme { Column(Modifier.verticalScroll(rememberScrollState())) {
                ConversationRichText("```kotlin\n$code\n```\n\n| 名称 | 第二列 | 第三列 | 末列 |\n| --- | --- | --- | --- |\n| 论文 | model | value | 终点 |")
            } }
        }
        compose.onNodeWithTag("conversation-code-0").assertExists()
        compose.onNodeWithTag("conversation-copy-0").performClick()
        compose.runOnIdle { assertEquals(code, clipboard!!.getText()?.text) }
        compose.onNodeWithTag("conversation-table-1").performScrollTo().performTouchInput { swipeLeft() }
        compose.onNodeWithText("终点").assertIsDisplayed()
    }

    @Test fun unsafeSchemesHaveNoLinksAndEmptyEventsHaveNoReasoningPlaceholder() {
        val dangerous = listOf("javascript:alert", "data:text/plain,hello", "file:///tmp/a", "intent://example", "https://name:secret@example.com", "https:///missing-host")
        dangerous.forEach { target ->
            assertFalse(target, safeConversationUrl(target))
            assertTrue(conversationInline("[危险]($target)", SpanStyle()).getStringAnnotations("URL", 0, 10000).isEmpty())
        }
        val valid = conversationInline("[原始来源](https://example.org/paper)", SpanStyle())
        assertEquals("https://example.org/paper", valid.getStringAnnotations("URL", 0, valid.length).single().item)
        compose.setContent { MuyonTheme { Column {
            ConversationRichText("[危险](javascript:alert)")
            WorkflowEventSummary(JSONObject().put("summary", ""))
        } } }
        compose.onNodeWithText("[危险](javascript:alert)").assertHasNoClickAction()
        compose.onNodeWithTag("workflow-event").assertDoesNotExist()
        compose.onNodeWithText("思考中", substring = true).assertDoesNotExist()
        assertEquals("受阻", workflowStatus("blocked"))
        assertEquals("等待确认", workflowStatus("waiting_confirmation"))
        assertEquals("结果未知", workflowStatus("unknown"))
        assertNull(workflowReplyData(JSONObject("""{"status":"ok","data":{"status":"unavailable","error":"chat_operation_unavailable"}}""")))
        assertNull(workflowReplyData(JSONObject("""{"status":"ok","data":{"error":"workflow_scope_mismatch"}}""")))
        assertNull(workflowReplyData(JSONObject("""{"status":"ok","data":{"status":"unknown"}}""")))
        assertNotNull(workflowReplyData(JSONObject("""{"status":"ok","data":{"root":{"status":"unknown"},"runs":[]}}""")))
    }
}
