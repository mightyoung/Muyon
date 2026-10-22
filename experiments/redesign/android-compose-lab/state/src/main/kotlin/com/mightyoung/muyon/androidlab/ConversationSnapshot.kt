package com.mightyoung.muyon.androidlab

const val CONVERSATION_SNAPSHOT_TOO_LARGE = "conversation-ui-too-large"

/** Keep well below Binder's shared transaction budget. Never truncate a user's text. */
fun LocalUiState.platformConversationSnapshot(): List<String> {
    val snapshot = conversationSnapshot()
    return if (snapshot.sumOf { it.length.toLong() * 2 + 16 } <= 96_000L) snapshot
        else listOf(CONVERSATION_SNAPSHOT_TOO_LARGE)
}

/** Android saved-instance UI snapshot, never a durable conversation or execution receipt. */
fun LocalUiState.conversationSnapshot(): List<String> = buildList {
    add("conversation-ui-v1")
    add(selectedConversationId.toString()); add(historyQuery); add(recordQuery)
    add(theme.name); add(taskFilter.name); add(conversations.size.toString())
    conversations.forEach { conversation ->
        add(conversation.id.toString()); add(conversation.title)
        with(conversation.memory) {
            add(draft); add(firstVisibleItemIndex.toString()); add(firstVisibleItemOffset.toString()); add(focus.name)
        }
        add(conversation.notes.size.toString())
        conversation.notes.forEach { add(it.id.toString()); add(it.text) }
    }
}

/** Invalid, truncated or incompatible platform state is rejected, without fabricating history. */
fun restoreConversationSnapshot(values: List<String>): LocalUiState? = runCatching {
    val input = values.iterator()
    fun next() = input.next()
    fun count(): Int = next().toInt().also { require(it in 0..10_000) }
    require(next() == "conversation-ui-v1")
    val selected = next().toInt()
    val historyQuery = next(); val recordQuery = next()
    val theme = LabTheme.valueOf(next()); val filter = LocalTaskFilter.valueOf(next())
    val conversations = List(count()) {
        val id = next().toInt(); val title = next()
        val memory = PageMemory(next(), next().toInt(), next().toInt(), FocusSlot.valueOf(next()))
        val notes = List(count()) { LocalNote(next().toInt(), next()) }
        LocalConversation(id, title, memory, notes)
    }
    require(!input.hasNext())
    LocalUiState(conversations, selected, historyQuery, recordQuery, theme = theme, taskFilter = filter)
}.getOrNull()
