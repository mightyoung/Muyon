package com.mightyoung.muyon.androidlab

/** Stdlib-only checks; intentionally contain no model, service or execution fixture. */
fun runConversationCandidateChecks() {
    val raw = "  第一行 e\u0301 🐶\n```kotlin\nval x = 1\n```\n孤立代理项:\uD800  "
    val firstMemory = PageMemory(raw, 12, 37, FocusSlot.DRAFT)
    val state = LocalUiState()
        .updateDraft(1, "只保存用户记录")
        .saveLocalNote()
        .updateMemory(firstMemory)
        .createConversation()
        .updateDraft(2, "第二个会话\n未发送 🐾")
        .copy(historyQuery = "查询 🐶", recordQuery = "记录", theme = LabTheme.DARK,
            taskFilter = LocalTaskFilter.WAITING_CONFIRMATION, overlay = LocalOverlay.History)
    val checks = linkedMapOf<String, () -> Unit>(
        "platform snapshot rejects oversized text without truncating live state" to {
            val oversized = LocalUiState().updateDraft(1, "长".repeat(60_000)).saveLocalNote().updateDraft(1, "保留草稿")
            check(oversized.platformConversationSnapshot() == listOf(CONVERSATION_SNAPSHOT_TOO_LARGE))
            check(restoreConversationSnapshot(oversized.platformConversationSnapshot()) == null)
            check(oversized.active.notes.single().text.length == 60_000)
            check(oversized.active.memory.draft == "保留草稿")
            check(state.platformConversationSnapshot() == state.conversationSnapshot())
        },
        "snapshot restores two independent drafts and selected conversation" to {
            val restored = checkNotNull(restoreConversationSnapshot(state.conversationSnapshot()))
            check(restored.selectedConversationId == 2)
            check(restored.active.memory.draft == "第二个会话\n未发送 🐾")
            check(restored.selectConversation(1).active.memory == firstMemory)
            check(restored.selectConversation(1).active.memory.draft.toCharArray().contentEquals(raw.toCharArray()))
        },
        "restore preserves user records and preferences but dismisses transient overlay" to {
            val restored = checkNotNull(restoreConversationSnapshot(state.conversationSnapshot()))
            check(restored == state.copy(overlay = null))
            check(restored.filteredNotes().single().note.text == "只保存用户记录")
            check(restored.conversations.sumOf { it.notes.size } == 1)
            check(restored.overlay == null)
            check(DisconnectedRustUiPort.availability() == PortAvailability.NOT_CONNECTED)
        },
        "repeated restoration never adds assistant messages or execution results" to {
            var restored = state.copy(overlay = null)
            repeat(4) { restored = checkNotNull(restoreConversationSnapshot(restored.conversationSnapshot())) }
            check(restored == state.copy(overlay = null))
            check(restored.conversations.map { it.notes.map(LocalNote::text) } == listOf(listOf("只保存用户记录"), emptyList()))
        },
        "every truncated snapshot is rejected" to {
            val saved = state.conversationSnapshot()
            for (size in 0 until saved.size) check(restoreConversationSnapshot(saved.take(size)) == null) { "accepted truncated length $size" }
        },
        "incompatible version and trailing payload are rejected" to {
            val saved = state.conversationSnapshot()
            check(restoreConversationSnapshot(saved.toMutableList().apply { this[0] = "conversation-ui-v999" }) == null)
            check(restoreConversationSnapshot(saved + "unexpected execution receipt") == null)
        },
        "invalid selection enum counts and coordinates are rejected" to {
            val saved = LocalUiState().conversationSnapshot()
            // Header: version, selected, history, records, theme, filter, conversation count.
            // Conversation: id, title, draft, scroll index, offset, focus, note count.
            for ((index, bad) in listOf(1 to "999", 4 to "UNKNOWN", 5 to "UNKNOWN", 6 to "0",
                6 to "10001", 7 to "-1", 8 to " ", 10 to "-1", 11 to "-1", 12 to "UNKNOWN", 13 to "-1")) {
                check(restoreConversationSnapshot(saved.toMutableList().apply { this[index] = bad }) == null) { "accepted invalid field $index=$bad" }
            }
        },
        "duplicate conversation and note identifiers are rejected" to {
            val duplicateConversations = listOf("conversation-ui-v1", "1", "", "", "SYSTEM", "ALL", "2") +
                List(2) { listOf("1", "local", "", "0", "0", "NONE", "0") }.flatten()
            check(restoreConversationSnapshot(duplicateConversations) == null)
            val duplicateNotes = listOf("conversation-ui-v1", "1", "", "", "SYSTEM", "ALL", "1",
                "1", "local", "", "0", "0", "NONE", "2", "1", "first user note", "1", "second user note")
            check(restoreConversationSnapshot(duplicateNotes) == null)
        },
    )
    var failures = 0
    checks.forEach { (name, check) ->
        try { check(); println("PASS conversation candidate: $name") }
        catch (error: Throwable) { failures++; println("FAIL conversation candidate: $name: ${error.message}") }
    }
    check(failures == 0) { "$failures/${checks.size} conversation candidate checks failed" }
    println("${checks.size}/${checks.size} conversation snapshot checks passed; Android rendering NOT_RUN")
}
