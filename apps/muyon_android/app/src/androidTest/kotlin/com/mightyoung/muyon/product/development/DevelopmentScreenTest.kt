package com.mightyoung.muyon.product.development

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.product.ui.system.FoundationTheme
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import java.util.UUID

class DevelopmentScreenTest {
    @get:Rule val compose = createComposeRule()

    private fun snapshot(conversation: String, revision: String = "1") = JSONObject().put("draft_ref",
        JSONObject().put("draft_id", "local-draft").put("revision", revision))
        .put("content", JSONObject().put("conversation_id", conversation).put("edit_revision", revision)
            .put("project", JSONObject().put("state", "new").put("project_id", "new-project")))

    private fun scopeData() = JSONObject().put("status", "scope_current").put("scope_generation", 7L)

    @Test fun openingAndPreparingNeverConfirmsCreation() {
        val conversation = UUID.randomUUID().toString()
        val methods = mutableListOf<String>()
        compose.setContent {
            FoundationTheme { DevelopmentEditor(conversation, null) { method, payload, callback ->
                methods += method
                if (method.startsWith("development_")) assertEquals(7L, payload.getLong("scope_generation"))
                if (method == "development_confirm_project") {
                    assertEquals("displayed-plan", payload.getString("plan_id"))
                    assertEquals("displayed-binding", payload.getString("binding_digest"))
                }
                val data = if (method == "chat_scope_current") scopeData() else JSONObject().put("snapshot", snapshot(conversation)).put("scope_generation", 7L)
                if (method == "development_prepare_project") data.put("plan", JSONObject().put("plan_id", "displayed-plan")
                    .put("operation", "ProjectCreate").put("name", "用户项目").put("id", "new-project")).put("binding_digest", "displayed-binding")
                callback(JSONObject().put("status", "ok").put("data", data))
            } }
        }
        compose.runOnIdle { assertEquals(listOf("chat_scope_current"), methods) }
        compose.onNodeWithTag("development-confirm-project").assertDoesNotExist()
        compose.onNodeWithTag("development-open").performClick()
        compose.onNodeWithTag("development-prepare-project").performScrollTo().performClick()
        compose.onNodeWithTag("development-project-plan").assertExists()
        compose.onNodeWithTag("development-confirm-project").performScrollTo().assertIsEnabled()
        compose.runOnIdle { assertEquals(listOf("chat_scope_current", "development_open", "development_prepare_project"), methods) }
        compose.onNodeWithTag("development-confirm-project").performClick()
        compose.runOnIdle { assertEquals(1, methods.count { it == "development_confirm_project" }) }
        compose.onNodeWithTag("development-confirm-project").assertDoesNotExist()
    }

    @Test fun blockedModelPreviewCannotSendAndRequiresExplicitAvailabilityAndPreview() {
        val conversation = UUID.randomUUID().toString()
        val methods = mutableListOf<String>()
        compose.setContent {
            FoundationTheme { DevelopmentEditor(conversation, null) { method, _, callback ->
                methods += method
                val data = when (method) {
                    "chat_scope_current" -> scopeData()
                    "agent_availability" -> JSONObject().put("configured", true)
                    else -> JSONObject().put("request_id", "blocked-request").put("send_allowed", false)
                    .put("blocked_reason", "price_proof_required").put("reserved_micro_cny", "100")
                    .put("outbound_endpoint", "https://example.invalid/chat").put("outbound_preview", JSONObject().put("messages", "实际完整内容"))
                }
                callback(JSONObject().put("status", "ok").put("data", data))
            } }
        }
        compose.runOnIdle { assertEquals(listOf("chat_scope_current"), methods) }
        compose.onNodeWithText("检查模型可用性").performScrollTo().performClick()
        compose.onNodeWithText("需要整理的开发内容").performScrollTo().performTextInput("整理需求")
        compose.onNodeWithText("预览模型整理请求").performScrollTo().performClick()
        compose.onNodeWithText("阻断原因：price_proof_required").assertExists()
        compose.onNodeWithTag("development-confirm-model").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("development-confirm-project").assertDoesNotExist()
        compose.runOnIdle { assertEquals(listOf("chat_scope_current", "agent_availability", "chat_prepare_development"), methods) }
    }

    @Test fun revisionConflictRetainsUserInputAndWaitsForExplicitReread() {
        val conversation = UUID.randomUUID().toString()
        val methods = mutableListOf<String>()
        compose.setContent {
            FoundationTheme { DevelopmentEditor(conversation, null) { method, payload, callback ->
                methods += method
                if (method == "development_update") {
                    assertEquals("1", payload.getString("expected_revision"))
                    assertEquals("local-draft", payload.getString("draft_id"))
                    callback(JSONObject().put("status", "rejected").put("error", "revision_conflict"))
                } else callback(JSONObject().put("status", "ok").put("data", if (method == "chat_scope_current") scopeData()
                    else JSONObject().put("snapshot", snapshot(conversation)).put("scope_generation", 7L)))
            } }
        }
        compose.onNodeWithTag("development-open").performClick()
        compose.onNodeWithText("项目名草稿").performScrollTo().performTextInput("保留手工输入")
        compose.onNodeWithText("保存项目名草稿").performScrollTo().performClick()
        compose.onNodeWithText("项目名草稿").assertTextContains("保留手工输入")
        compose.onNodeWithText("保存项目名草稿").assertIsNotEnabled()
        compose.runOnIdle { assertEquals(listOf("chat_scope_current", "development_open", "development_update"), methods) }
        compose.onNodeWithTag("development-open").performScrollTo().performClick()
        compose.onNodeWithText("项目名草稿").assertTextContains("保留手工输入")
        compose.runOnIdle { assertEquals(listOf("chat_scope_current", "development_open", "development_update", "development_open"), methods) }
    }

    @Test fun unsavedOriginalProposalOffersExplicitCancelWithoutAcceptingOrSending() {
        val conversation = UUID.randomUUID().toString()
        val scope = developmentScopeKey(conversation, null)
        InstrumentationRegistry.getInstrumentation().targetContext.getSharedPreferences("product-development-ui", 0)
            .edit().putString("proposal-request:$scope", "original-proposal-request")
            .putString("proposal-draft:$scope", "proposal-draft").commit()
        val methods = mutableListOf<String>()
        compose.setContent {
            FoundationTheme { DevelopmentEditor(conversation, null) { method, payload, callback ->
                methods += method
                val data = when (method) {
                    "chat_scope_current" -> scopeData()
                    "development_open" -> JSONObject().put("snapshot", snapshot(conversation)).put("scope_generation", 7L)
                    "development_lookup_proposal" -> {
                        assertEquals("original-proposal-request", payload.getString("request_id"))
                        assertEquals(7L, payload.getLong("scope_generation"))
                        JSONObject().put("status", "not_saved").put("scope_generation", 7L)
                    }
                    "chat_cancel" -> {
                        assertEquals("original-proposal-request", payload.getString("request_id"))
                        JSONObject().put("status", "cancelled")
                    }
                    else -> error("Unexpected action: $method")
                }
                callback(JSONObject().put("status", "ok").put("data", data))
            } }
        }
        compose.onNodeWithTag("development-open").performClick()
        compose.onNodeWithTag("development-lookup-proposal").performScrollTo().performClick()
        compose.onNodeWithTag("development-notice").assertTextContains("原工具仍待处理", substring = true)
        compose.onNodeWithTag("development-cancel-unsaved-proposal").performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals(listOf("chat_scope_current", "development_open", "development_lookup_proposal", "chat_cancel"), methods)
        }
        compose.onNodeWithText("查询原提案模型结果").assertExists()
    }
}
