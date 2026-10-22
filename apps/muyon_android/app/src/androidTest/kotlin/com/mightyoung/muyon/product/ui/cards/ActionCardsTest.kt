package com.mightyoung.muyon.product.ui.cards

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import com.mightyoung.muyon.product.ui.system.FoundationTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.CompositionLocalProvider
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class ActionCardsTest {
    @get:Rule val compose = createComposeRule()
    private val binding = CardBinding(CardScope("test-workspace", "test-conversation", "test-project", "test-agent", 1), "test-message", "test-card", 1, 1, "test-attempt", "test-digest")
    private val events = mutableListOf<CardAction>()
    private fun host(vararg capabilities: CardCapability) = CardInteractions(capabilities.toSet(), events::add)

    private fun surface(content: @Composable () -> Unit) {
        compose.setContent { FoundationTheme {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) { content() }
        } }
    }

    @Test fun unknownReceiptOnlyQueriesOriginalIntentAndKeepsUnknownCost() {
        surface { ReceiptCard(
            ReceiptCardModel(binding, OriginalCardRequest(binding, "submit", "original-intent"), ReceiptStatus.Unknown, "未确认是否写入", "¥0.002620", cancelRequested = true),
            host(*CardCapability.entries.toTypedArray())) }
        compose.onNodeWithText("结果未知").assertExists()
        compose.onNodeWithText("实际费用：未知").assertExists()
        compose.onNodeWithText("已记录取消意图；尚未确认取消；取消不代表回滚。").assertExists()
        compose.onNodeWithText("取消请求已发出", substring = true).assertDoesNotExist()
        compose.onNodeWithTag("card-query-receipt").performScrollTo().performClick()
        assertEquals(listOf(CardAction.QueryReceipt(binding, OriginalCardRequest(binding, "submit", "original-intent"))), events)
        compose.onNodeWithTag("card-request-cancel").assertDoesNotExist()
        compose.onNodeWithText("重试").assertDoesNotExist()
    }

    @Test fun attachmentPartialNeverClaimsWholeFileReadableOrInventsPercent() {
        surface { AttachmentCard(AttachmentCardModel(binding, "source", "fixture.pdf", "v1",
            AttachmentAvailability.Partial, listOf(AttachmentStage("提取", StageStatus.Partial, "3 / 5 页"),
                AttachmentStage("索引", StageStatus.Partial, "仅第1–3页可检索")), "第4–5页失败"),
            host(CardCapability.ViewAvailablePages, CardCapability.ViewFailureDetails)) }
        compose.onNodeWithText("部分可用").assertExists()
        compose.onNodeWithText("仅第1–3页可检索").assertExists()
        compose.onNodeWithText("保存附件不代表已读完全文。").assertExists()
        compose.onNodeWithTag("card-available-pages").performScrollTo().performClick()
        compose.onNodeWithTag("card-failure-details").performScrollTo().performClick()
        assertEquals(listOf(CardAction.ViewAvailablePages(binding, "source"), CardAction.ViewFailureDetails(binding, "source")), events)
    }

    @Test fun evidenceBindsAnchorVersionAndSeparatesExternalLink() {
        surface { EvidenceCard(EvidenceCardModel(binding, "主张", "原文片段", SourceRelation.Candidate,
            "source", "fixture.pdf", "v3", "第2页", "p2", "同源，不是独立证据", "https://example.org"),
            host(CardCapability.OpenSource, CardCapability.OpenExternal)) }
        compose.onNodeWithText("检索候选").assertExists()
        compose.onNodeWithTag("card-locate-source").performScrollTo().performClick()
        compose.onNodeWithTag("card-external-source").performScrollTo().performClick()
        assertEquals(CardAction.OpenSource(binding, "source", "v3", "p2"), events[0])
        assertEquals(ActionCategory.ExternalLink, events[1].category)
    }

    @Test fun missingAnchorOrHostCapabilityDisablesSourceAction() {
        surface { EvidenceCard(EvidenceCardModel(binding, "主张", "片段", SourceRelation.Cited,
            "source", "fixture.pdf", "v1", "位置未知", null, "来源可定位不等于主张已证实"), host(CardCapability.OpenSource)) }
        compose.onNodeWithTag("card-locate-source").assertIsNotEnabled()
        assertTrue(events.isEmpty())
    }

    @Test fun localSingleSelectionIsControlledAndNeverSendsOrSaves() {
        val model = mutableStateOf(ChoiceCardModel(binding, "阅读状态", SelectionMode.Single,
            listOf(ChoiceOption("todo", "待核对"), ChoiceOption("read", "已读完")), setOf("todo")))
        surface { ChoiceCard(model.value, host(CardCapability.EditDraft)) }
        compose.onNodeWithTag("card-choice-todo").assertIsSelected()
        compose.onNodeWithTag("card-choice-read").performClick()
        assertEquals(listOf(CardAction.ChangeSelection(binding, setOf("read"))), events)
        compose.onNodeWithTag("card-choice-todo").assertIsSelected()
        compose.runOnIdle { model.value = model.value.copy(selectedIds = setOf("read")) }
        compose.onNodeWithTag("card-choice-read").assertIsSelected()
    }

    @Test fun multiSelectionEmitsLocalDraftSet() {
        surface { ChoiceCard(ChoiceCardModel(binding, "材料", SelectionMode.Multiple,
            listOf(ChoiceOption("a", "材料A"), ChoiceOption("b", "材料B")), setOf("a")), host(CardCapability.EditDraft)) }
        compose.onNodeWithTag("card-choice-b").performClick()
        assertEquals(listOf(CardAction.ChangeSelection(binding, setOf("a", "b"))), events)
        compose.onNodeWithTag("card-choice-a").assertIsOn()
    }

    @Test fun draftEditSavePreviewAndSendRemainDistinctAndWaitForHostReceipt() {
        val model = mutableStateOf(DraftCardModel(binding, "draft", "记录", DraftSaveStatus.Unsaved,
            listOf(DraftField("note", "备注", "原内容")), canSubmit = true))
        surface { DraftCard(model.value, host(CardCapability.EditDraft, CardCapability.SaveDraft,
            CardCapability.PreviewDraftSubmission, CardCapability.SendDraft)) }
        compose.onNodeWithTag("card-field-note").performTextReplacement("新内容")
        compose.onNodeWithTag("card-save-draft").performScrollTo().performClick()
        compose.onNodeWithText("未保存").assertExists()
        compose.onNodeWithTag("card-submit-draft").performScrollTo().performClick()
        compose.onNodeWithTag("card-send-draft").performScrollTo().performClick()
        assertEquals(listOf(ActionCategory.LocalDraft, ActionCategory.LocalDraft, ActionCategory.BusinessPreview, ActionCategory.MessageSend), events.map { it.category })
        compose.runOnIdle { model.value = model.value.copy(saveStatus = DraftSaveStatus.Unknown, detail = "查询保存结果后再继续") }
        compose.onNodeWithTag("card-save-draft").assertIsNotEnabled()
        compose.onNodeWithTag("card-submit-draft").assertIsNotEnabled()
        compose.onNodeWithTag("card-send-draft").assertIsNotEnabled()
        compose.onNodeWithText("保存结果未知").assertExists()
        compose.onNodeWithText("已保存草稿").assertDoesNotExist()
    }

    @Test fun confirmationUsesLatestTrustedPreviewAndDoesNotTreatDismissAsCancellation() {
        val model = mutableStateOf(ConfirmationCardModel(binding, "intent", "确认修改", "目标", "a → b", "r3", "r4", "本地库", "仅本地", ConfirmationKind.Modification))
        surface { ConfirmationCard(model.value, host(CardCapability.RequestExecution, CardCapability.DismissPreview)) }
        compose.runOnIdle { model.value = model.value.copy(binding = binding.copy(stateRevision = 2, digest = "new"), expectedRevision = "r4", proposedRevision = "r5") }
        compose.onNodeWithTag("card-approve").performScrollTo().performClick()
        assertEquals(CardAction.RequestExecution(model.value.binding, model.value), events.single())
        compose.onNodeWithTag("card-dismiss-preview").performScrollTo().performClick()
        assertTrue(events.last() is CardAction.DismissPreview)
        compose.onNodeWithText("批准修改不等于批准披露。").assertExists()
    }

    @Test fun disclosurePreviewPreservesContentRecipientAndDistinctApproval() {
        val model = ConfirmationCardModel(binding, "disclosure-intent", "确认披露", "当前片段", "仅发送片段", "r1", "r1",
            "指定接收方", "由宿主确认费用", ConfirmationKind.Disclosure, "此次实际披露内容")
        surface { ConfirmationCard(model, host(CardCapability.RequestExecution)) }
        compose.onNodeWithText("此次披露内容：此次实际披露内容").assertExists()
        compose.onNodeWithText("接收方：指定接收方").assertExists()
        compose.onNodeWithText("批准修改").assertDoesNotExist()
        compose.onNodeWithTag("card-approve").performScrollTo().performClick()
        assertEquals(CardAction.RequestExecution(binding, model), events.single())
    }

    @Test fun cancelRequestNeverSynthesizesCancelledOrChangesOriginalIntent() {
        val model = mutableStateOf(ReceiptCardModel(binding, OriginalCardRequest(binding, "submit", "original"), ReceiptStatus.Running, "仍在执行"))
        surface { ReceiptCard(model.value, host(CardCapability.QueryReceipt, CardCapability.RequestCancel)) }
        compose.onNodeWithTag("card-request-cancel").performScrollTo().performClick()
        assertEquals(CardAction.RequestCancel(binding, OriginalCardRequest(binding, "submit", "original")), events.single())
        compose.onNodeWithText("执行中").assertExists()
        compose.runOnIdle { model.value = model.value.copy(cancelRequested = true) }
        compose.onNodeWithText("已记录取消意图；尚未确认取消；取消不代表回滚。").assertExists()
        compose.onNodeWithText("取消请求已发出", substring = true).assertDoesNotExist()
        compose.onNodeWithText("已取消").assertDoesNotExist()
        compose.onNodeWithTag("card-request-cancel").assertDoesNotExist()
        compose.onNodeWithTag("card-query-receipt").performScrollTo().performClick()
        assertEquals(CardAction.QueryReceipt(binding, OriginalCardRequest(binding, "submit", "original")), events.last())
    }

    @Test fun absentCapabilityDisablesApproval() {
        surface { ConfirmationCard(ConfirmationCardModel(binding, "intent", "确认", "目标", "变更", "r1", "r2", "本地库", "仅本地", ConfirmationKind.Modification), host()) }
        compose.onNodeWithTag("card-approve").assertIsNotEnabled()
        assertTrue(events.isEmpty())
    }

    @Test fun conflictOffersComparisonAndNeverSaveOrEdit() {
        surface { ProjectCards(ProjectCardsModel(binding, "项目", "仅本项目 · 本地资料", emptyList(),
            listOf(ReportVersion("v2", "报告", ReportVersionStatus.Conflict, "source-v1"))), host(*CardCapability.entries.toTypedArray())) }
        compose.onNodeWithTag("card-compare-v2").performScrollTo().performClick()
        assertEquals(listOf(CardAction.CompareVersions(binding, "v2")), events)
        compose.onNodeWithTag("card-edit-v2").assertDoesNotExist()
        compose.onNodeWithTag("card-preview-save-v2").assertDoesNotExist()
    }

    @Test fun largeTextNarrowSurfaceRetainsScrollAndDisabledActions() {
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                FoundationTheme { Column(Modifier.width(320.dp).height(400.dp).verticalScroll(rememberScrollState())) {
                    ReceiptCard(ReceiptCardModel(binding, OriginalCardRequest(binding, "submit", "original"), ReceiptStatus.Unknown, "长说明".repeat(50)), CardInteractions())
                } }
            }
        }
        compose.onNodeWithTag("card-query-receipt").performScrollTo().assertIsDisplayed().assertIsNotEnabled()
    }
}
