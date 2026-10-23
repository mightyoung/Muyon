package com.mightyoung.muyon.product.ui.publicservices

data class AnswerRef(val id: String, val revision: String)
data class SnapshotRef(val id: String, val revision: String)
data class SourceBinding(val resultId: String, val documentId: String, val revision: String,
    val textDigest: String, val startByte: String, val endByte: String, val pageIndex: Int?)
data class PresentationRequest(val requestId: String, val answerRef: AnswerRef, val snapshotRef: SnapshotRef,
    val displayIntent: String, val catalogVersion: String, val capabilityViewRef: String)
enum class ComponentType { MessageBlock, ChoiceCard, FormCard, ResultList, SourceCard, AttachmentCard, TaskProgressCard, DraftArtifactCard, ConfirmationCard, ReceiptCard }
sealed interface Props {
    data class Message(val text: String, val answerRef: AnswerRef) : Props
    data class Choice(val optionIds: List<String>, val selectedIds: Set<String>, val customText: String?) : Props
    data class Form(val fieldIds: List<String>, val fieldTypes: Map<String,String>, val values: Map<String,String>, val validationMessages: Map<String,String>) : Props
    data class Results(val itemIds: List<String>, val labels: List<String>, val sourceBindings: List<SourceBinding>) : Props
    data class Source(val sourceBinding: SourceBinding, val quote: String, val claimRelation: String) : Props
    data class Attachment(val documentRef: String, val stageCoverageRefs: List<String>) : Props
    data class Progress(val jobRef: String, val stage: String, val processed: String, val total: String?) : Props
    data class DraftArtifact(val draftRef: String, val contentSummary: String, val saveStatus: String) : Props
    data class Confirmation(val preparedRef: String) : Props
    data class Receipt(val originalIntentId: String, val receiptRef: String?) : Props
}
enum class EventKind { LocalView, DraftEdit, DomainRequest }
data class EventBinding(val eventKind: EventKind, val actionRef: String)
data class Node(val id: String, val componentType: ComponentType, val typedProps: Props,
    val bindingRefs: List<String>, val children: List<String>, val eventBindings: List<EventBinding>)
data class UIPlan(val schemaVersion: Int, val surfaceId: String, val planRevision: String,
    val snapshotRef: SnapshotRef, val root: String, val nodes: List<Node>)
data class ValidationContext(val snapshotRef: SnapshotRef, val scopeGeneration: String, val allowedActions: Set<String>,
    val sources: Map<String,SourceBinding>, val readAllowed: Boolean, val actionAllowed: Boolean)
enum class Decision { TextOnly, Supplement, Replace }
data class PresentationResult(val decision: Decision, val reasonCode: String, val plan: ValidatedPlan?, val diagnostics: List<String>)
