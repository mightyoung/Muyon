package com.mightyoung.muyon.product.ui.cards

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.mightyoung.muyon.product.ui.system.FoundationButton
import com.mightyoung.muyon.product.ui.system.FoundationTag
import com.mightyoung.muyon.product.ui.system.ButtonKind

/** Host capabilities are explicit and default to none. They are not authorization grants. */
data class CardInteractions(
    val capabilities: Set<CardCapability> = emptySet(),
    val onAction: ((CardAction) -> Unit)? = null,
) {
    fun allows(capability: CardCapability): Boolean = onAction != null && capability in capabilities
}

/** Uses the host MaterialTheme; ui-shell should wrap with ui.system.FoundationTheme. */
@Composable
private fun CardFrame(title: String, status: String? = null, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Surface(modifier.fillMaxWidth(), shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surface,
        contentColor = MaterialTheme.colorScheme.onSurface,
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(title, style = MaterialTheme.typography.titleLarge)
            status?.let { FoundationTag(it) }
            content()
        }
    }
}

@Composable
private fun Note(text: String) {
    Text(text, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun ActionButton(
    label: String, tag: String, capability: CardCapability, action: CardAction,
    interactions: CardInteractions, enabled: Boolean = true, primary: Boolean = false,
) {
    val active = enabled && interactions.allows(capability)
    val modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag(tag)
    val click = { if (active) interactions.onAction?.invoke(action); Unit }
    FoundationButton(label, onClick = if (active) click else null, modifier = modifier,
        kind = if (primary) ButtonKind.Primary else ButtonKind.Secondary)
}

@Composable
fun AttachmentCard(model: AttachmentCardModel, interactions: CardInteractions = CardInteractions(), modifier: Modifier = Modifier) {
    CardFrame("附件处理", model.availability.label, modifier) {
        Text(model.filename, style = MaterialTheme.typography.titleMedium)
        Note("来源版本：${model.version}")
        HorizontalDivider()
        model.stages.forEach { stage ->
            Text("${stage.title} · ${stage.status.label}", style = MaterialTheme.typography.bodyLarge)
            Note(stage.detail)
        }
        model.failureDetail?.let { Note(it) }
        Note("保存附件不代表已读完全文。")
        ActionButton("查看可用页", "card-available-pages", CardCapability.ViewAvailablePages,
            CardAction.ViewAvailablePages(model.binding, model.sourceId), interactions, primary = true)
        if (model.failureDetail != null) ActionButton("查看失败详情", "card-failure-details", CardCapability.ViewFailureDetails,
            CardAction.ViewFailureDetails(model.binding, model.sourceId), interactions)
    }
}

@Composable
fun EvidenceCard(model: EvidenceCardModel, interactions: CardInteractions = CardInteractions(), modifier: Modifier = Modifier) {
    CardFrame("证据与来源", model.relation.label, modifier) {
        Text(model.claim, style = MaterialTheme.typography.titleMedium)
        Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surfaceVariant) {
            Text(model.quote, Modifier.padding(12.dp), style = MaterialTheme.typography.bodyLarge)
        }
        Text(model.title, style = MaterialTheme.typography.bodyLarge)
        Note("${model.version} · ${model.location}")
        Note(model.provenance)
        Note("来源可定位不等于主张已证实；被引用来源不代表全部检索结果。")
        ActionButton("定位原文", "card-locate-source", CardCapability.OpenSource,
            CardAction.OpenSource(model.binding, model.sourceId, model.version, model.anchor), interactions,
            enabled = model.anchor != null)
        model.externalUrl?.let { url ->
            Note("外部来源：$url")
            ActionButton("打开外部来源", "card-external-source", CardCapability.OpenExternal,
                CardAction.OpenExternal(model.binding, model.sourceId, url), interactions)
        }
    }
}

@Composable
fun ChoiceCard(model: ChoiceCardModel, interactions: CardInteractions = CardInteractions(), modifier: Modifier = Modifier) {
    CardFrame(model.title, modifier = modifier) {
        Column(if (model.mode == SelectionMode.Single) Modifier.selectableGroup() else Modifier,
            verticalArrangement = Arrangement.spacedBy(8.dp)) {
            model.options.forEach { option ->
                val selected = option.id in model.selectedIds
                val enabled = option.enabled && interactions.allows(CardCapability.EditDraft)
                val change: (Boolean) -> Unit = { checked ->
                    if (enabled) interactions.onAction?.invoke(CardAction.ChangeSelection(model.binding, model.selectionAfter(option.id, checked)))
                }
                val interaction = if (model.mode == SelectionMode.Single)
                    Modifier.selectable(selected, enabled = enabled, role = Role.RadioButton, onClick = { change(true) })
                else Modifier.toggleable(selected, enabled = enabled, role = Role.Checkbox, onValueChange = change)
                Surface(shape = RoundedCornerShape(12.dp), color = if (selected) MaterialTheme.colorScheme.surfaceVariant else MaterialTheme.colorScheme.surface,
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)) {
                    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("card-choice-${option.id}")
                        .then(interaction).padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        if (model.mode == SelectionMode.Single) RadioButton(selected, onClick = null, enabled = enabled,
                            colors = RadioButtonDefaults.colors(selectedColor = MaterialTheme.colorScheme.onSurface))
                        else Checkbox(selected, onCheckedChange = null, enabled = enabled,
                            colors = CheckboxDefaults.colors(checkedColor = MaterialTheme.colorScheme.onSurface,
                                checkmarkColor = MaterialTheme.colorScheme.surface))
                        Text(option.label, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                    }
                }
            }
        }
        Note("选择仅修改本地草稿，不会发送消息或授权执行。")
    }
}

