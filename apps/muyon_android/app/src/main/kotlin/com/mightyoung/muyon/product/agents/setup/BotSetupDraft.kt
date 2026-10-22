package com.mightyoung.muyon.product.agents.setup

import java.util.UUID

enum class SetupStep { NAME, PURPOSE, CONFIGURATION, REVIEW }
enum class FieldOrigin { USER, TEMPLATE }
enum class CreationStatus { NOT_REQUESTED, PENDING, UNKNOWN, REJECTED, CREATED }
data class DraftField(val value: String = "", val origin: FieldOrigin = FieldOrigin.USER,
    val revision: Long = 0, val userLocked: Boolean = false)
data class CreationObservation(val status: CreationStatus = CreationStatus.NOT_REQUESTED,
    val intentId: String? = null, val agentId: String? = null)
data class TemplateSource(val id: String, val version: Int, val label: String = "本地模板建议")
data class SuggestionRequest(val draftId: String, val revision: Long, val requestId: String,
    val name: String, val purpose: String)
data class RoleSuggestion(val role: String, val source: TemplateSource)
data class CapabilityOption(val id: String, val version: String, val available: Boolean,
    val reason: String, val inputs: String, val outputs: String)
data class MaterialOption(val id: String, val scope: String, val available: Boolean)
data class SetupChoices(val capabilities: List<CapabilityOption>, val materials: List<MaterialOption>,
    val selectedCapabilityIds: Set<String>, val selectedMaterialIds: Set<String>)
data class DraftSnapshot(val scope: String, val draftId: String, val revision: Long,
    val step: SetupStep, val name: DraftField, val purpose: DraftField, val role: DraftField,
    val cancelled: Boolean, val suggestion: RoleSuggestion?, val creation: CreationObservation)

/** Pure local review data. This is neither an AgentProfile nor a grant/creation command. */
data class SetupPreview(val draftId: String, val revision: Long, val name: String,
    val purpose: String, val role: String, val capabilities: List<CapabilityOption>,
    val materialScope: List<String>, val roleTemplateSource: TemplateSource?,
    val permissionSummary: String = "未配置；未授予新权限",
    val costSummary: String = "费用未知；未配置执行预算",
    val actualCost: String? = null, val heldCost: String? = null,
    val canCreate: Boolean = false, val canStart: Boolean = false)

/** Deterministic suggestions from purpose only; never infers access from a display name. */
object LocalSetupTemplates {
    fun suggest(request: SuggestionRequest): RoleSuggestion = when {
        "论文" in request.purpose || "文献" in request.purpose ->
            RoleSuggestion("文献整理助手", TemplateSource("paper-organizer", 1))
        "供应商" in request.purpose || "采购" in request.purpose ->
            RoleSuggestion("采购资料整理助手", TemplateSource("supplier-organizer", 1))
        else -> RoleSuggestion("通用资料整理助手", TemplateSource("general-organizer", 1))
    }
}

/**
 * In-memory, single-owner state machine for a future ViewModel. No Context, repository,
 * transport, AgentCatalog, model or executor is reachable here. Confine calls to one UI thread.
 * Scope is an opaque account + project identity supplied by the trusted host.
 */
class BotSetupDraft(private val scope: String, private val draftId: String = UUID.randomUUID().toString()) {
    private var revision = 0L
    private var step = SetupStep.NAME
    private var name = DraftField()
    private var purpose = DraftField()
    private var role = DraftField()
    private var cancelled = false
    private var request: SuggestionRequest? = null
    private var suggestion: RoleSuggestion? = null
    private var selectedTemplate: TemplateSource? = null
    private var creation = CreationObservation()
    private var capabilities = emptyList<CapabilityOption>()
    private var materials = emptyList<MaterialOption>()
    private var selectedCapabilities = emptyList<CapabilityOption>()
    private var selectedMaterials = emptyList<String>()

    init { require(scope.isNotBlank() && draftId.isNotBlank() && draftId.length <= 80) }
    fun snapshot() = DraftSnapshot(scope, draftId, revision, step, name, purpose, role,
        cancelled, suggestion, creation)

