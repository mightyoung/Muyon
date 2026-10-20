package com.mightyoung.muyon.product

import android.content.Context
import android.content.ContextWrapper
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.product.agentipc.ProductClient
import com.mightyoung.muyon.product.chat.ChatScreen
import com.mightyoung.muyon.product.design.MuyonTheme
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class ChatOriginPresentationTest {
    @get:Rule val compose = createComposeRule()

    @Test fun oldRequestRecoveryShowsOriginalIdentityInsideAnotherGroup() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val namespace = "origin_presentation_${UUID.randomUUID()}"
        val isolated = object : ContextWrapper(context) {
            override fun getSharedPreferences(name: String, mode: Int) = super.getSharedPreferences("$namespace-$name", mode)
        }
        val saved = isolated.getSharedPreferences("product-chat-state", Context.MODE_PRIVATE)
        // A local unresolved-marker fixture, never a fabricated response or business receipt.
        assertTrue(saved.edit().putString("original_request", UUID.randomUUID().toString())
            .putString("original_request_conversation_key", "agent:original-a")
            .putString("original_request_display_name", "原始助手A").commit())
        val ready = CountDownLatch(1)
        lateinit var client: ProductClient
        instrumentation.runOnMainSync { client = ProductClient(context) { connected -> if (connected) ready.countDown() }; client.bind() }
        try {
            assertTrue(ready.await(15, TimeUnit.SECONDS))
            compose.setContent {
                CompositionLocalProvider(LocalContext provides isolated) {
                    MuyonTheme { ChatScreen(client, null, "group:current-b", "当前群组B", listOf("成员B", "成员C")) }
                }
            }
            compose.onNodeWithText("原请求 · 原始助手A · 会话 agent:original-a").performScrollTo().assertIsDisplayed()
            compose.onNodeWithText("查询原结果").assertExists()
            compose.onNodeWithTag("chat-original-origin").assertTextContains("原始助手A").assertTextContains("agent:original-a")
            assertNotNull(saved.getString("conversation:group:current-b", null))
            assertNull(context.getSharedPreferences("product-chat-state", 0).getString("conversation:group:current-b", null))
        } finally {
            instrumentation.runOnMainSync { client.close() }
            context.deleteSharedPreferences("$namespace-product-chat-state")
        }
    }
}
