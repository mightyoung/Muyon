package com.mightyoung.muyon.product.ui.cards

/** Display scope only; the host must compare every field with its mounted trusted scope. */
data class CardScope(val workspaceId: String, val conversationId: String, val projectId: String?, val agentId: String, val generation: Long) {
    init {
        require(listOfNotNull(workspaceId, conversationId, projectId, agentId).all { it.isNotBlank() })
        require(generation >= 0)
    }
}

/** Opaque digest is supplied by the host, never computed from rendered text. */
data class CardBinding(
    val scope: CardScope, val messageId: String, val componentId: String,
    val componentRevision: Long, val stateRevision: Long, val attemptId: String, val digest: String,
) {
    init {
        require(listOf(messageId, componentId, attemptId, digest).all { it.isNotBlank() })
        require(componentRevision >= 0 && stateRevision >= 0)
    }
}

/** Original pending identity is retained independently of the current host CAS revision. */
data class OriginalCardRequest(val binding: CardBinding, val actionId: String, val intentId: String) {
    init { require(actionId.isNotBlank() && intentId.isNotBlank()) }
}

enum class ActionCategory { LocalDraft, OpenSource, ExternalLink, MessageSend, BusinessPreview, BusinessExecution, ReceiptQuery, Cancellation }
enum class CardCapability {
    OpenSource, OpenExternal, ViewAvailablePages, ViewFailureDetails, EditDraft, SaveDraft,
    PreviewDraftSubmission, SendDraft, RequestExecution, DismissPreview, QueryReceipt,
    RequestCancel, ViewVersion, EditReport, PreviewReportSave, CompareVersions,
}

/** Typed intents, never executable commands. No card stores grants or invokes a host service. */
sealed interface CardAction {
    val binding: CardBinding
    val category: ActionCategory
    data class OpenSource(override val binding: CardBinding, val sourceId: String, val version: String, val anchor: String?) : CardAction { override val category = ActionCategory.OpenSource }
    data class OpenExternal(override val binding: CardBinding, val sourceId: String, val url: String) : CardAction { override val category = ActionCategory.ExternalLink }
    data class ViewAvailablePages(override val binding: CardBinding, val sourceId: String) : CardAction { override val category = ActionCategory.OpenSource }
    data class ViewFailureDetails(override val binding: CardBinding, val sourceId: String) : CardAction { override val category = ActionCategory.OpenSource }
    data class ChangeSelection(override val binding: CardBinding, val selectedIds: Set<String>) : CardAction { override val category = ActionCategory.LocalDraft }
    data class EditField(override val binding: CardBinding, val draftId: String, val fieldId: String, val value: String) : CardAction { override val category = ActionCategory.LocalDraft }
    data class SaveDraft(override val binding: CardBinding, val draftId: String) : CardAction { override val category = ActionCategory.LocalDraft }
    data class PreviewDraftSubmission(override val binding: CardBinding, val draftId: String) : CardAction { override val category = ActionCategory.BusinessPreview }
    data class SendDraft(override val binding: CardBinding, val draftId: String) : CardAction { override val category = ActionCategory.MessageSend }
    data class RequestExecution(override val binding: CardBinding, val preview: ConfirmationCardModel) : CardAction {
        init { require(binding == preview.binding) }
        override val category = ActionCategory.BusinessExecution
    }
    data class DismissPreview(override val binding: CardBinding, val intentId: String) : CardAction { override val category = ActionCategory.LocalDraft }
    data class QueryReceipt(override val binding: CardBinding, val original: OriginalCardRequest) : CardAction { override val category = ActionCategory.ReceiptQuery }
    data class RequestCancel(override val binding: CardBinding, val original: OriginalCardRequest) : CardAction { override val category = ActionCategory.Cancellation }
    data class ViewVersion(override val binding: CardBinding, val versionId: String) : CardAction { override val category = ActionCategory.OpenSource }
    data class EditReport(override val binding: CardBinding, val versionId: String) : CardAction { override val category = ActionCategory.LocalDraft }
    data class PreviewReportSave(override val binding: CardBinding, val versionId: String) : CardAction { override val category = ActionCategory.BusinessPreview }
    data class CompareVersions(override val binding: CardBinding, val versionId: String) : CardAction { override val category = ActionCategory.OpenSource }
}