    private fun editable() {
        require(!cancelled && creation.status in setOf(CreationStatus.NOT_REQUESTED, CreationStatus.REJECTED)) {
            "草稿已关闭或创建结果待核；请查询原意图"
        }
    }
    private fun invalidate() { request = null; suggestion = null }
    private fun changed() {
        require(revision < Long.MAX_VALUE)
        revision++
        invalidate()
        if (creation.status == CreationStatus.REJECTED) creation = CreationObservation()
    }
    private fun validText(value: String, max: Int, required: Boolean = true) {
        require(value.length <= max && (!required || value.any { !it.isWhitespace() && !Character.isSpaceChar(it) }))
        require(value.none { it.isISOControl() || Character.getType(it) == Character.FORMAT.toInt() })
        var index = 0
        while (index < value.length) {
            val c = value[index++]
            if (Character.isHighSurrogate(c)) require(index < value.length && Character.isLowSurrogate(value[index++]))
            else require(!Character.isLowSurrogate(c))
        }
    }
    fun editName(value: String) { editable(); validText(value, 60); changed(); name = DraftField(value, FieldOrigin.USER, revision, true) }
    fun editPurpose(value: String) { editable(); validText(value, 8000); changed(); purpose = DraftField(value, FieldOrigin.USER, revision, true) }
    fun editRole(value: String) { editable(); validText(value, 160); changed(); role = DraftField(value, FieldOrigin.USER, revision, true); selectedTemplate = null }
    fun next() {
        editable()
        when (step) {
            SetupStep.NAME -> { validText(name.value, 60); step = SetupStep.PURPOSE }
            SetupStep.PURPOSE -> { validText(purpose.value, 8000); step = SetupStep.CONFIGURATION }
            SetupStep.CONFIGURATION -> { validText(role.value, 160); step = SetupStep.REVIEW }
            SetupStep.REVIEW -> Unit
        }
    }
    fun back() { editable(); step = SetupStep.entries[(step.ordinal - 1).coerceAtLeast(0)] }
    fun cancel() { editable(); cancelled = true; invalidate() }
    fun resume() { require(cancelled); cancelled = false }
    fun restoreScope(currentScope: String) { require(scope == currentScope) { "账户或项目不同，不能恢复此草稿" } }

    fun requestSuggestions(): SuggestionRequest {
        editable(); validText(name.value, 60); validText(purpose.value, 8000)
        suggestion = null
        return SuggestionRequest(draftId, revision, UUID.randomUUID().toString(), name.value, purpose.value)
            .also { request = it }
    }
    fun receiveSuggestions(token: SuggestionRequest, value: RoleSuggestion): Boolean {
        if (cancelled || token != request || token.revision != revision) return false
        // Only this reviewed offline provider is supported. No caller-provided model text.
        if (value != LocalSetupTemplates.suggest(token)) return false
        suggestion = value
        return true
    }
    fun acceptRoleSuggestion(token: SuggestionRequest): Boolean {
        editable()
        val proposed = suggestion ?: return false
        if (request != token || revision != token.revision || role.userLocked) return false
        validText(proposed.role, 160)
        changed(); role = DraftField(proposed.role, FieldOrigin.TEMPLATE, revision)
        selectedTemplate = proposed.source
        return true
    }

    fun choices() = SetupChoices(capabilities.toList(), materials.toList(),
        selectedCapabilities.map { it.id }.toSet(), selectedMaterials.toSet())

    /** Host supplies current allowed metadata; changing availability/version requires reselection. */
    fun offerChoices(allowedCapabilities: List<CapabilityOption>, allowedMaterials: List<MaterialOption>) {
        editable()
        require(allowedCapabilities.map { it.id }.distinct().size == allowedCapabilities.size)
        require(allowedMaterials.map { it.id }.distinct().size == allowedMaterials.size)
        require(allowedCapabilities.all { it.id.isNotBlank() && it.version.isNotBlank() })
        require(allowedMaterials.all { it.id.isNotBlank() && it.scope == scope })
        changed(); capabilities = allowedCapabilities.toList(); materials = allowedMaterials.toList()
        selectedCapabilities = selectedCapabilities.filter { it.available && it in capabilities }
        selectedMaterials = selectedMaterials.filter { id -> materials.any { it.id == id && it.available } }
    }
    fun selectChoices(capabilityIds: Set<String>, materialIds: Set<String>) {
        editable()
        require(capabilityIds.all { id -> capabilities.any { it.id == id && it.available } })
        require(materialIds.all { id -> materials.any { it.id == id && it.available && it.scope == scope } })
        changed()
        selectedCapabilities = capabilities.filter { it.id in capabilityIds }
        selectedMaterials = materials.filter { it.id in materialIds }.map { it.id }
    }
    fun preview(): SetupPreview {
        editable(); require(step == SetupStep.REVIEW)
        validText(name.value, 60); validText(purpose.value, 8000); validText(role.value, 160)
        return SetupPreview(draftId, revision, name.value, purpose.value, role.value,
            selectedCapabilities.toList(), selectedMaterials.toList(), selectedTemplate)
    }

    /** Passive observation seam only. Does not submit, save, authorize or start anything. */
    fun observePendingCreation(intentId: String, expectedRevision: Long) {
        editable(); preview()
        require(intentId.isNotBlank() && expectedRevision == revision)
        require(creation.status == CreationStatus.NOT_REQUESTED)
        creation = CreationObservation(CreationStatus.PENDING, intentId)
        invalidate()
    }
    /** UNKNOWN may only reconcile the original intent. It never re-enters a create transition. */
    fun observeCreationResult(intentId: String, status: CreationStatus, agentId: String? = null) {
        require(creation.status in setOf(CreationStatus.PENDING, CreationStatus.UNKNOWN))
        require(creation.intentId == intentId)
        require(status in setOf(CreationStatus.UNKNOWN, CreationStatus.REJECTED, CreationStatus.CREATED))
        require(if (status == CreationStatus.CREATED) !agentId.isNullOrBlank() else agentId == null)
        creation = CreationObservation(status, intentId, agentId)
    }
}
