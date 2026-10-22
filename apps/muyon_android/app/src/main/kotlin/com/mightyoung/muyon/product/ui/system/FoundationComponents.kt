package com.mightyoung.muyon.product.ui.system

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp

/** The host supplies localized status text, and retains authority over every action. */
@Composable
fun FoundationButton(
    label: String,
    onClick: (() -> Unit)?,
    modifier: Modifier = Modifier,
    state: ActionState = ActionState.Ready,
    kind: ButtonKind = ButtonKind.Primary,
    stateLabel: String? = null
) {
    require(label.isNotBlank())
    require(state !in setOf(ActionState.Loading, ActionState.Unknown, ActionState.Error) || !stateLabel.isNullOrBlank())
    val enabled = state.canAct(onClick != null)
    val decorated = modifier.sizeIn(minWidth = FoundationTokens.minimumTarget, minHeight = FoundationTokens.minimumTarget).semantics {
        stateLabel?.let { stateDescription = it }
        if (state == ActionState.Loading) progressBarRangeInfo = ProgressBarRangeInfo.Indeterminate
    }
    val body: @Composable RowScope.() -> Unit = {
        Column {
            Text(label)
            stateLabel?.takeIf { it.isNotBlank() }?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
        }
    }
    when (kind) {
        ButtonKind.Primary -> Button(onClick = { if (enabled) onClick?.invoke() }, modifier = decorated,
            enabled = enabled, shape = RoundedCornerShape(12.dp), content = body)
        ButtonKind.Secondary -> OutlinedButton(onClick = { if (enabled) onClick?.invoke() }, modifier = decorated,
            enabled = enabled, shape = RoundedCornerShape(12.dp),
            border = BorderStroke(1.dp, LocalFoundationPalette.current.border), content = body)
        ButtonKind.Quiet -> TextButton(onClick = { if (enabled) onClick?.invoke() }, modifier = decorated,
            enabled = enabled, content = body)
    }
}

@Composable
fun FoundationTextField(
    value: String,
    onValueChange: ((String) -> Unit)?,
    label: String,
    modifier: Modifier = Modifier,
    state: ActionState = ActionState.Ready,
    supportingText: String? = null
) {
    require(label.isNotBlank())
    require(state == ActionState.Ready || !supportingText.isNullOrBlank())
    val editable = state.canAct(onValueChange != null)
    OutlinedTextField(
        value = value, onValueChange = { if (editable) onValueChange?.invoke(it) },
        modifier = modifier.sizeIn(minWidth = FoundationTokens.minimumTarget, minHeight = FoundationTokens.minimumTarget).semantics {
            supportingText?.let { stateDescription = it }
            if (state == ActionState.Loading) progressBarRangeInfo = ProgressBarRangeInfo.Indeterminate
        }, enabled = editable, readOnly = !editable,
        label = { Text(label) }, isError = state == ActionState.Error,
        supportingText = supportingText?.let { message -> { Text(message) } },
        textStyle = MaterialTheme.typography.bodyLarge,
        shape = RoundedCornerShape(12.dp)
    )
}

/** A single focusable target. Checkbox drawing is decorative within the toggleable row. */
@Composable
fun FoundationSelection(
    label: String,
    selected: Boolean,
    onSelectedChange: ((Boolean) -> Unit)?,
    modifier: Modifier = Modifier,
    enabled: Boolean = true
) {
    require(label.isNotBlank())
    Row(
        modifier.sizeIn(minWidth = FoundationTokens.minimumTarget, minHeight = FoundationTokens.minimumTarget)
            .toggleable(value = selected, enabled = enabled && onSelectedChange != null,
                role = Role.Checkbox, onValueChange = { if (enabled) onSelectedChange?.invoke(it) })
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Checkbox(checked = selected, onCheckedChange = null, enabled = enabled && onSelectedChange != null,
            modifier = Modifier.clearAndSetSemantics { })
        Spacer(Modifier.width(8.dp))
        Text(label, style = MaterialTheme.typography.bodyLarge)
    }
}

@Composable
fun FoundationTag(label: String, modifier: Modifier = Modifier) {
    require(label.isNotBlank())
    Surface(modifier, shape = RoundedCornerShape(8.dp),
        color = LocalFoundationPalette.current.background,
        border = BorderStroke(1.dp, LocalFoundationPalette.current.border)) {
        Text(label, Modifier.padding(horizontal = 8.dp, vertical = 4.dp), style = MaterialTheme.typography.bodyMedium)
    }
}

@Immutable
data class FoundationMenuItem(val id: String, val label: String, val selected: Boolean = false, val enabled: Boolean = true)

