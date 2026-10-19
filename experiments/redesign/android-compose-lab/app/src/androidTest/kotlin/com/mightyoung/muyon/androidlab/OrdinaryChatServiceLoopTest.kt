package com.mightyoung.muyon.androidlab

import android.app.ActivityManager
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.os.Process
import android.view.inputmethod.InputMethodManager
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import java.io.File
import org.json.JSONObject

/** Exact named no-network test, only ordinaryChat compile-time APK and NEW schema/root. */
class OrdinaryChatServiceLoopTest {
    @get:Rule val compose=createAndroidComposeRule<MainActivity>()
    private fun hideKeyboard() {
        compose.activityRule.scenario.onActivity { activity->
            (activity.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager).hideSoftInputFromWindow(activity.window.decorView.windowToken,0)
            activity.window.decorView.clearFocus()
        }
        compose.waitForIdle()
    }
    private fun waitStatus(status:String) {compose.waitUntil(60_000){compose.onAllNodes(hasTestTag("service-read-status") and hasText(status)).fetchSemanticsNodes().isNotEmpty()}}
    @Test fun composeSendUsesPrivateServiceSameRustAgentAndDisplaysPlainProviderAnswer() {
        compose.onNodeWithTag("new-conversation").performClick()
        val prompt="请概括这条普通文本"
        compose.onNodeWithTag("assistant-draft").performTextReplacement(prompt)
        compose.onNodeWithTag("send-service-read").assertIsEnabled().performClick()
        hideKeyboard()
        waitStatus("已完成")
        val application=compose.activity.application as MuyonLabApplication
        var first:ChatReadConversation?=null
        compose.runOnIdle {first=application.chats.snapshot.conversations.values.single{it.text==prompt}}
        val completed=checkNotNull(first)
        val conversationId=application.chats.snapshot.conversations.entries.single{it.value.requestId==completed.requestId}.key
        assertEquals("离线普通文本响应",completed.answer)
        assertTrue(completed.providerReceipt);assertNull(completed.projection);assertNotNull(completed.receipt)
        assertNotNull(completed.runId);assertTrue(completed.synthetic)
        compose.onNodeWithTag("local-chat-list").performScrollToNode(hasText("离线普通文本响应"))
        compose.onNodeWithText("离线普通文本响应").assertIsDisplayed()
        val context=compose.activity.applicationContext
        val manager=context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val agent=manager.runningAppProcesses.orEmpty().single{it.processName=="${context.packageName}:agent"}
        assertEquals(Process.myUid(),agent.uid);assertNotEquals(Process.myPid(),agent.pid)
        val file=File(context.filesDir,"agent-admission-root/muyon-ordinary-admission-v2.sqlite")
        fun attempts():Int=SQLiteDatabase.openDatabase(file.path,null,SQLiteDatabase.OPEN_READONLY).use{db->db.rawQuery("SELECT COUNT(*) FROM chat_attempts",null).use{c->check(c.moveToFirst());c.getInt(0)}}
        assertEquals(1,attempts())
        compose.activityRule.scenario.recreate()
        compose.runOnIdle {
            val original=(compose.activity.application as MuyonLabApplication).chats.snapshot.conversations.values.single{it.text==prompt}
            assertEquals(completed.requestId,original.requestId);assertEquals(completed.runId,original.runId);assertEquals(completed.originalReceiptIdentity,original.originalReceiptIdentity)
        }
        // Recreation stops the last visible lease. Its unknown disclosure must never
        // be treated as a completed run or silently enable another admission.
        waitStatus(frontendStatusLabel("unknown"))
        compose.onNodeWithTag("assistant-draft").performTextReplacement("第二条普通文本")
        compose.onNodeWithTag("send-service-read").assertIsNotEnabled()
        hideKeyboard()
        compose.runOnIdle {
            val unknown=application.chats.snapshot.conversations.values.single{it.text==prompt}
            assertEquals("unknown",unknown.status);assertTrue(unknown.answer.isEmpty());assertNull(unknown.receipt)
            assertEquals(completed.admittedServiceEpoch,unknown.admittedServiceEpoch)
            assertEquals(completed.originalReceiptIdentity,unknown.originalReceiptIdentity)
        }
        assertEquals(1,attempts())
        // release() changes transport before the asynchronous stop finishes. Wait
        // for its existing completion publication, not elapsed time or Send enabled.
        compose.waitUntil(60_000) {
            val state=application.agents.presentation
            state.transport==UiAgentTransport.UNBOUND && state.message.startsWith("已请求停止并解除绑定")
        }
        compose.onNodeWithTag("local-chat-list").performScrollToNode(hasTestTag("reconcile-service-read"))
        compose.onNodeWithTag("reconcile-service-read").performClick()
        waitStatus("已完成")
        compose.runOnIdle {
            val restored=application.chats.snapshot.conversations.values.single{it.text==prompt}
            assertEquals(completed.requestId,restored.requestId);assertEquals(completed.runId,restored.runId)
            assertEquals(completed.admittedServiceEpoch,restored.admittedServiceEpoch)
            assertEquals(completed.originalReceiptIdentity,restored.originalReceiptIdentity)
            assertEquals(completed.answer,restored.answer);assertTrue(restored.providerReceipt);assertNotNull(restored.receipt)
        }
        assertEquals(1,attempts())
        // Same original conversation, new explicit request through the same owner/Service.
        val secondPrompt="第二条普通文本"
        compose.onNodeWithTag("assistant-draft").performTextReplacement(secondPrompt)
        compose.onNodeWithTag("send-service-read").assertIsEnabled().performClick()
        hideKeyboard()
        waitStatus("已完成")
        lateinit var second:ChatReadConversation
        compose.runOnIdle {
            second=checkNotNull(application.chats.snapshot.conversations[conversationId])
            assertEquals(1,application.chats.snapshot.conversations.size)
            assertEquals(secondPrompt,second.text);assertEquals("离线普通文本响应",second.answer)
            assertTrue(second.providerReceipt);assertTrue(second.synthetic);assertNull(second.projection)
            assertNotNull(second.requestId);assertNotEquals(completed.requestId,second.requestId)
            assertNotNull(second.runId);assertNotEquals(completed.runId,second.runId)
            assertNotNull(second.originalReceiptIdentity);assertNotEquals(completed.originalReceiptIdentity,second.originalReceiptIdentity)
            assertEquals(completed.admittedServiceEpoch,second.admittedServiceEpoch)
        }
        compose.onNodeWithTag("local-chat-list").performScrollToNode(hasText(secondPrompt))
        compose.onNodeWithText(secondPrompt).assertIsDisplayed()
        compose.onNodeWithTag("local-chat-list").performScrollToNode(hasText("离线普通文本响应"))
        compose.onNodeWithText("离线普通文本响应").assertIsDisplayed()
        assertEquals(agent.pid,manager.runningAppProcesses.orEmpty().single{it.processName=="${context.packageName}:agent"}.pid)
        assertEquals(2,attempts())
        // Inspect the SAME owner's durable attempted contexts and exact wire bytes.
        SQLiteDatabase.openDatabase(file.path,null,SQLiteDatabase.OPEN_READONLY).use { db->
            db.rawQuery("SELECT t.context,r.payload FROM chat_attempts t JOIN admissions a ON a.id=t.id JOIN reservations r ON r.token=a.token",null).use { rows->
                val observed=mutableMapOf<String,String>()
                val tasks=mutableSetOf<String>();val taskAttempts=mutableSetOf<String>()
                while(rows.moveToNext()) {
                    val binding=JSONObject(String(rows.getBlob(0),Charsets.UTF_8))
                    assertEquals(conversationId,binding.getString("conversation"))
                    assertEquals("ordinary-fixture-workspace",binding.getString("workspace"))
                    tasks+=binding.getString("task");taskAttempts+=binding.getString("attempt")
                    val body=JSONObject(String(rows.getBlob(1),Charsets.UTF_8))
                    assertEquals("ordinary-fixture-model",body.getString("model"))
                    assertEquals(1,body.getJSONArray("messages").length())
                    observed[binding.getString("input_ref")]=body.getJSONArray("messages").getJSONObject(0).getString("content")
                }
                assertEquals(mapOf("${completed.runId}:${completed.requestId}" to prompt,"${second.runId}:${second.requestId}" to secondPrompt),observed)
                assertEquals(2,tasks.size);assertEquals(2,taskAttempts.size)
            }
        }
        // A third explicit Send cannot exceed the unchanged per-call budget or the two-call ceiling.
        val thirdPrompt="第三条预算不足的普通文本"
        compose.onNodeWithTag("assistant-draft").performTextReplacement(thirdPrompt)
        compose.onNodeWithTag("send-service-read").assertIsEnabled().performClick()
        hideKeyboard()
        waitStatus("预算不足 · 未发送到 provider")
        lateinit var failed:ChatReadConversation
        compose.runOnIdle {
            failed=checkNotNull(application.chats.snapshot.conversations[conversationId])
            assertEquals("failed",failed.status);assertEquals("provider_budget_reservation_failed",failed.reason)
            assertEquals(thirdPrompt,failed.text);assertNotEquals(second.requestId,failed.requestId)
            assertNotNull(failed.runId);assertNotEquals(second.runId,failed.runId)
            assertEquals(second.admittedServiceEpoch,failed.admittedServiceEpoch)
            assertTrue(failed.answer.isEmpty());assertNull(failed.receipt);assertNull(failed.originalReceiptIdentity)
            assertFalse(failed.providerReceipt);assertNull(failed.projection);assertEquals(1L,failed.cursor)
        }
        assertEquals(2,attempts())
        compose.onNodeWithTag("local-chat-list").performScrollToNode(hasTestTag("service-read-reason"))
        compose.onNodeWithTag("service-read-reason").assertTextEquals("原因：provider_budget_reservation_failed")
        compose.onNodeWithTag("local-chat-list").performScrollToNode(hasTestTag("service-read-budget-guidance"))
        compose.onNodeWithTag("service-read-budget-guidance").assertTextContains("预算更新后请手动发送",substring=true)
        // Read-only lookup must preserve the exact failure, not replace its reason with envelope "none".
        compose.onNodeWithTag("local-chat-list").performScrollToNode(hasTestTag("reconcile-service-read"))
        compose.onNodeWithTag("reconcile-service-read").performClick()
        compose.waitUntil(60_000) {
            val lookedUp=application.chats.snapshot.conversations[conversationId]
            lookedUp!==failed && lookedUp?.status=="failed"
        }
        compose.waitForIdle()
        compose.runOnIdle {assertEquals(failed,application.chats.snapshot.conversations[conversationId])}
        assertEquals(2,attempts())
        println("ORDINARY_CHAT_COMPOSE_SERVICE_AGENT_PASS synthetic=true network=false original_run=${completed.runId} second_run=${second.runId} budget_reason=${failed.reason} attempts=2 ui_pid=${Process.myPid()} agent_pid=${agent.pid}")
    }
}
