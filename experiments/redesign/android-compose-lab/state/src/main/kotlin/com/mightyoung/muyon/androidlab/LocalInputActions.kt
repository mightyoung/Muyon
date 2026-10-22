package com.mightyoung.muyon.androidlab

/** UI callback binding, exercised without an Android runtime. */
data class LocalInputActions(val draftChanged: (String) -> Unit, val draftFocused: () -> Unit)

fun localInputActions(
    conversationId: Int,
    readState: () -> LocalUiState,
    writeState: (LocalUiState) -> Unit,
): LocalInputActions {
    // Events can interleave before recomposition. Capture only the originating ID,
    // then merge the changed field into the latest state when the callback runs.
    return LocalInputActions(
        draftChanged = { raw -> writeState(readState().updateDraft(conversationId, raw)) },
        draftFocused = { writeState(readState().rememberDraftFocus(conversationId)) },
    )
}
