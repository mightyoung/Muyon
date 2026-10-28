package com.mightyoung.muyon.study.adapters

/** Generation guard is checked when a queued callback runs, not when it is posted. */
internal class SpeechSession {
    private var generation = 0L
    private var active = false
    private val finalSegments = mutableListOf<String>()
    private var partial = ""
    @Synchronized fun begin(): Long {
        generation++; active = true; finalSegments.clear(); partial = ""; return generation
    }
    @Synchronized fun invalidate() { generation++; active = false }
    @Synchronized fun current(ticket: Long): Boolean = active && generation == ticket
    @Synchronized fun update(ticket: Long, text: String, final: Boolean): String? {
        if(!current(ticket)) return null
        if(final) { if(text.isNotBlank()) finalSegments.add(text.trim()); partial = "" }
        else partial = text.trim()
        return (finalSegments + listOf(partial)).filter { it.isNotEmpty() }.joinToString("\n")
    }
}
