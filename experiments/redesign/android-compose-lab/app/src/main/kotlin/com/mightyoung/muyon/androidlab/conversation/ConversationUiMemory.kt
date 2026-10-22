package com.mightyoung.muyon.androidlab.conversation

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import com.mightyoung.muyon.androidlab.LocalUiState

/** Full text survives configuration changes in memory, without a durable-storage claim. */
class ConversationUiMemory : ViewModel() {
    val observableState = mutableStateOf(LocalUiState())
    var state by observableState
    var initialized = false
    var restorationNotice by mutableStateOf<String?>(null)
}
