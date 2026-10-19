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
        // Same conversation, second explicit request exceeds the synthetic durable one-call ceiling.
        compose.onNodeWithTag("assistant-draft").performTextReplacement("第二条普通文本")
        compose.onNodeWithTag("send-service-read").assertIsEnabled().performClick()
        hideKeyboard()
        waitStatus("执行失败")
        assertEquals(1,attempts())
        println("ORDINARY_CHAT_COMPOSE_SERVICE_AGENT_PASS synthetic=true network=false original_run=${completed.runId} attempts=1 ui_pid=${Process.myPid()} agent_pid=${agent.pid}")
    }
}
