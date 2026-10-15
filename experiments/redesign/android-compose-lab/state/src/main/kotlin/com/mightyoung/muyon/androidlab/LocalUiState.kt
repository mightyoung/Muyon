package com.mightyoung.muyon.androidlab

/** UI-owned, in-memory notes. No request, assistant result or Rust contract is represented here. */
enum class LabTheme { SYSTEM, LIGHT, DARK }
enum class LocalTaskFilter { ALL, RUNNING, WAITING_CONFIRMATION }
data class LocalNote(val id: Int, val text: String)
data class LocalConversation(val id: Int, val title: String, val memory: PageMemory = PageMemory(), val notes: List<LocalNote> = emptyList())
data class LocalNoteRef(val conversationId: Int, val conversationTitle: String, val note: LocalNote)
sealed interface LocalOverlay {
    data object History : LocalOverlay
    data object Capabilities : LocalOverlay
    data class Rename(val conversationId: Int, val titleDraft: String) : LocalOverlay
    data class NoteDetails(val conversationId: Int, val noteId: Int) : LocalOverlay
}

data class LocalUiState(
    val conversations: List<LocalConversation> = listOf(LocalConversation(1, "新的本地会话")),
    val selectedConversationId: Int = 1,
    val historyQuery: String = "",
    val recordQuery: String = "",
    val overlay: LocalOverlay? = null,
    val theme: LabTheme = LabTheme.SYSTEM,
    val taskFilter: LocalTaskFilter = LocalTaskFilter.ALL,
) {
    init {
        require(conversations.isNotEmpty() && conversations.any { it.id == selectedConversationId })
        require(conversations.map { it.id }.toSet().size == conversations.size)
        require(conversations.all { conversation ->
            conversation.id > 0 && conversation.title.isNotBlank() &&
                conversation.notes.map { it.id }.toSet().size == conversation.notes.size &&
                conversation.notes.all { it.id > 0 && it.text.isNotBlank() }
        })
    }
    val active: LocalConversation get() = conversations.first { it.id == selectedConversationId }
    val canSaveLocalNote: Boolean get() = active.memory.draft.isNotBlank()
    fun updateMemory(memory: PageMemory): LocalUiState = storeMemory(selectedConversationId, memory)
    fun storeMemory(id: Int, memory: PageMemory): LocalUiState = copy(
        conversations = conversations.map { if (it.id == id) it.copy(memory = memory) else it },
    )

    fun createConversation(): LocalUiState {
        val id = Math.addExact(conversations.maxOf { it.id }, 1)
        return copy(conversations = conversations + LocalConversation(id, "本地会话 $id"), selectedConversationId = id, overlay = null, historyQuery = "")
    }

    fun selectConversation(id: Int): LocalUiState = if (conversations.any { it.id == id })
        copy(selectedConversationId = id, overlay = null) else this

    fun saveLocalNote(): LocalUiState {
        if (!canSaveLocalNote) return this
        val note = LocalNote(Math.addExact(active.notes.maxOfOrNull { it.id } ?: 0, 1), active.memory.draft)
        val saved = active.copy(notes = active.notes + note, memory = active.memory.copy(draft = "", focus = FocusSlot.DRAFT))
        return copy(conversations = conversations.map { if (it.id == saved.id) saved else it })
    }

    fun filteredConversations(): List<LocalConversation> = conversations.filter { conversation ->
        historyQuery.isEmpty() || conversation.title.contains(historyQuery, ignoreCase = true) ||
            conversation.notes.any { it.text.contains(historyQuery, ignoreCase = true) }
    }

    fun filteredNotes(): List<LocalNoteRef> = conversations.flatMap { conversation ->
        conversation.notes.filter { note ->
            recordQuery.isEmpty() || note.text.contains(recordQuery, ignoreCase = true) || conversation.title.contains(recordQuery, ignoreCase = true)
        }.map { LocalNoteRef(conversation.id, conversation.title, it) }
    }

    fun openRename(id: Int): LocalUiState = conversations.firstOrNull { it.id == id }?.let {
        copy(overlay = LocalOverlay.Rename(it.id, it.title))
    } ?: this

    fun renameDraft(raw: String): LocalUiState = (overlay as? LocalOverlay.Rename)?.let {
        copy(overlay = it.copy(titleDraft = raw))
    } ?: this

    fun confirmRename(): LocalUiState {
        val rename = overlay as? LocalOverlay.Rename ?: return this
        if (rename.titleDraft.isBlank()) return this
        return copy(conversations = conversations.map { if (it.id == rename.conversationId) it.copy(title = rename.titleDraft) else it }, overlay = null)
    }

    fun openNote(conversationId: Int, noteId: Int): LocalUiState = if (
        conversations.any { it.id == conversationId && it.notes.any { note -> note.id == noteId } }
    ) copy(overlay = LocalOverlay.NoteDetails(conversationId, noteId)) else this

    fun inspectedNote(): LocalNoteRef? {
        val details = overlay as? LocalOverlay.NoteDetails ?: return null
        val conversation = conversations.firstOrNull { it.id == details.conversationId } ?: return null
        return conversation.notes.firstOrNull { it.id == details.noteId }?.let { LocalNoteRef(conversation.id, conversation.title, it) }
    }

    fun openInspectedConversation(): LocalUiState = inspectedNote()?.let { selectConversation(it.conversationId) } ?: this
}
