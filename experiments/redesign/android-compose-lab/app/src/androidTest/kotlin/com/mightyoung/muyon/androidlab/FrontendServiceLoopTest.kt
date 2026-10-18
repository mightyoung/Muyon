package com.mightyoung.muyon.androidlab

import android.app.ActivityManager
import android.content.Context
import android.os.Process
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

/** Actual Activity/Application/Binder/native read acceptance. Synthetic schema12, no model API.
 * Requires the packaged bridge inputs and an API26+ emulator/device; no fake port is installed.
 */
class FrontendServiceLoopTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    private fun newConversation() {
        compose.onNodeWithTag("new-conversation").performClick()
        compose.onNodeWithTag("assistant-draft").performTextReplacement("")
    }

    private fun awaitTag(tag:String) {
        compose.waitUntil(timeoutMillis=60_000) {
            compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
        }
    }

    @Test fun realPrivateServiceReadRendersSyntheticProjectionAndOriginalReceipt() {
        newConversation()
        val prompt="读取当前测试供应商名称 ${System.nanoTime()}"
        compose.onNodeWithTag("assistant-draft").performTextInput(prompt)
        compose.onNodeWithTag("send-service-read").assertIsEnabled().performClick()
        awaitTag("service-read-input")
        compose.onNodeWithTag("local-chat-list").performScrollToNode(hasTestTag("service-read-input"))
        compose.onNodeWithTag("service-read-input").assertExists()
        compose.onNodeWithText(prompt).assertExists()
        awaitTag("service-read-receipt")
        compose.waitUntil(timeoutMillis=60_000) {
            compose.onAllNodes(hasTestTag("service-read-status") and hasText("已完成")).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("local-chat-list").performScrollToNode(hasTestTag("service-read-projection"))
        compose.onNodeWithTag("service-read-projection").assertTextEquals("合成供应商甲")
        compose.onNodeWithTag("service-read-status").assertTextEquals("已完成")
        val rendered=compose.onNodeWithTag("service-read-receipt").fetchSemanticsNode()
            .config[SemanticsProperties.Text].joinToString("") { it.text }
        assertTrue("original receipt must be rendered",rendered.startsWith("原始回执："))
        val receipt=JSONObject(rendered.removePrefix("原始回执："))
        assertEquals("ToolRegistry",receipt.getString("owner"))
        assertEquals("host-supplier-name-read",receipt.getString("binding_id"))
        assertTrue(receipt.getString("invocation_id").isNotBlank())
        assertTrue(Regex("[0-9a-f]{32}").matches(receipt.getString("identity")))
        compose.onNodeWithTag("port-disconnected").assertTextContains("synthetic schema12")
        compose.onNodeWithTag("port-disconnected").assertTextContains("无真实模型")
        // Own-UID process information: verifies the live :agent process without test-only APIs.
        val context=compose.activity.applicationContext
        val manager=context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val processes=manager.runningAppProcesses.orEmpty()
        val agent=processes.singleOrNull { it.processName=="${context.packageName}:agent" }
        assertNotNull("private :agent process must exist after a real read",agent)
        assertTrue("Service must run outside the UI process",agent!!.pid!=Process.myPid())
        assertEquals(Process.myUid(),agent.uid)
        println("API26_REAL_PRIVATE_READ_PASS ui_pid=${Process.myPid()} agent_pid=${agent.pid} receipt_identity=${receipt.getString("identity")} synthetic_schema12=true model_api_called=false")
        val originalIdentity=receipt.getString("identity")
        val originalPid=agent.pid
        // Bound strictly to this tested application's own private Service child.
        check(agent.processName=="${context.packageName}:agent" && agent.uid==Process.myUid() && originalPid!=Process.myPid())
        Process.killProcess(originalPid)
        awaitTag("service-read-historical-receipt")
        compose.onNodeWithTag("service-read-historical-receipt").assertTextContains(originalIdentity)
        compose.onNodeWithTag("service-read-status").assertTextContains("状态未知")
        compose.onNodeWithTag("service-read-receipt").assertDoesNotExist()
        compose.onNodeWithTag("service-read-projection").assertDoesNotExist()
        compose.onNodeWithTag("send-service-read").assertIsNotEnabled()
        // Existing request lookup only: never click Send or replace the original input.
        compose.onNodeWithTag("local-chat-list").performScrollToNode(hasTestTag("reconcile-service-read"))
        compose.onNodeWithTag("reconcile-service-read").performClick()
        awaitTag("service-read-receipt")
        compose.waitUntil(timeoutMillis=60_000) {
            compose.onAllNodes(hasTestTag("service-read-status") and hasText("已完成")).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("service-read-projection").assertTextEquals("合成供应商甲")
        val recoveredText=compose.onNodeWithTag("service-read-receipt").fetchSemanticsNode()
            .config[SemanticsProperties.Text].joinToString("") { it.text }
        val recoveredReceipt=JSONObject(recoveredText.removePrefix("原始回执："))
        assertEquals("lookup must preserve the original receipt",originalIdentity,recoveredReceipt.getString("identity"))
        assertEquals(receipt.getString("invocation_id"),recoveredReceipt.getString("invocation_id"))
        val restartedAgent=manager.runningAppProcesses.orEmpty().singleOrNull { it.processName=="${context.packageName}:agent" }
        assertNotNull("lookup must reconnect to a live private Service",restartedAgent)
        assertEquals(Process.myUid(),restartedAgent!!.uid)
        assertTrue(restartedAgent.pid!=originalPid && restartedAgent.pid!=Process.myPid())
        println("API26_REAL_BINDER_RECOVERY_PASS old_agent_pid=$originalPid new_agent_pid=${restartedAgent.pid} original_receipt_identity=$originalIdentity lookup_only=true model_api_called=false")
    }

    @Test fun invalidInputCannotDispatchAndSaveRemainsLocal() {
        newConversation()
        compose.onNodeWithTag("send-service-read").assertIsNotEnabled()
        compose.onNodeWithTag("assistant-draft").performTextReplacement(" \n\t")
        compose.onNodeWithTag("send-service-read").assertIsNotEnabled()
        compose.onNodeWithTag("assistant-draft").performTextReplacement("供".repeat(1366))
        compose.onNodeWithTag("send-service-read").assertIsNotEnabled()
        compose.onNodeWithTag("assistant-draft").performTextReplacement("仅保存本地，不发送")
        compose.onNodeWithTag("save-local-note").assertIsEnabled().performClick()
        compose.onNodeWithTag("assistant-draft").assertTextEquals("")
        compose.onNodeWithTag("send-service-read").assertIsNotEnabled()
        compose.onNodeWithTag("local-chat-list").performScrollToNode(hasText("你 · 本地记录，未发送"))
        compose.onNodeWithText("你 · 本地记录，未发送").assertIsDisplayed()
        println("API26_FRONTEND_INPUT_VALIDATION_PASS no_send_clicked=true model_api_called=false")
    }
}
