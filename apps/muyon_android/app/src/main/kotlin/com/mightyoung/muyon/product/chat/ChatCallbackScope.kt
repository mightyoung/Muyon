package com.mightyoung.muyon.product.chat

/** UI callbacks own one mounted conversation/project generation, never the next one. */
internal class ChatCallbackScope {
    private var generation = 0L
    private var selected: Pair<String, String?>? = null
    private var active = true

    fun select(conversation: String, project: String?) {
        val next = conversation to project
        if (next != selected) { selected = next; generation++ }
    }
    fun capture(): Long = generation
    fun accepts(token: Long): Boolean = active && token == generation
    fun invalidate() { generation++ }
    fun close() { active = false; invalidate() }
}
