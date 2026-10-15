package com.mightyoung.muyon.androidlab

private fun localExpect(value: Boolean, message: String) = check(value) { message }
private fun LocalUiState.withDraft(raw: String) = updateMemory(active.memory.copy(draft = raw))

fun runLocalUiChecks() {
    val raw = "  e\u0301\n\uD800  "
    val checks = linkedMapOf<String, () -> Unit>(
        "empty local session never fabricates a message" to {
            val s = LocalUiState()
            localExpect(s.active.notes.isEmpty() && s.filteredNotes().isEmpty(), "fabricated records")
            localExpect(!s.canSaveLocalNote && s.overlay == null, "unexpected initial action")
        },
        "draft remains exact raw UTF16" to {
            localExpect(LocalUiState().withDraft(raw).active.memory.draft.toCharArray().contentEquals(raw.toCharArray()), "raw draft changed")
        },
        "blank local note does not create records" to {
            val s = LocalUiState().withDraft(" \n\t")
            localExpect(!s.canSaveLocalNote && s.saveLocalNote() == s, "blank note saved")
        },
        "nonblank local note can be saved" to {
            localExpect(LocalUiState().withDraft(raw).canSaveLocalNote, "local save unavailable")
        },
        "local save preserves text and clears only composer" to {
            val original = LocalUiState().withDraft(raw)
            val saved = original.saveLocalNote()
            localExpect(saved.active.notes.single().text == raw, "saved text changed")
            localExpect(saved.active.memory.draft.isEmpty(), "composer not cleared")
            localExpect(saved.active.memory.focus == FocusSlot.DRAFT, "input focus not retained")
            localExpect(original.active.notes.isEmpty() && original.active.memory.draft == raw, "mutated original")
        },
        "repeated empty save cannot duplicate a note" to {
            val s = LocalUiState().withDraft("one").saveLocalNote()
            localExpect(s.saveLocalNote() == s && s.active.notes.size == 1, "duplicated local note")
        },
        "local note ids stay unique and ordered" to {
            val s = LocalUiState().withDraft("one").saveLocalNote().withDraft("two").saveLocalNote()
            localExpect(s.active.notes.map { it.text } == listOf("one", "two"), "wrong record order")
            localExpect(s.active.notes.map { it.id }.toSet().size == 2, "duplicate note id")
        },
        "new conversation retains prior unsaved draft" to {
            val s = LocalUiState().withDraft(raw).createConversation()
            localExpect(s.conversations.size == 2 && s.selectedConversationId != 1, "not created/selected")
            localExpect(s.active.notes.isEmpty() && s.active.memory.draft.isEmpty(), "new page copied content")
            localExpect(s.selectConversation(1).active.memory.draft == raw, "lost old draft")
        },
        "conversation switching retains individual scroll and focus" to {
            val memory = PageMemory(raw, 4, 21, FocusSlot.DRAFT)
            val s = LocalUiState().updateMemory(memory).createConversation().withDraft("second").selectConversation(1)
            localExpect(s.active.memory == memory, "cross-conversation memory lost")
            val lateScroll = s.selectConversation(2).storeMemory(1, memory.copy(firstVisibleItemIndex = 9))
            localExpect(lateScroll.active.memory.draft == "second", "inactive scroll callback overwrote active input")
            localExpect(lateScroll.selectConversation(1).active.memory.firstVisibleItemIndex == 9, "inactive memory update lost")
        },
        "invalid conversation selection changes nothing" to {
            val s = LocalUiState().copy(overlay = LocalOverlay.History)
            localExpect(s.selectConversation(999) == s, "invalid selection changed state")
        },
        "selection closes overlay but keeps search query" to {
            val s = LocalUiState().copy(overlay = LocalOverlay.History, historyQuery = "local").selectConversation(1)
            localExpect(s.overlay == null && s.historyQuery == "local", "selection side effects")
        },
        "create resets history filter and closes overlay" to {
            val s = LocalUiState().copy(overlay = LocalOverlay.History, historyQuery = "missing").createConversation()
            localExpect(s.historyQuery.isEmpty() && s.overlay == null, "new conversation hidden by stale filter")
        },
        "history filter searches own title and note text" to {
            val s = LocalUiState().withDraft("Alpha source").saveLocalNote().createConversation()
            localExpect(s.copy(historyQuery = "alpha").filteredConversations().map { it.id } == listOf(1), "history query mismatch")
            localExpect(s.copy(historyQuery = "absent").filteredConversations().isEmpty(), "false history match")
        },
        "record filter exposes only user saved content" to {
            val s = LocalUiState().withDraft("Alpha").saveLocalNote().createConversation().withDraft("unsaved")
            localExpect(s.filteredNotes().single().note.text == "Alpha", "draft or fake response exposed as saved record")
            localExpect(s.copy(recordQuery = "ALPHA").filteredNotes().size == 1, "case-insensitive search")
            localExpect(s.copy(recordQuery = "unsaved").filteredNotes().isEmpty(), "unsaved content indexed")
        },
        "rename opens correct current title" to {
            val s = LocalUiState().openRename(1)
            localExpect(s.overlay == LocalOverlay.Rename(1, "新的本地会话"), "rename target/title mismatch")
        },
        "rename cancellation leaves title unchanged" to {
            val s = LocalUiState().openRename(1).renameDraft("replacement").copy(overlay = null)
            localExpect(s.active.title == "新的本地会话", "cancel mutated title")
        },
        "rename confirmation preserves exact title" to {
            val s = LocalUiState().openRename(1).renameDraft("  名称 e\u0301  ").confirmRename()
            localExpect(s.active.title == "  名称 e\u0301  " && s.overlay == null, "title normalized or dialog remained")
        },
        "blank rename cannot overwrite title" to {
            val s = LocalUiState().openRename(1).renameDraft(" \n")
            localExpect(s.confirmRename() == s, "blank rename accepted")
        },
        "record details bind exact conversation and note" to {
            val s = LocalUiState().withDraft("first").saveLocalNote().createConversation().withDraft("second").saveLocalNote().openNote(1, 1)
            localExpect(s.inspectedNote()?.note?.text == "first", "wrong note details")
            localExpect(s.openInspectedConversation().selectedConversationId == 1 && s.openInspectedConversation().overlay == null, "wrong return target")
        },
        "invalid note or rename cannot invent an overlay" to {
            val s = LocalUiState()
            localExpect(s.openNote(999, 1) == s && s.openNote(1, 999) == s && s.openRename(999) == s, "invalid object opened")
        },
        "local preferences retain drafts without changing host capability" to {
            val s = LocalUiState().withDraft(raw).copy(theme = LabTheme.DARK, taskFilter = LocalTaskFilter.WAITING_CONFIRMATION)
            localExpect(s.active.memory.draft == raw && s.theme == LabTheme.DARK, "preference lost input")
            localExpect(DisconnectedRustUiPort.availability() == PortAvailability.NOT_CONNECTED, "UI preference invented host connection")
        },
        "snapshot selection and ids remain valid after many sessions" to {
            var s = LocalUiState()
            repeat(40) { s = s.createConversation() }
            localExpect(s.conversations.size == 41 && s.conversations.map { it.id }.toSet().size == 41, "duplicate conversation id")
            localExpect(s.active.id == s.selectedConversationId, "selection lost")
        },
    )
    var failed = 0
    checks.forEach { (name, run) ->
        try { run(); println("PASS local UI: $name") }
        catch (error: Throwable) { failed++; println("FAIL local UI: $name: ${error.message}") }
    }
    check(failed == 0) { "$failed/${checks.size} local UI checks failed" }
    println("${checks.size}/${checks.size} local UI state checks passed; no model or Rust action executed")
}
