package com.mightyoung.muyon.study.adapters

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.time.Instant

class CalendarPolicyTest {
    private val start = 1800000000000L
    private val end = start + 1800000L
    private fun event() = JSONObject().put("id", CalendarPolicy.eventId("task-1", start, end)).put("summary", "数学")
        .put("etag", "\"version1\"").put("status", "confirmed")
        .put("start", JSONObject().put("dateTime", Instant.ofEpochMilli(start).toString()))
        .put("end", JSONObject().put("dateTime", Instant.ofEpochMilli(end).toString()))
        .put("extendedProperties", JSONObject().put("private", JSONObject().put("muyon_owner", CalendarPolicy.OWNER)
            .put("task_id", "task-1").put("block_id", "revision-1").put("muyon_signature", CalendarPolicy.signature(start, end, "数学"))))
    @Test fun googleIdUsesAllowedAlphabetAndStableTaskTimes() {
        val id = CalendarPolicy.eventId("task-1", start, end)
        assertTrue(id.matches(Regex("[a-v0-9]{5,1024}")))
        assertEquals(id, CalendarPolicy.eventId("task-1", start, end))
        val changedRevision = event(); CalendarPolicy.properties(changedRevision)!!.put("block_id", "revision-99")
        assertEquals(id, CalendarPolicy.eventId(CalendarPolicy.properties(changedRevision)!!.getString("task_id"), start, end))
        assertNotEquals(id, CalendarPolicy.eventId("task-2", start, end))
        assertNotEquals(id, CalendarPolicy.eventId("task-1", start + 1, end))
    }
    @Test fun onlyMarkedUnmodifiedEventsAreManaged() {
        assertTrue(CalendarPolicy.intact(event()))
        assertFalse(CalendarPolicy.intact(event().put("summary", "手动改名")))
        assertFalse(CalendarPolicy.intact(event().put("start", JSONObject().put("dateTime", Instant.ofEpochMilli(start + 1000).toString()))))
        val unowned = event(); CalendarPolicy.properties(unowned)!!.remove("muyon_owner")
        assertFalse(CalendarPolicy.intact(unowned))
        assertFalse(CalendarPolicy.intact(event().put("status", "cancelled")))
    }
    @Test fun obsoleteSelectionRetainsMovedManualAndAmbiguousEvents() {
        val intact = event(); val id = intact.getString("id")
        assertEquals("delete", CalendarPolicy.obsolete(intact, emptySet(), start - 1))
        assertEquals("ignore", CalendarPolicy.obsolete(intact, setOf(id), start - 1))
        assertEquals("ignore", CalendarPolicy.obsolete(intact, emptySet(), end + 1))
        val moved = event().put("start", JSONObject().put("dateTime", Instant.ofEpochMilli(start + 60000).toString()))
        assertEquals("conflict", CalendarPolicy.obsolete(moved, emptySet(), start - 1))
        assertEquals("conflict", CalendarPolicy.obsolete(event().put("etag", ""), emptySet(), start - 1))
        assertEquals("conflict", CalendarPolicy.obsolete(event().put("recurringEventId", "series"), emptySet(), start - 1))
        val unrelated = event(); unrelated.remove("extendedProperties")
        assertEquals("ignore", CalendarPolicy.obsolete(unrelated, emptySet(), start - 1))
        val legacy = event(); CalendarPolicy.properties(legacy)!!.remove("muyon_owner")
        assertEquals("conflict", CalendarPolicy.obsolete(legacy, emptySet(), start - 1))
    }
}
