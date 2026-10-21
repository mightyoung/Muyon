package com.mightyoung.muyon.product.agents

import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class AgentCatalogTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    // Isolated preference namespace avoids overwriting the real user's directory.
    private fun isolatedContext() = object : android.content.ContextWrapper(context) {
        private val name = "catalog_test_${UUID.randomUUID()}"
        override fun getSharedPreferences(name: String, mode: Int) = super.getSharedPreferences(this.name, mode)
    }
    @Test fun reopenedCatalogPreservesEditsAndGroupArchiveNeverDeletesAgents() {
        val scope = isolatedContext()
        val first = AgentCatalog(scope)
        val agent = AgentProfile("a", "研究助手", "梳理论文", "明确来源", "✦", "#7564D8")
        first.saveAgent(agent)
        first.saveGroup(AgentGroup("g", "研究组", listOf("a")))
        val second = AgentCatalog(scope)
        assertEquals(agent, second.read().agents.single())
        second.saveAgent(agent.copy(role = "整理证据"))
        second.saveGroup(AgentGroup("g", "新研究组", listOf("a")))
        second.archiveGroup("g")
        val reopened = AgentCatalog(scope).read()
        assertEquals("整理证据", reopened.agents.single().role)
        assertFalse(reopened.agents.single().archived)
        assertTrue(reopened.groups.single().archived)
        assertEquals("新研究组", reopened.groups.single().name)
        assertEquals("整理证据", second.activeAgent("a").role)
        second.archiveAgent("a")
        assertThrows(NoSuchElementException::class.java) { second.activeAgent("a") }
    }
    @Test fun invalidMembersAndCorruptDataCannotOverwritePersistedDirectory() {
        val scope = isolatedContext()
        val catalog = AgentCatalog(scope)
        catalog.saveAgent(AgentProfile("a", "助手", "研究", ""))
        val preferences = scope.getSharedPreferences(AgentCatalog.PREFERENCES, 0)
        val original = preferences.getString(AgentCatalog.KEY, null)
        assertThrows(NoSuchElementException::class.java) { catalog.activeAgent("missing") }
        for (members in listOf(emptyList(), listOf("missing"), listOf("a", "a"))) {
            assertThrows(IllegalArgumentException::class.java) { catalog.saveGroup(AgentGroup("g", "群组", members)) }
            assertEquals(original, preferences.getString(AgentCatalog.KEY, null))
        }
        catalog.saveGroup(AgentGroup("g", "群组", listOf("a")))
        assertThrows(IllegalArgumentException::class.java) { catalog.archiveAgent("a") }
        assertTrue(preferences.edit().putString(AgentCatalog.KEY, "{broken").commit())
        assertThrows(IllegalStateException::class.java) { AgentCatalog(scope).read() }
        assertThrows(IllegalStateException::class.java) { catalog.activeAgent("a") }
        assertThrows(IllegalStateException::class.java) { catalog.saveAgent(AgentProfile("b", "其他助手", "研究", "")) }
        assertEquals("{broken", preferences.getString(AgentCatalog.KEY, null))
    }
    @Test fun escapedInstructionsCannotCommitAnUnreadableExpandedDirectory() {
        val scope = isolatedContext()
        val catalog = AgentCatalog(scope)
        val preferences = scope.getSharedPreferences(AgentCatalog.PREFERENCES, 0)
        // Each field is legal, but JSON escaping doubles these 8000 backslashes.
        // Cross the aggregate storage boundary before the 100-record boundary.
        val instructions = "\\".repeat(8000)
        var saved = 0
        var lastGoodRaw: String? = null
        var rejected = false
        for (index in 0 until 100) {
            try {
                catalog.saveAgent(AgentProfile("agent_$index", "研究助手 $index", "整理文献", instructions))
                saved++
                lastGoodRaw = preferences.getString(AgentCatalog.KEY, null)
            } catch (failure: IllegalArgumentException) {
                assertTrue(failure.message.orEmpty(), failure.message.orEmpty().contains("目录容量上限"))
                assertEquals("Rejected serialization must not alter the last committed JSON", lastGoodRaw,
                    preferences.getString(AgentCatalog.KEY, null))
                rejected = true
                break
            }
        }
        assertTrue("Escaped aggregate must exceed the serialization limit before 100 agents", rejected)
        assertTrue(saved in 2..99)
        val reopened = AgentCatalog(scope).read()
        assertEquals(saved, reopened.agents.size)
        assertTrue(reopened.agents.all { it.instructions == instructions })
        assertEquals(lastGoodRaw, preferences.getString(AgentCatalog.KEY, null))
    }
}
