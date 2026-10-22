package com.mightyoung.muyon.product.ui.shell

import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

/** Uses an isolated real Android preference file; no Service, catalog or request identities. */
class LocalShellDraftsTest {
    @Test fun restoresDraftWithoutMixingConversationOrProjectScopes() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "test-shell-drafts-${UUID.randomUUID()}"
        val preferences = context.getSharedPreferences(name, 0)
        try {
            val first = LocalShellDrafts(preferences)
            assertTrue(first.write("agent:a", "project:a", "用户未发送的草稿"))
            val restored = LocalShellDrafts(preferences)
            assertEquals("用户未发送的草稿", restored.read("agent:a", "project:a"))
            assertEquals("", restored.read("agent:b", "project:a"))
            assertEquals("", restored.read("agent:a", "project:b"))
            assertTrue(restored.write("agent:a", null, "全局"))
            assertEquals("", restored.read("agent:a", ""))
        } finally { context.deleteSharedPreferences(name) }
    }

    @Test fun delimiterLikeIdentitiesCannotAliasAndLongDraftIsBounded() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "test-shell-drafts-${UUID.randomUUID()}"
        try {
            val drafts = LocalShellDrafts(context.getSharedPreferences(name, 0))
            assertTrue(drafts.write("a:1:b", "c", "a".repeat(5000)))
            assertEquals(4096, drafts.read("a:1:b", "c").length)
            assertEquals("", drafts.read("a", "b:1:c"))
        } finally { context.deleteSharedPreferences(name) }
    }
}