@Composable
fun DraftCard(model: DraftCardModel, interactions: CardInteractions = CardInteractions(), modifier: Modifier = Modifier) {
    CardFrame(model.title, model.saveStatus.label, modifier) {
        model.fields.forEach { field ->
            OutlinedTextField(value = field.value, onValueChange = { value ->
                if (model.canEdit && interactions.allows(CardCapability.EditDraft))
                    interactions.onAction?.invoke(CardAction.EditField(model.binding, model.draftId, field.id, value))
            }, label = { Text(field.label) }, modifier = Modifier.fillMaxWidth().testTag("card-field-${field.id}"),
                enabled = model.canEdit && interactions.allows(CardCapability.EditDraft),
                isError = field.error != null, singleLine = !field.multiline,
                supportingText = { field.error?.let { Text(it) } },
                textStyle = MaterialTheme.typography.bodyLarge)
        }
        model.detail?.let { Note(it) }
        Note("编辑仅修改本地草稿；保存草稿不等于提交。")
        ActionButton("保存草稿", "card-save-draft", CardCapability.SaveDraft,
            CardAction.SaveDraft(model.binding, model.draftId), interactions, enabled = model.canSave)
        ActionButton("预览提交记录", "card-submit-draft", CardCapability.PreviewDraftSubmission,
            CardAction.PreviewDraftSubmission(model.binding, model.draftId), interactions, enabled = model.canPreviewSubmission, primary = true)
        if (CardCapability.SendDraft in interactions.capabilities) ActionButton("发送为消息", "card-send-draft", CardCapability.SendDraft,
            CardAction.SendDraft(model.binding, model.draftId), interactions, enabled = model.canSave)
        Note("只有宿主返回保存回执后，才显示已保存草稿。")
    }
}

