package com.mightyoung.muyon.product.ui.shell

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/** Activity attachment is real even while missing Host metadata prevents any selectable document row. */
@Composable
fun ReaderSelectionSurface(surface: ActivityReaderSurface, project: String?) {
    var route by remember(surface, project) { mutableStateOf<ReaderRoute?>(null) }
    DisposableEffect(surface, project) {
        val entered = surface.enter(project); route = entered
        onDispose { surface.leave(entered) } // exact route token: an old dispose cannot stop a new route
    }
    val revision = surface.revision
    val records = remember(surface, revision) { surface.availableSelections }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("当前文档选择", style = MaterialTheme.typography.titleMedium)
        if (records.isEmpty()) Text(surface.catalogUnavailable)
        ReaderDocumentChoices(records, enabled = route != null) { selected ->
            route?.let { surface.chooseFromUserGesture(it, selected) }
        }
        Text(surface.notice, style = MaterialTheme.typography.bodySmall)
    }
}

/** Only metadata supplied by the Activity's private Host listing may populate production choices. */
@Composable
internal fun ReaderDocumentChoices(records: List<ReaderExactSelection>, enabled: Boolean, onSelect: (ReaderExactSelection) -> Unit) {
    records.forEach { selected ->
        OutlinedButton(enabled = enabled, onClick = { onSelect(selected) }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
            Text("${selected.document.documentId} · 版本 ${selected.document.revision} · ${selected.document.format}")
        }
    }
}
