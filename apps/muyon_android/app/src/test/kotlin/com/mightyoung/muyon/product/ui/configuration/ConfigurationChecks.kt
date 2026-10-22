package com.mightyoung.muyon.product.ui.configuration

import com.mightyoung.muyon.product.agents.setup.*

fun main() {
    var passed = 0
    fun test(name: String, body: () -> Unit) { body(); println("PASS $name"); passed++ }
    fun review(): BotConfigurationEditor = BotConfigurationEditor(BotSetupDraft("scope")).apply {
        name = "管理员"; check(next()); purpose = "整理论文"; check(next())
        suggest(); check(useSuggestion()); role = "我的角色"; check(next())
    }
    test("back retains user edits and preview uses edited role") {
        val editor = review(); check(editor.preview()!!.role == "我的角色")
        editor.back(); check(editor.role == "我的角色"); editor.back()
        check(editor.purpose == "整理论文"); check(editor.next()); editor.suggest()
        check(!editor.useSuggestion()); check(editor.role == "我的角色")
    }
    test("name never grants authority and preview never creates or starts") {
        val preview = review().preview()!!
        check(!preview.canCreate && !preview.canStart)
        check(preview.capabilities.isEmpty()); check(preview.permissionSummary.contains("未授予"))
    }
    test("invalid blank remains editable and blocks forward") {
        val editor = BotConfigurationEditor(BotSetupDraft("scope"))
        editor.name = ""; check(!editor.next()); check(editor.error != null)
        editor.name = "我的助手"; check(editor.next()); check(editor.error == null)
    }
    test("unknown blocks edits and exposes only original intent query") {
        val editor = review(); val preview = editor.preview()!!
        editor.draft.observePendingCreation("original", preview.revision)
        editor.draft.observeCreationResult("original", CreationStatus.UNKNOWN)
        check(!editor.editable); check(!editor.next()); check(editor.preview() == null)
        check(editor.queryIntentId == "original")
        check(!editor.useSuggestion()); check(!editor.back())
    }
    test("unavailable capabilities are never selected by suggestion") {
        val editor = BotConfigurationEditor(BotSetupDraft("scope"))
        editor.draft.offerChoices(listOf(CapabilityOption("blocked", "1", false, "未接入", "", "")), emptyList())
        check(!editor.select(setOf("blocked"), emptySet()))
        check(editor.draft.choices().selectedCapabilityIds.isEmpty())
    }
    println("$passed/5 PASS")
}
