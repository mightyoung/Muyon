package com.mightyoung.muyon.product

import android.graphics.Bitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.product.agents.AgentCatalog
import com.mightyoung.muyon.product.agents.AgentGroup
import com.mightyoung.muyon.product.agents.AgentProfile
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

/** Actual Activity navigation, durable namespaces and IME; no provider or fabricated replies. */
class WorkbenchNavigationTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    private fun navigate(destination: String) {
        if (compose.onAllNodesWithTag("nav-$destination").fetchSemanticsNodes().isEmpty()) {
            compose.onNodeWithContentDescription("打开工作空间导航").performClick()
        }
        compose.onNodeWithTag("nav-$destination").performClick()
    }

    private fun capture(name: String) {
        compose.waitForIdle()
        val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        val folder = File(context.getExternalFilesDir(null), "design-evidence").also { check(it.mkdirs() || it.isDirectory) }
        File(folder, "$name.png").outputStream().use { check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
        bitmap.recycle()
    }

    @Test fun agentAndGroupNavigationPreservesSeparateConversationsAndGlobalReceiptMarkers() {
        compose.waitUntil(15_000) {
            compose.onAllNodesWithText("创建新工作台").fetchSemanticsNodes().isNotEmpty() ||
                compose.onAllNodesWithTag("chat-send").fetchSemanticsNodes().isNotEmpty()
        }
        if (compose.onAllNodesWithText("创建新工作台").fetchSemanticsNodes().isNotEmpty()) {
            compose.onNodeWithText("创建新工作台").performClick()
        }
        compose.waitUntil(15_000) { compose.onAllNodesWithTag("chat-send").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("chat-availability").assertDoesNotExist()
        compose.onNodeWithText("模型与预算设置").assertDoesNotExist()
        compose.onNodeWithText("读取供应商").assertDoesNotExist()
        compose.onNodeWithTag("chat-more").performClick()
        compose.onNodeWithText("模型与预算设置").performClick()
        compose.onNodeWithTag("chat-availability").assertExists()
        compose.onNodeWithText("取消").performClick()
        capture("00-chat-home")
        InstrumentationRegistry.getArguments().getString("expected_font_scale")?.toFloat()?.let { expected ->
            assertEquals(expected, compose.activity.resources.configuration.fontScale, 0.01f)
        }
        if (InstrumentationRegistry.getArguments().getString("expected_expanded") == "true") {
            assertTrue(compose.activity.resources.configuration.screenWidthDp >= 840)
        }
        val suffix = UUID.randomUUID().toString()
        val catalog = AgentCatalog(context)
        val a = AgentProfile("ui-a-$suffix", "文献助手", "梳理来源与研究问题", "区分观察和推断")
        val b = AgentProfile("ui-b-$suffix", "方法审阅", "检查方法与证据", "明确证据边界", "◈", "#427BB8")
        val group = AgentGroup("ui-g-$suffix", "研究讨论组", listOf(a.id, b.id))
        catalog.saveAgent(a); catalog.saveAgent(b); catalog.saveGroup(group)
        val saved = context.getSharedPreferences("product-chat-state", 0)
        val originalRequest = saved.getString("original_request", null)
        val originalIntent = saved.getString("original_business_intent", null)
        try {
            navigate("agents")
            compose.waitUntil(10_000) { compose.onAllNodesWithTag("agent_card_${a.id}").fetchSemanticsNodes().isNotEmpty() }
            capture("01-agent-library")
            compose.onNodeWithTag("agent_card_${a.id}").performScrollTo().performClick()
            capture("02-agent-detail")
            compose.onNodeWithText("编辑智能体").performScrollTo().performClick()
            compose.onNodeWithTag("agent_role").performScrollTo().performTextReplacement("梳理论文并追踪来源")
            capture("02b-agent-editor")
            compose.onNodeWithTag("agent_next").performScrollTo().performClick()
            compose.onNodeWithTag("agent_instructions").assertTextContains("区分观察和推断")
            compose.onNodeWithTag("agent_next").performScrollTo().performClick()
            capture("02c-agent-review")
            compose.onNodeWithTag("agent_next").performScrollTo().performClick()
            compose.waitUntil(10_000) { catalog.read().agents.single { it.id == a.id }.role == "梳理论文并追踪来源" }
            compose.onNodeWithTag("agent_card_${a.id}").performScrollTo().performClick()
            compose.onNodeWithText("打开对话").performScrollTo().performClick()
            compose.onNodeWithText("消息草稿").assertExists()
            val agentConversation = saved.getString("conversation:agent:${a.id}", null)
            assertNotNull(agentConversation)
            navigate("agents")
            compose.onNodeWithText("群组").performClick()
            compose.onNodeWithTag("group_card_${group.id}").performScrollTo().performClick()
            capture("03-group-detail")
            compose.onNodeWithText("打开群组会话").performScrollTo().performClick()
            compose.waitUntil(10_000) { saved.getString("conversation:group:${group.id}", null) != null }
            val groupConversation = saved.getString("conversation:group:${group.id}", null)
            assertNotEquals(agentConversation, groupConversation)
            capture("04-group-chat")
            compose.onNodeWithText("消息草稿").performTextInput("整理当前研究资料")
            compose.waitUntil(10_000) {
                androidx.core.view.ViewCompat.getRootWindowInsets(compose.activity.window.decorView)
                    ?.isVisible(androidx.core.view.WindowInsetsCompat.Type.ime()) == true
            }
            compose.waitForIdle()
            compose.onNodeWithText("消息草稿").assertIsDisplayed().assertTextContains("整理当前研究资料")
            compose.onNodeWithTag("chat-send").assertIsDisplayed().assertIsNotEnabled()
            val visible = android.graphics.Rect()
            compose.activity.window.decorView.getWindowVisibleDisplayFrame(visible)
            assertTrue("composer must stay above the expanded keyboard",
                compose.onNodeWithTag("chat-send").fetchSemanticsNode().boundsInWindow.bottom <= visible.bottom)
            capture("05-chat-ime")
            assertEquals(originalRequest, saved.getString("original_request", null))
            assertEquals(originalIntent, saved.getString("original_business_intent", null))
            assertEquals(agentConversation, saved.getString("conversation:agent:${a.id}", null))
        } finally {
            catalog.archiveGroup(group.id)
            catalog.archiveAgent(a.id); catalog.archiveAgent(b.id)
        }
    }
}
