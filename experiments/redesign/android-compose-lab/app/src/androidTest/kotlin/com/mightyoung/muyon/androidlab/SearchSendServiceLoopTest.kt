package com.mightyoung.muyon.androidlab

import android.view.inputmethod.InputMethodManager
import android.content.Context
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.json.JSONObject
import java.io.File

/** Only searchFixture, ordinary Settings/Send controls and the real private Service/Rust Agent. */
class SearchSendServiceLoopTest {
    @get:Rule val compose=createAndroidComposeRule<MainActivity>()
    private val app get()=compose.activity.application as MuyonLabApplication
    private fun configure(connection:Boolean) {
        compose.onNodeWithTag("destination-SETTINGS").performClick()
        compose.onNodeWithTag("settings-list").performScrollToNode(hasTestTag("search-enabled"))
        if(!app.searchSettings.read().settings.enabled)compose.onNodeWithTag("search-enabled").performClick()
        compose.onNodeWithTag("settings-list").performScrollToNode(hasTestTag(if(connection)"search-connection-search-connection" else "search-connection-none"))
        compose.onNodeWithTag(if(connection)"search-connection-search-connection" else "search-connection-none").performClick()
        compose.onNodeWithTag("settings-list").performScrollToNode(hasTestTag("search-settings-save"))
        compose.onNodeWithTag("search-settings-save").performClick()
        compose.onNodeWithTag("search-settings-message").assertTextEquals("已保存；未发送任何请求")
        compose.onNodeWithTag("destination-ASSISTANT").performClick()
    }
    private fun send(text:String,status:String):ChatReadConversation {
        compose.onNodeWithTag("assistant-draft").performTextReplacement(text)
        compose.onNodeWithTag("send-service-read").assertIsEnabled().performClick()
        lateinit var request:String
        compose.runOnIdle{request=checkNotNull(app.chats.snapshot.conversations.values.single{it.text==text}.requestId)}
        try {
            compose.waitUntil(60_000){var done=false;compose.runOnIdle{done=app.chats.snapshot.conversations.values.any{it.requestId==request&&it.status==status}};done}
        } catch (timeout:ComposeTimeoutException) {
            var diagnostic="request_missing"
            compose.runOnIdle {
                app.chats.snapshot.conversations.values.singleOrNull{it.requestId==request}?.let { value->
                    // Fixed protocol states and presence flags only; no business text or secrets.
                    val state=value.status.takeIf{it in setOf("submitting","reconciling","accepted","existing","events","completed","failed","cancelled","outcome_unknown","unknown","rejected")} ?: "invalid"
                    diagnostic="state=$state cursor=${value.cursor} run=${value.runId!=null} synthetic=${value.synthetic} receipt=${value.receipt!=null} tool=${value.toolResult!=null}"
                }
            }
            throw AssertionError("search_send_terminal_timeout expected=$status $diagnostic",timeout)
        }
        compose.activityRule.scenario.onActivity{activity->(activity.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager).hideSoftInputFromWindow(activity.window.decorView.windowToken,0);activity.window.decorView.clearFocus()}
        compose.waitForIdle()
        var value:ChatReadConversation?=null;compose.runOnIdle{value=app.chats.snapshot.conversations.values.single{it.requestId==request}}
        return checkNotNull(value)
    }
    private fun outbound(result:ChatReadConversation):File=File(compose.activity.filesDir,"agent-service-root/native-agent-service-v1/${result.runId}/search-outbound.db")
    @Test fun settingsSaveThenOrdinarySendShowsSourceEmptyAndControlledError() {
        val before=File(compose.activity.filesDir,"agent-service-root").walkTopDown().count{it.name=="search-outbound.db"}
        configure(true)
        assertEquals(before,File(compose.activity.filesDir,"agent-service-root").walkTopDown().count{it.name=="search-outbound.db"})
        compose.onNodeWithTag("new-conversation").performClick()
        val first=send("find fixture","completed")
        assertTrue(first.synthetic);assertTrue(first.toolReceipt);assertNotNull(first.toolResult);assertEquals("https://example.org/source",first.toolResult!!.sources.single().url)
        compose.onNodeWithTag("local-chat-list").performScrollToNode(hasTestTag("search-source-url-1"))
        compose.onNodeWithTag("search-source-url-1").assertTextEquals("https://example.org/source")
        compose.onNodeWithTag("local-chat-list").performScrollToNode(hasTestTag("search-cost"));compose.onNodeWithTag("search-cost").assertTextEquals("USD 750/1,000,000 · 合成账本估值，非真实计费")
        val ledger=JSONObject(outbound(first).readText());assertTrue(ledger.getBoolean("synthetic"));assertEquals("nonempty",ledger.getString("status"))
        val payload=JSONObject(ledger.getString("payload"));assertEquals(setOf("query","count","need_content"),payload.keys().asSequence().toSet())
        val empty=send("empty fixture","completed");assertNotEquals(first.requestId,empty.requestId);assertTrue(empty.toolResult!!.empty);assertEquals(0L,empty.toolResult!!.costMicros)
        compose.onNodeWithTag("local-chat-list").performScrollToNode(hasTestTag("search-empty-result"));compose.onNodeWithTag("search-empty-result").assertIsDisplayed()
        val failed=send("error fixture","failed");assertEquals("search_authentication_failed",failed.reason);assertNull(failed.toolResult);assertTrue(failed.answer.isEmpty())
        assertEquals("failed",JSONObject(outbound(failed).readText()).getString("status"))
    }
    @Test fun enabledButUnconfiguredOrdinarySendNeverInventsAvailableHostOrSearchResult() {
        configure(false);repeat(4){compose.onNodeWithTag("new-conversation").performClick()}
        val failed=send("unconfigured fixture","failed");assertEquals("search_unconfigured",failed.reason);assertNull(failed.toolResult);assertNull(failed.receipt);assertFalse(outbound(failed).exists())
    }
}
