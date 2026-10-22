package com.mightyoung.muyon.product.chat

import org.junit.Assert.*
import org.junit.Test

class ChatCallbackScopeTest {
    @Test fun delayedPreviewCannotEnterNewConversationOrProjectOrDisposedTab() {
        val callbacks = ChatCallbackScope()
        callbacks.select("conversation-a", "project-a")
        val oldPreview = callbacks.capture()
        assertTrue(callbacks.accepts(oldPreview))
        // New conversation invalidates immediately, before Compose applies it.
        callbacks.invalidate()
        assertFalse(callbacks.accepts(oldPreview))
        callbacks.select("conversation-b", "project-a")
        val otherPreview = callbacks.capture()
        callbacks.select("conversation-b", "project-b")
        assertFalse(callbacks.accepts(otherPreview))
        val beforeLeavingTab = callbacks.capture()
        callbacks.close()
        assertFalse(callbacks.accepts(beforeLeavingTab))
        val returned = ChatCallbackScope()
        returned.select("conversation-b", "project-b")
        assertTrue(returned.accepts(returned.capture()))
        assertFalse(callbacks.accepts(oldPreview))
    }
}
