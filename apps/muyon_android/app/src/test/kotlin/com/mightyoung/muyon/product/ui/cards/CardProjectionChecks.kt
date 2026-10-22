package com.mightyoung.muyon.product.ui.cards

private var assertions = 0
private fun verify(value: Boolean) { assertions++; check(value) }

private fun rejects(block: () -> Unit) {
    verify(runCatching(block).isFailure)
}

fun main() {
    val binding = CardBinding(CardScope("workspace", "conversation", "project", "agent", 1), "message", "card", 1, 1, "attempt", "digest")
    val unknown = ReceiptCardModel(binding, OriginalCardRequest(binding, "submit", "intent-original"), ReceiptStatus.Unknown,
        "执行结果尚未确认", "¥0.002620", null, cancelRequested = true)
    verify(unknown.status.label == "结果未知")
    verify(unknown.actualCost == null)
    verify(unknown.copy(cancelRequested = false).actions == setOf(CardCapability.QueryReceipt))
    verify(unknown.copy(status = ReceiptStatus.Running).actions == setOf(CardCapability.QueryReceipt))
    verify(unknown.actions == setOf(CardCapability.QueryReceipt))
    verify(ReceiptCardModel(binding, OriginalCardRequest(binding, "submit", "original"), ReceiptStatus.Running, "处理中").actions ==
        setOf(CardCapability.QueryReceipt, CardCapability.RequestCancel))
    verify(ReceiptCardModel(binding, OriginalCardRequest(binding, "submit", "original"), ReceiptStatus.Cancelled, "宿主确认已取消").actions ==
        setOf(CardCapability.QueryReceipt))
    val original = OriginalCardRequest(binding, "submit", "original")
    val current = binding.copy(stateRevision = 8, attemptId = "new-attempt", digest = "new-digest")
    val cancel = CardAction.RequestCancel(current, original)
    verify(cancel.binding.stateRevision == 8L)
    verify(cancel.original.binding.attemptId == "attempt")
    verify(cancel.original.binding.digest == "digest")
    verify(cancel != CardAction.RequestCancel(current, OriginalCardRequest(current, "submit", "new-intent")))
    val preview = ConfirmationCardModel(binding, "intent", "保存记录", "project/record", "before → after",
        "r3", "r4", "本机库", "仅本地写入", ConfirmationKind.Modification)
    rejects { preview.copy(kind = ConfirmationKind.Disclosure) }
    rejects { preview.copy(kind = ConfirmationKind.Disclosure, disclosureContent = " ") }
    val disclosure = preview.copy(kind = ConfirmationKind.Disclosure, disclosureContent = "仅当前片段")
    verify(disclosure.kind.approveLabel == "批准此次披露")
    verify(CardAction.RequestExecution(binding, disclosure).preview.disclosureContent == "仅当前片段")
    val execute = CardAction.RequestExecution(binding, preview)
    verify(execute.category == ActionCategory.BusinessExecution)
    verify(execute.preview.expectedRevision == "r3")
    verify(execute.preview.binding == execute.binding)
    rejects { CardAction.RequestExecution(binding.copy(stateRevision = 2), preview) }
    verify(CardAction.OpenExternal(binding, "source", "https://example.org").category == ActionCategory.ExternalLink)
    verify(CardAction.SaveDraft(binding, "draft").category == ActionCategory.LocalDraft)
    verify(CardAction.SendDraft(binding, "draft").category == ActionCategory.MessageSend)
    verify(CardAction.PreviewDraftSubmission(binding, "draft").category == ActionCategory.BusinessPreview)
    val single = ChoiceCardModel(binding, "状态", SelectionMode.Single,
        listOf(ChoiceOption("todo", "待核对"), ChoiceOption("read", "已读完")), setOf("todo"))
    verify(single.selectionAfter("read", true) == setOf("read"))
    verify(single.selectionAfter("read", false) == single.selectedIds)
    val multi = single.copy(mode = SelectionMode.Multiple)
    verify(multi.selectionAfter("read", true) == setOf("todo", "read"))
    verify(multi.selectionAfter("todo", false).isEmpty())
    rejects { single.copy(selectedIds = setOf("todo", "read")) }
    rejects { single.copy(selectedIds = setOf("unknown")) }
    rejects { single.copy(options = listOf(ChoiceOption("todo", "1"), ChoiceOption("todo", "2"))) }
    rejects { single.selectionAfter("unknown", true) }
    val evidence = EvidenceCardModel(binding, "主张", "原文", SourceRelation.Cited,
        "source-v1", "论文.pdf", "v1", "第3页", "anchor-p3", "同源材料，不代表独立证据")
    verify(evidence.anchor == "anchor-p3")
    verify(evidence.relation.label == "被引用来源")
    verify(evidence.copy(relation = SourceRelation.Candidate).relation.label == "检索候选")
    val attachment = AttachmentCardModel(binding, "source", "notes.pdf", "v1", AttachmentAvailability.Partial,
        listOf(AttachmentStage("本地保存", StageStatus.Complete, "已保存"),
            AttachmentStage("提取", StageStatus.Partial, "3 / 5 页"),
            AttachmentStage("索引", StageStatus.Partial, "仅第1–3页可检索")), "第4–5页失败")
    verify(attachment.availability.label == "部分可用")
    verify(attachment.stages.last().detail == "仅第1–3页可检索")
    val draft = DraftCardModel(binding, "draft", "阅读记录", DraftSaveStatus.Saving,
        listOf(DraftField("note", "备注", "保留本地输入")), canSubmit = true)
    verify(!draft.canEdit && !draft.canSave && !draft.canPreviewSubmission)
    verify(draft.copy(saveStatus = DraftSaveStatus.Unknown).canPreviewSubmission.not())
    verify(draft.copy(saveStatus = DraftSaveStatus.Unsaved).canPreviewSubmission)
    verify(draft.copy(saveStatus = DraftSaveStatus.Saved).saveStatus.label == "已保存草稿")
    val report = ReportVersion("v2", "报告", ReportVersionStatus.Conflict, "source-v1")
    verify(report.actions == setOf(CardCapability.ViewVersion, CardCapability.CompareVersions))
    verify(report.copy(status = ReportVersionStatus.Draft).actions ==
        setOf(CardCapability.EditReport, CardCapability.PreviewReportSave))
    verify(report.copy(status = ReportVersionStatus.History).actions == setOf(CardCapability.ViewVersion))
    println("PASS: $assertions action-card projection and safety checks; no host/network invoked")
}
