package com.mightyoung.muyon.product.ui.publicservices

import java.math.BigInteger
import java.util.Collections

private fun <T> immutableList(values: Collection<T>): List<T> = Collections.unmodifiableList(ArrayList(values))
private fun <T> immutableSet(values: Collection<T>): Set<T> = Collections.unmodifiableSet(LinkedHashSet(values))
private fun <K,V> immutableMap(values: Map<K,V>): Map<K,V> = Collections.unmodifiableMap(LinkedHashMap(values))
private fun freeze(p: Props): Props = when (p) {
    is Props.Message -> p.copy()
    is Props.Choice -> p.copy(optionIds = immutableList(p.optionIds), selectedIds = immutableSet(p.selectedIds))
    is Props.Form -> p.copy(fieldIds = immutableList(p.fieldIds), fieldTypes = immutableMap(p.fieldTypes), values = immutableMap(p.values), validationMessages = immutableMap(p.validationMessages))
    is Props.Results -> p.copy(itemIds = immutableList(p.itemIds), labels = immutableList(p.labels), sourceBindings = immutableList(p.sourceBindings))
    is Props.Source -> p.copy()
    is Props.Attachment -> p.copy(stageCoverageRefs = immutableList(p.stageCoverageRefs))
    is Props.Progress -> p.copy()
    is Props.DraftArtifact -> p.copy()
    is Props.Confirmation -> p.copy()
    is Props.Receipt -> p.copy()
}
/** Constructor is private; there is no unchecked factory, even inside this module. */
class ValidatedPlan private constructor(val plan: UIPlan, val context: ValidationContext) {
    internal companion object {
        fun validate(request: PresentationRequest, input: UIPlan, host: ValidationContext): PresentationResult = try {
            require(input.nodes.size in 1..256) { "node_limit" }
            val plan = input.copy(nodes = immutableList(input.nodes.map { n -> n.copy(typedProps = freeze(n.typedProps),
                bindingRefs = immutableList(n.bindingRefs), children = immutableList(n.children), eventBindings = immutableList(n.eventBindings)) }))
            val context = host.copy(allowedActions = immutableSet(host.allowedActions), sources = immutableMap(host.sources))
            inspect(request, plan, context)
            PresentationResult(Decision.Supplement, "validated", ValidatedPlan(plan, context), emptyList())
        } catch (error: IllegalArgumentException) {
            PresentationResult(Decision.TextOnly, error.message ?: "invalid_plan", null, emptyList())
        }
    }
}
fun validatePlan(request: PresentationRequest, plan: UIPlan, context: ValidationContext): PresentationResult = ValidatedPlan.validate(request, plan, context)
fun validateEncodedPlan(request: PresentationRequest, raw: String, context: ValidationContext): PresentationResult = try {
    validatePlan(request, decodeUIPlan(raw), context)
} catch (_: IllegalArgumentException) { PresentationResult(Decision.TextOnly, "invalid_wire_plan", null, emptyList()) }
private fun inspectSource(s: SourceBinding, context: ValidationContext, quote: String? = null) {
    parsePublicId(s.resultId); parsePublicId(s.documentId); parseRevision(s.revision); parsePublicDigest(s.textDigest)
    parseRevision(s.startByte); parseRevision(s.endByte)
    require(s.pageIndex == null || s.pageIndex >= 0) { "invalid_page" }
    val start = BigInteger(s.startByte); val end = BigInteger(s.endByte)
    require(start <= end) { "invalid_source_range" }
    require(context.sources.containsValue(s)) { "unresolved_source" }
    if (quote != null) require(BigInteger.valueOf(quote.toByteArray(Charsets.UTF_8).size.toLong()) <= end - start) { "quote_exceeds_byte_range" }
}
private fun inspect(request: PresentationRequest, plan: UIPlan, context: ValidationContext) {
    require(plan.schemaVersion == 1) { "unsupported_schema" }
    parsePublicId(request.requestId); parsePublicId(request.answerRef.id); parseRevision(request.answerRef.revision)
    parsePublicId(request.displayIntent); parsePublicId(request.catalogVersion); parsePublicId(request.capabilityViewRef)
    parsePublicId(plan.surfaceId); parseRevision(plan.planRevision); parsePublicId(plan.snapshotRef.id); parseRevision(plan.snapshotRef.revision)
    parseRevision(context.scopeGeneration)
    require(context.readAllowed) { "read_permission_unavailable" }
    require(request.snapshotRef == plan.snapshotRef && context.snapshotRef == plan.snapshotRef) { "snapshot_mismatch" }
    require(plan.nodes.map { it.id }.distinct().size == plan.nodes.size) { "duplicate_node" }
    val nodes = plan.nodes.associateBy { it.id }; require(plan.root in nodes) { "missing_root" }
    var bytes = 0L
    fun display(value: String) { require(validUnicode(value)); bytes += value.toByteArray(Charsets.UTF_8).size; require(bytes <= 65536) { "text_limit" } }
    fun ids(values: Collection<String>) { values.forEach(::parsePublicId) }
    context.allowedActions.forEach(::parsePublicId)
    for (n in plan.nodes) {
        parsePublicId(n.id)
        require(n.children.size <= 32 && n.children.distinct().size == n.children.size) { "invalid_children" }
        require(n.children.all { it in nodes }) { "dangling_child" }
        require(n.bindingRefs.all { it in context.sources }) { "unresolved_binding" }
        for (e in n.eventBindings) {
            parsePublicId(e.actionRef); require(e.actionRef in context.allowedActions) { "unknown_action" }
            require(e.eventKind != EventKind.DomainRequest || context.actionAllowed) { "action_permission_unavailable" }
        }
        val expected = when (val p = n.typedProps) {
            is Props.Message -> { display(p.text); require(p.answerRef == request.answerRef) { "answer_mismatch" }; ComponentType.MessageBlock }
            is Props.Choice -> {
                ids(p.optionIds); require(p.optionIds.distinct().size == p.optionIds.size && p.selectedIds.all { it in p.optionIds }) { "invalid_choice" }
                p.customText?.let(::display); ComponentType.ChoiceCard
            }
            is Props.Form -> {
                ids(p.fieldIds); require(p.fieldIds.distinct().size == p.fieldIds.size) { "duplicate_field" }
                require(p.fieldTypes.keys == p.fieldIds.toSet() && p.fieldTypes.values.all { it in setOf("text", "decimal", "choice", "boolean") }) { "invalid_field_types" }
                require(p.values.keys.all { it in p.fieldIds } && p.validationMessages.keys.all { it in p.fieldIds }) { "unknown_field" }
                p.values.values.forEach(::display); p.validationMessages.values.forEach(::display); ComponentType.FormCard
            }
            is Props.Results -> {
                ids(p.itemIds); require(p.itemIds.distinct().size == p.itemIds.size && p.itemIds.size == p.labels.size && p.itemIds.size == p.sourceBindings.size) { "invalid_result_columns" }
                p.labels.forEach(::display); p.sourceBindings.forEach { inspectSource(it, context) }; ComponentType.ResultList
            }
            is Props.Source -> {
                display(p.quote); require(p.claimRelation in setOf("unassessed", "cited", "candidate")) { "invalid_claim_relation" }
                inspectSource(p.sourceBinding, context, p.quote); ComponentType.SourceCard
            }
            is Props.Attachment -> {
                parsePublicId(p.documentRef); ids(p.stageCoverageRefs)
                require(p.stageCoverageRefs.isEmpty()) { "host_coverage_resolution_required" }; ComponentType.AttachmentCard
            }
            is Props.Progress -> {
                parsePublicId(p.jobRef); display(p.stage); val count = parseRevision(p.processed); val total = p.total?.let(::parseRevision)
                require(total == null || count.length < total.length || count.length == total.length && count <= total) { "invalid_progress" }
                ComponentType.TaskProgressCard
            }
            is Props.DraftArtifact -> {
                parsePublicId(p.draftRef); display(p.contentSummary)
                require(p.saveStatus in setOf("unsaved", "saving", "saved", "unknown", "conflict")) { "invalid_save_status" }
                require(p.saveStatus == "unsaved") { "host_save_resolution_required" }; ComponentType.DraftArtifactCard
            }
            is Props.Confirmation -> { parsePublicId(p.preparedRef); throw IllegalArgumentException("host_prepared_resolution_required") }
            is Props.Receipt -> {
                parsePublicId(p.originalIntentId)
                p.receiptRef?.let { parsePublicId(it); throw IllegalArgumentException("host_receipt_resolution_required") }
                ComponentType.ReceiptCard
            }
        }
        require(n.componentType == expected) { "component_props_mismatch" }
    }
    val visiting = HashSet<String>(); val heights = HashMap<String,Int>()
    fun height(id: String, depth: Int): Int {
        require(depth <= 16) { "depth_limit" }
        heights[id]?.let { require(depth + it - 1 <= 16) { "depth_limit" }; return it }
        require(visiting.add(id)) { "cycle" }
        val result = 1 + (nodes.getValue(id).children.maxOfOrNull { height(it, depth + 1) } ?: 0)
        visiting.remove(id); heights[id] = result; return result
    }
    height(plan.root, 1)
    require(heights.size == nodes.size) { "unreachable_node" }
}