enum class AttachmentAvailability(val label: String) { Processing("处理中"), Partial("部分可用"), Available("可用"), Failed("处理失败"), Unknown("处理结果未知") }
enum class StageStatus(val label: String) { Pending("待处理"), Running("处理中"), Complete("已完成"), Partial("部分完成"), Failed("失败"), Unknown("未知") }
data class AttachmentStage(val title: String, val status: StageStatus, val detail: String)
data class AttachmentCardModel(
    val binding: CardBinding, val sourceId: String, val filename: String, val version: String,
    val availability: AttachmentAvailability, val stages: List<AttachmentStage>, val failureDetail: String? = null,
)
enum class SourceRelation(val label: String) { Cited("被引用来源"), Candidate("检索候选") }
data class EvidenceCardModel(
    val binding: CardBinding, val claim: String, val quote: String, val relation: SourceRelation,
    val sourceId: String, val title: String, val version: String, val location: String,
    val anchor: String?, val provenance: String, val externalUrl: String? = null,
)
enum class SelectionMode { Single, Multiple }
data class ChoiceOption(val id: String, val label: String, val enabled: Boolean = true)
data class ChoiceCardModel(
    val binding: CardBinding, val title: String, val mode: SelectionMode,
    val options: List<ChoiceOption>, val selectedIds: Set<String>,
) {
    init {
        require(options.map { it.id }.distinct().size == options.size)
        require(options.all { it.id.isNotBlank() })
        require(selectedIds.all { id -> options.any { it.id == id } })
        require(mode != SelectionMode.Single || selectedIds.size <= 1)
    }
    /** Local editing projection, not a business transition or persisted selection. */
    fun selectionAfter(id: String, checked: Boolean): Set<String> {
        val option = options.single { it.id == id }
        if (!option.enabled) return selectedIds
        return if (mode == SelectionMode.Single) { if (checked) setOf(id) else selectedIds }
        else if (checked) selectedIds + id else selectedIds - id
    }
}
enum class DraftSaveStatus(val label: String) { Unsaved("未保存"), Saving("保存中"), Saved("已保存草稿"), Failed("保存失败"), Unknown("保存结果未知") }
data class DraftField(val id: String, val label: String, val value: String, val error: String? = null, val multiline: Boolean = false)
data class DraftCardModel(
    val binding: CardBinding, val draftId: String, val title: String, val saveStatus: DraftSaveStatus,
    val fields: List<DraftField>, val canSubmit: Boolean = false, val detail: String? = null,
) {
    init { require(fields.map { it.id }.distinct().size == fields.size) }
    val canEdit get() = saveStatus != DraftSaveStatus.Saving && saveStatus != DraftSaveStatus.Unknown
    val canSave get() = canEdit && fields.none { it.error != null }
    val canPreviewSubmission get() = canSave && canSubmit
}
enum class ConfirmationKind(val approveLabel: String) { Modification("批准修改"), Disclosure("批准此次披露") }
data class ConfirmationCardModel(
    val binding: CardBinding, val intentId: String, val title: String, val target: String, val change: String,
    val expectedRevision: String, val proposedRevision: String, val recipient: String, val costScope: String,
    val kind: ConfirmationKind, val disclosureContent: String? = null,
) {
    init {
        require(listOf(intentId, target, expectedRevision, proposedRevision, recipient, costScope).all { it.isNotBlank() })
        require(kind != ConfirmationKind.Disclosure || !disclosureContent.isNullOrBlank())
    }
}
enum class ReceiptStatus(val label: String) { Running("执行中"), Succeeded("已完成"), Failed("执行失败"), Cancelled("已取消"), Unknown("结果未知") }
data class ReceiptCardModel(
    val binding: CardBinding, val original: OriginalCardRequest, val status: ReceiptStatus, val detail: String,
    val reservedCost: String? = null, val actualCost: String? = null, val cancelRequested: Boolean = false,
) {
    val cancelIntentNotice get() = if (cancelRequested) "已记录取消意图；尚未确认取消；取消不代表回滚。" else null
    val intentId get() = original.intentId
    val actions: Set<CardCapability> get() = if (status == ReceiptStatus.Running && !cancelRequested)
        setOf(CardCapability.QueryReceipt, CardCapability.RequestCancel) else setOf(CardCapability.QueryReceipt)
}
data class ProjectMaterial(val sourceId: String, val title: String, val version: String)
enum class ReportVersionStatus(val label: String) { Draft("草稿 · 未保存"), Saved("已保存版本"), History("历史版本"), Conflict("版本冲突") }
data class ReportVersion(val versionId: String, val title: String, val status: ReportVersionStatus, val sourceSnapshot: String) {
    val actions: Set<CardCapability> get() = when (status) {
        ReportVersionStatus.Draft -> setOf(CardCapability.EditReport, CardCapability.PreviewReportSave)
        ReportVersionStatus.Conflict -> setOf(CardCapability.ViewVersion, CardCapability.CompareVersions)
        else -> setOf(CardCapability.ViewVersion)
    }
}
data class ProjectCardsModel(val binding: CardBinding, val title: String, val scopeLabel: String, val materials: List<ProjectMaterial>, val reports: List<ReportVersion>)
