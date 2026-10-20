package com.mightyoung.muyon.androidlab

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.view.inputmethod.InputMethodManager
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import com.mightyoung.muyon.androidlab.agentipc.OrdinaryChatProductionConfig
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import java.io.File

/** Socket-free live-PROTOCOL end-to-end check; its usage/answers are synthetic fixtures. */
class OrdinaryChatLiveServiceLoopTest {
    @get:Rule val compose=createAndroidComposeRule<MainActivity>()
    @Test fun ordinarySendUsesSameOwnerLiveProtocolHistoryAndSettlement() {
        val app=compose.activity.application as MuyonLabApplication
        compose.onNodeWithTag("new-conversation").performClick()
        // Cold JNA/native bootstrap is read-only here. Do not spend a Send or turn
        // a five-second pre-admission timeout into an UNKNOWN request to retry.
        compose.runOnIdle{app.agents.refresh()}
        compose.waitUntil(90000){
            var connected=false
            compose.runOnIdle{
                val state=app.agents.presentation
                val snapshot=state.snapshot
                connected=state.transport==UiAgentTransport.CONNECTED && snapshot?.phase==UiAgentServicePhase.READY &&
                    snapshot.meta.serviceEpoch.isNotBlank() && state.visible && !state.observationBusy
                if(!connected && !state.observationBusy)app.agents.refresh()
            }
            connected
        }
        compose.runOnIdle{
            val state=app.agents.presentation
            assertEquals(UiAgentTransport.CONNECTED,state.transport)
            val current=checkNotNull(state.snapshot)
            assertEquals(UiAgentServicePhase.READY,current.phase);assertTrue(current.meta.serviceEpoch.isNotBlank())
            assertTrue(state.visible);assertFalse(state.observationBusy)
            assertTrue("read-only bootstrap must not create a chat request",app.chats.snapshot.conversations.isEmpty())
        }
        fun send(text:String):ChatReadConversation {
            var previous:ChatReadConversation?=null
            compose.runOnIdle{previous=app.chats.snapshot.conversations.values.singleOrNull()}
            compose.onNodeWithTag("assistant-draft").performTextReplacement(text)
            // Shell copies the Service snapshot every 100 ms. Its displayed status can
            // lag the underlying terminal snapshot, especially when SECOND is unchanged.
            compose.waitUntil(10000){
                compose.runOnIdle{previous?.let{old->
                    val current=app.chats.snapshot.conversations.values.single()
                    assertEquals("previous request changed before explicit Send",old.requestId,current.requestId)
                    assertEquals("previous terminal downgraded while waiting for UI",old.status,current.status)
                }}
                compose.onAllNodes(hasTestTag("send-service-read") and isEnabled()).fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithTag("send-service-read").assertIsEnabled().performClick()
            lateinit var request:String
            compose.runOnIdle{request=checkNotNull(app.chats.snapshot.conversations.values.single().requestId)}
            compose.activityRule.scenario.onActivity{a->(a.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager).hideSoftInputFromWindow(a.window.decorView.windowToken,0);a.window.decorView.clearFocus()}
            compose.waitUntil(60000){var terminal=false;compose.runOnIdle{terminal=app.chats.snapshot.conversations.values.single().let{it.requestId==request && it.status in setOf("completed","failed","unknown","cancelled")}};terminal}
            lateinit var result:ChatReadConversation
            compose.runOnIdle{result=app.chats.snapshot.conversations.values.single()}
            fun assertTerminalStable(){compose.runOnIdle{
                val current=app.chats.snapshot.conversations.values.single()
                assertEquals(request,current.requestId)
                assertEquals("terminal downgraded before rendered acknowledgement",result.status,current.status)
                assertEquals(result.answer,current.answer)
            }}
            compose.onNodeWithTag("local-chat-list").performScrollToNode(hasTestTag("service-read-status"))
            val label=frontendStatusLabel(result.status,result.reason)
            compose.waitUntil(10000){
                assertTerminalStable()
                compose.onAllNodes(hasTestTag("service-read-status") and hasText(label)).fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithTag("service-read-status").assertTextEquals(label).assertIsDisplayed()
            if(result.answer.isNotEmpty()){
                val answer=hasText(result.answer) and hasAnyAncestor(hasTestTag("service-read-result"))
                compose.onNodeWithTag("local-chat-list").performScrollToNode(answer)
                compose.onNode(answer).assertIsDisplayed()
            }
            assertTerminalStable()
            return result
        }
        val first=send(OrdinaryChatProductionConfig.FIRST)
        assertEquals("first reason=${first.reason}","completed",first.status);assertEquals("CANARY-4827",first.answer);assertFalse(first.synthetic);assertTrue(first.providerReceipt)
        val second=send(OrdinaryChatProductionConfig.SECOND)
        assertEquals("second reason=${second.reason}","completed",second.status);assertEquals("CANARY-4827",second.answer);assertFalse(second.synthetic);assertTrue(second.providerReceipt)
        assertNotEquals(first.requestId,second.requestId);assertNotEquals(first.originalReceiptIdentity,second.originalReceiptIdentity)
        val root=File(compose.activity.filesDir,"agent-admission-root")
        val database=File(root,"muyon-ordinary-admission-v2.sqlite")
        SQLiteDatabase.openDatabase(database.path,null,SQLiteDatabase.OPEN_READONLY).use{db->
            db.rawQuery("SELECT r.payload FROM chat_attempts t JOIN admissions a ON a.id=t.id JOIN reservations r ON r.token=a.token",null).use{rows->
                val wires=mutableListOf<JSONObject>();while(rows.moveToNext())wires+=JSONObject(String(rows.getBlob(0)))
                assertEquals(2,wires.size)
                val wire=wires.single{it.getJSONArray("messages").length()==3}
                assertEquals(OrdinaryChatProductionConfig.FIRST,wire.getJSONArray("messages").getJSONObject(0).getString("content"))
                assertEquals(first.answer,wire.getJSONArray("messages").getJSONObject(1).getString("content"))
                assertEquals(OrdinaryChatProductionConfig.SECOND,wire.getJSONArray("messages").getJSONObject(2).getString("content"))
                assertEquals(128,wire.getInt("max_tokens"));assertEquals("disabled",wire.getJSONObject("thinking").getString("type"))
            }
        }
        val candidates=root.listFiles().orEmpty().filter{it.name.startsWith("live-chat-") && it.extension=="json"}
        assertEquals(2,candidates.size)
        candidates.forEach{val candidate=JSONObject(it.readText());assertEquals("offline-live-protocol-fixture",candidate.getJSONObject("provider").getString("id"));assertEquals("CNY",candidate.getString("currency"))}
        val third=send(OrdinaryChatProductionConfig.SECOND)
        assertEquals("failed",third.status);assertEquals("provider_budget_reservation_failed",third.reason)
        SQLiteDatabase.openDatabase(database.path,null,SQLiteDatabase.OPEN_READONLY).use{db->db.rawQuery("SELECT COUNT(*) FROM chat_attempts",null).use{assertTrue(it.moveToFirst());assertEquals(2,it.getInt(0))}}
        println("OFFLINE_LIVE_PROTOCOL_SAME_OWNER_PASS vendor_requests=0 attempts=2 history=3 settled=true")
    }
}
