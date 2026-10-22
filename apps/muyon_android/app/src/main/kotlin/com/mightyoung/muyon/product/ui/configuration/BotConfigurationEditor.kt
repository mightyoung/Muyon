package com.mightyoung.muyon.product.ui.configuration
import com.mightyoung.muyon.product.agents.setup.*

/** UI text buffers only; the host retains this editor while navigating. No persistence or transport. */
class BotConfigurationEditor(val draft: BotSetupDraft) {
    var name = draft.snapshot().name.value
    var purpose = draft.snapshot().purpose.value
    var role = draft.snapshot().role.value
    var error: String? = null
        private set
    val editable get() = !draft.snapshot().cancelled && draft.snapshot().creation.status in
        setOf(CreationStatus.NOT_REQUESTED, CreationStatus.REJECTED)
    val queryIntentId get() = draft.snapshot().creation.takeIf {
        it.status in setOf(CreationStatus.UNKNOWN, CreationStatus.PENDING)
    }?.intentId
    private var token: SuggestionRequest? = null
    private fun action(block: () -> Unit): Boolean {
        if (!editable) { error = "草稿已关闭或创建结果待核；请查询原意图"; return false }
        return try { block(); error = null; true } catch (failure: IllegalArgumentException) {
            error = failure.message ?: "请检查输入与当前能力"; false
        }
    }
    fun next(): Boolean = action {
        when (draft.snapshot().step) {
            SetupStep.NAME -> if (name != draft.snapshot().name.value) draft.editName(name)
            SetupStep.PURPOSE -> if (purpose != draft.snapshot().purpose.value) draft.editPurpose(purpose)
            SetupStep.CONFIGURATION -> if (role != draft.snapshot().role.value) draft.editRole(role)
            SetupStep.REVIEW -> Unit
        }
        draft.next()
    }
    fun back(): Boolean = action { draft.back() }
    fun suggest(): Boolean = action {
        val request = draft.requestSuggestions()
        check(draft.receiveSuggestions(request, LocalSetupTemplates.suggest(request)))
        token = request
    }
    fun useSuggestion(): Boolean {
        if (!editable) return false
        val request = token ?: return false
        // A buffer edit is already a user choice even before moving to the next step.
        if (role != draft.snapshot().role.value) return false
        val accepted = draft.acceptRoleSuggestion(request)
        if (accepted) role = draft.snapshot().role.value
        return accepted
    }
    fun select(capabilities: Set<String>, materials: Set<String>): Boolean =
        action { draft.selectChoices(capabilities, materials) }
    fun preview(): SetupPreview? = if (editable && draft.snapshot().step == SetupStep.REVIEW)
        try { draft.preview() } catch (_: IllegalArgumentException) { null } else null
}
