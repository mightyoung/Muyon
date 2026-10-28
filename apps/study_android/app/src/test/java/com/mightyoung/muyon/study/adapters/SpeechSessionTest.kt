package com.mightyoung.muyon.study.adapters

import org.junit.Assert.*
import org.junit.Test

class SpeechSessionTest {
    @Test fun accumulatesFinalizedUtterancesAndReplacesOnlyPartial() {
        val session = SpeechSession(); val ticket = session.begin()
        assertEquals("今天学习", session.update(ticket, "今天学习", true))
        assertEquals("今天学习\n然后", session.update(ticket, "然后", false))
        assertEquals("今天学习\n然后练习数学", session.update(ticket, "然后练习数学", false))
        assertEquals("今天学习\n然后练习数学", session.update(ticket, "然后练习数学", true))
        assertEquals("今天学习\n然后练习数学", session.update(ticket, "", false))
    }
    @Test fun queuedCallbacksCannotUpdateAfterDismissOrAnotherStart() {
        val session = SpeechSession(); val first = session.begin()
        val queued = { session.update(first, "stale", true) }
        session.invalidate()
        assertNull(queued()); assertFalse(session.current(first))
        val second = session.begin()
        assertNull(queued()); assertEquals("new", session.update(second, "new", true))
        session.invalidate(); assertNull(session.update(second, "partial", false))
    }
}
