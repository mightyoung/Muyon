package com.mightyoung.muyon.product.chat

import android.content.ContextWrapper
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.product.agentipc.ProductClient
import com.mightyoung.muyon.product.agents.AgentCatalog
import com.mightyoung.muyon.product.agents.AgentProfile
import com.mightyoung.muyon.product.design.MuyonTheme
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class ChatConfigurationRestoreTest {
    @get:Rule val compose = createComposeRule()

    @Test fun returningToChatRestoresCurrentRuntimeConfigurationWithoutSending() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val namespace = "configuration_restore_${UUID.randomUUID()}"
        val isolated = object : ContextWrapper(context) {
            override fun getSharedPreferences(name: String, mode: Int) = super.getSharedPreferences("$namespace-$name", mode)
        }
        val ready = CountDownLatch(1)
        lateinit var client: ProductClient
        instrumentation.runOnMainSync { client = ProductClient(context) { if (it) ready.countDown() }; client.bind() }
        try {
            assertTrue(ready.await(15, TimeUnit.SECONDS))
            val initialized = CountDownLatch(1)
            var initReply: JSONObject? = null
            instrumentation.runOnMainSync {
                client.call(if (client.workspaceExists) "health" else "initialize") { initReply = it; initialized.countDown() }
            }
            assertTrue(initialized.await(35, TimeUnit.SECONDS))
            assertEquals("ok", initReply?.optString("status"))
            val configured = CountDownLatch(1)
            var configReply: JSONObject? = null
            instrumentation.runOnMainSync {
                // Non-provider fixture credential; configuration makes no network request.
                client.configureChat(JSONObject().put("cap_micro_cny", "1000000").put("max_calls", "10")
                    .put("chat", true).put("search", true), "fixture-configuration-no-outbound-17".toCharArray()) {
                    configReply = it; configured.countDown()
                }
            }
            assertTrue(configured.await(35, TimeUnit.SECONDS))
            assertEquals("ok", configReply?.optString("status"))
            val catalog = AgentCatalog(isolated)
            catalog.saveAgent(AgentProfile(namespace, "测试助手", "saved-role-R16", "saved-instructions-S17"))
            val profile = catalog.read().agents.single { it.id == namespace }
            val shown = mutableStateOf(true)
            compose.setContent { CompositionLocalProvider(LocalContext provides isolated) {
                MuyonTheme { if (shown.value) ChatScreen(client, null, namespace,
                    agentRole = profile.role, agentInstructions = profile.instructions) }
            } }
            compose.onNodeWithTag("chat-draft").performTextInput("仅检查恢复状态，不点击发送")
            compose.waitUntil(15_000) { compose.onAllNodesWithTag("chat-send").fetchSemanticsNodes().size == 1 &&
                compose.onAllNodes(hasTestTag("chat-send") and isEnabled()).fetchSemanticsNodes().size == 1 }
            compose.runOnIdle { shown.value = false }
            compose.onNodeWithTag("chat-send").assertDoesNotExist()
            compose.runOnIdle { shown.value = true }
            compose.onNodeWithTag("chat-draft").performTextInput("返回标签后依旧可以预览")
            compose.waitUntil(15_000) { compose.onAllNodes(hasTestTag("chat-send") and isEnabled()).fetchSemanticsNodes().size == 1 }
            compose.onNodeWithTag("chat-send").assertIsEnabled()
            // Actual UI → Binder → Rust plan. Fixture configuration cannot send.
            compose.onNodeWithTag("chat-send").performClick()
            compose.waitUntil(15_000) {
                compose.onAllNodesWithText("saved-instructions-S17", substring = true).fetchSemanticsNodes().size == 1
            }
            compose.onNodeWithText("saved-instructions-S17", substring = true)
                .assertTextContains("saved-role-R16", substring = true)
                .assertTextContains("用户选择的助手角色说明", substring = true)
                .assertTextContains("\"role\": \"user\"", substring = true)
            compose.onNodeWithText("确认本次外发").assertIsNotEnabled()
        } finally {
            instrumentation.runOnMainSync { client.close() }
            context.deleteSharedPreferences("$namespace-product-chat-state")
            context.deleteSharedPreferences("$namespace-${AgentCatalog.PREFERENCES}")
        }
    }
}