/** Place inside the anchor's Box. Selection does not dismiss until the host changes expanded. */
@Composable
fun FoundationMenu(
    expanded: Boolean,
    items: List<FoundationMenuItem>,
    onSelect: ((String) -> Unit)?,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier
) {
    require(items.map { it.id }.distinct().size == items.size)
    require(items.all { it.id.isNotBlank() && it.label.isNotBlank() })
    val menuItems: @Composable ColumnScope.() -> Unit = {
        items.forEach { item ->
            DropdownMenuItem(
                text = { Text(item.label) },
                onClick = { if (item.enabled) onSelect?.invoke(item.id) },
                enabled = item.enabled && onSelect != null,
                modifier = Modifier.heightIn(min = FoundationTokens.minimumTarget).semantics { selected = item.selected },
                trailingIcon = if (item.selected) ({ Text("✓", Modifier.clearAndSetSemantics { }) }) else null
            )
        }
    }
    if (LocalFoundationReduceMotion.current) {
        // Popup has no open/close transition. Focusable popup blocks click-through.
        val maximumHeight = (LocalConfiguration.current.screenHeightDp * .8f).dp
        if (expanded) Popup(onDismissRequest = onDismiss, properties = PopupProperties(focusable = true)) {
            Surface(modifier.widthIn(min = 200.dp, max = 320.dp).heightIn(max = maximumHeight),
                color = LocalFoundationPalette.current.panel, shape = RoundedCornerShape(12.dp),
                border = BorderStroke(1.dp, LocalFoundationPalette.current.border)) {
                Column(Modifier.verticalScroll(rememberScrollState()).padding(vertical = 8.dp), content = menuItems)
            }
        }
    } else {
        DropdownMenu(expanded = expanded, onDismissRequest = onDismiss, modifier = modifier, content = menuItems)
    }
}

/** Platform modal: background cannot receive clicks; back/outside dismissal is host-owned. */
@Composable
fun FoundationDialog(
    title: String,
    onDismiss: () -> Unit,
    confirmLabel: String,
    onConfirm: (() -> Unit)?,
    dismissLabel: String,
    modifier: Modifier = Modifier,
    confirmState: ActionState = ActionState.Ready,
    confirmStateLabel: String? = null,
    content: @Composable () -> Unit
) {
    require(title.isNotBlank())
    AlertDialog(
        onDismissRequest = onDismiss, modifier = modifier,
        title = { Text(title) },
        text = { Column(Modifier.verticalScroll(rememberScrollState())) { content() } },
        confirmButton = { FoundationButton(confirmLabel, onConfirm, state = confirmState, stateLabel = confirmStateLabel) },
        dismissButton = { FoundationButton(dismissLabel, onDismiss, kind = ButtonKind.Quiet) },
        containerColor = LocalFoundationPalette.current.panel,
        titleContentColor = LocalFoundationPalette.current.text,
        textContentColor = LocalFoundationPalette.current.text
    )
}

/** Keep prior content at the call site; no result data is cleared or invented here. */
@Composable
fun FoundationFeedback(
    kind: FeedbackKind,
    title: String,
    detail: String,
    modifier: Modifier = Modifier
) {
    require(title.isNotBlank() && detail.isNotBlank())
    val p = LocalFoundationPalette.current
    Surface(modifier.semantics {
        liveRegion = LiveRegionMode.Polite
        if (kind == FeedbackKind.Loading) progressBarRangeInfo = ProgressBarRangeInfo.Indeterminate
        if (kind == FeedbackKind.Error) error(detail)
    }, shape = RoundedCornerShape(12.dp), color = p.panel,
        contentColor = if (kind == FeedbackKind.Error) p.error else p.text,
        border = BorderStroke(1.dp, p.border)) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            if (kind == FeedbackKind.Loading && !LocalFoundationReduceMotion.current) {
                CircularProgressIndicator(Modifier.size(24.dp))
                Spacer(Modifier.width(12.dp))
            }
            Column {
                // A visible non-color marker keeps failure/unknown/partial distinct.
                val marker = when (kind) {
                    FeedbackKind.Info -> "i"
                    FeedbackKind.Loading -> "…"
                    FeedbackKind.Partial -> "◐"
                    FeedbackKind.Error -> "!"
                    FeedbackKind.Unknown -> "?"
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(marker, Modifier.clearAndSetSemantics { })
                    Spacer(Modifier.width(8.dp))
                    Text(title, style = MaterialTheme.typography.titleMedium)
                }
                Text(detail, style = MaterialTheme.typography.bodyLarge)
            }
        }
    }
}

@Composable
fun FoundationEmptyState(
    title: String,
    detail: String,
    modifier: Modifier = Modifier,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null
) {
    require(title.isNotBlank() && detail.isNotBlank())
    require(onAction == null || !actionLabel.isNullOrBlank())
    Column(modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium)
        Text(detail, style = MaterialTheme.typography.bodyLarge)
        actionLabel?.let { FoundationButton(it, onAction, kind = ButtonKind.Secondary) }
    }
}