@Composable
fun ConfirmationCard(model: ConfirmationCardModel, interactions: CardInteractions = CardInteractions(), modifier: Modifier = Modifier) {
    CardFrame(model.title, "待确认", modifier) {
        Note("目标：${model.target}")
        Text("变更：${model.change}", style = MaterialTheme.typography.bodyLarge)
        Note("版本：${model.expectedRevision} → ${model.proposedRevision}（预期 ${model.expectedRevision}）")
        Note("接收方：${model.recipient}")
        Note("费用范围：${model.costScope}")
        model.disclosureContent?.let { Text("此次披露内容：$it", style = MaterialTheme.typography.bodyLarge) }
        Note(if (model.kind == ConfirmationKind.Modification) "批准修改不等于批准披露。" else "此次批准仅适用于上列披露内容与接收方。")
        ActionButton("放弃此次预览", "card-dismiss-preview", CardCapability.DismissPreview,
            CardAction.DismissPreview(model.binding, model.intentId), interactions)
        ActionButton(model.kind.approveLabel, "card-approve", CardCapability.RequestExecution,
            CardAction.RequestExecution(model.binding, model), interactions, primary = true)
        Note("目标、内容、权限范围或版本改变后，宿主须重新校验并确认。")
    }
}

@Composable
fun ReceiptCard(model: ReceiptCardModel, interactions: CardInteractions = CardInteractions(), modifier: Modifier = Modifier) {
    CardFrame("操作回执 · ${model.intentId}", model.status.label, modifier) {
        Note("历史回执不代表当前记录状态。")
        Text(model.detail, style = MaterialTheme.typography.bodyLarge)
        model.cancelIntentNotice?.let { Note(it) }
        if (model.status == ReceiptStatus.Unknown) Note("尚未确认执行结果，不代表失败。请查询原回执。")
        Note("预占：${model.reservedCost ?: "未知"}")
        Note("实际费用：${model.actualCost ?: "未知"}")
        ActionButton("查询原回执", "card-query-receipt", CardCapability.QueryReceipt,
            CardAction.QueryReceipt(model.binding, model.original), interactions)
        if (CardCapability.RequestCancel in model.actions) ActionButton("请求取消", "card-request-cancel", CardCapability.RequestCancel,
            CardAction.RequestCancel(model.binding, model.original), interactions)
        Note("查询不会重新提交原请求。")
    }
}

@Composable
fun ProjectCards(model: ProjectCardsModel, interactions: CardInteractions = CardInteractions(), modifier: Modifier = Modifier) {
    CardFrame(model.title, modifier = modifier) {
        Note(model.scopeLabel)
        Text("项目材料", style = MaterialTheme.typography.titleMedium)
        if (model.materials.isEmpty()) Note("暂无项目材料")
        model.materials.forEach { material ->
            Text(material.title, style = MaterialTheme.typography.bodyLarge)
            Note("来源快照 ${material.version} · 只读")
            ActionButton("查看材料", "card-material-${material.sourceId}", CardCapability.OpenSource,
                CardAction.OpenSource(model.binding, material.sourceId, material.version, null), interactions)
        }
        HorizontalDivider()
        Text("报告版本", style = MaterialTheme.typography.titleMedium)
        if (model.reports.isEmpty()) Note("暂无报告版本")
        model.reports.forEach { report ->
            Text("${report.title} · ${report.versionId}", style = MaterialTheme.typography.titleMedium)
            Note(report.status.label)
            Note("引用：${report.sourceSnapshot}")
            if (CardCapability.ViewVersion in report.actions) ActionButton("查看版本", "card-version-${report.versionId}", CardCapability.ViewVersion,
                CardAction.ViewVersion(model.binding, report.versionId), interactions)
            if (CardCapability.EditReport in report.actions) ActionButton("继续编辑", "card-edit-${report.versionId}", CardCapability.EditReport,
                CardAction.EditReport(model.binding, report.versionId), interactions)
            if (CardCapability.PreviewReportSave in report.actions) ActionButton("预览保存新版本", "card-preview-save-${report.versionId}", CardCapability.PreviewReportSave,
                CardAction.PreviewReportSave(model.binding, report.versionId), interactions, primary = true)
            if (CardCapability.CompareVersions in report.actions) {
                Note("发现版本冲突，先比较再保存。")
                ActionButton("比较版本", "card-compare-${report.versionId}", CardCapability.CompareVersions,
                    CardAction.CompareVersions(model.binding, report.versionId), interactions)
            }
        }
        Note("保存新版本须由宿主追加，不覆盖已有版本；预览不等于保存。")
    }
}
