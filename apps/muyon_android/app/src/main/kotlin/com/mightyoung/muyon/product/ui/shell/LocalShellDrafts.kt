package com.mightyoung.muyon.product.ui.shell

import android.content.SharedPreferences

/** Display-only local drafts, deliberately separate from product request/intent preferences. */
class LocalShellDrafts(private val preferences: SharedPreferences) {
    // Length prefixes distinguish arbitrary IDs and distinguish null project from empty project.
    private fun key(conversation: String, project: String?) =
        "draft:${conversation.length}:$conversation:${project?.length ?: -1}:${project.orEmpty()}"

    fun read(conversation: String, project: String?): String =
        preferences.getString(key(conversation, project), "").orEmpty().take(4096)

    /** Caller retains the current text and shows a persistent error if the write is unconfirmed. */
    fun write(conversation: String, project: String?, text: String): Boolean =
        preferences.edit().putString(key(conversation, project), text.take(4096)).commit()
}
