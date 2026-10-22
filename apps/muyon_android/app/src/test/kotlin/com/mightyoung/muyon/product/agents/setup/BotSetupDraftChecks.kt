package com.mightyoung.muyon.product.agents.setup

private fun rejects(block: () -> Unit) {
    check(runCatching(block).exceptionOrNull() is IllegalArgumentException)
}

fun main() {
    var passed = 0
    fun test(name: String, body: () -> Unit) { body(); passed++; println("PASS $name") }
    fun ready(): BotSetupDraft = BotSetupDraft("account/project", "draft-1").apply {
        editName("论文助手📚"); next(); editPurpose("整理当前项目文献"); next()
    }
    test("name remains a draft; stable identity and duplicate labels") {
        val a = BotSetupDraft("account/project", "draft-a")
        val b = BotSetupDraft("account/project", "draft-b")
        a.editName("助手"); b.editName("助手")
        check(a.snapshot().draftId != b.snapshot().draftId)
        check(a.snapshot().creation.status == CreationStatus.NOT_REQUESTED)
        rejects { a.preview() }
        rejects { a.editName("x".repeat(61)) }
        rejects { a.editName("\u0000") }
        rejects { a.editName("\u200B") }
        rejects { a.editName("   ") }
    }
    test("rename and intervening edit invalidate late suggestions") {
        val d = ready()
        val old = d.requestSuggestions()
        d.editName("采购助手")
        check(!d.receiveSuggestions(old, LocalSetupTemplates.suggest(old)))
        val current = d.requestSuggestions()
        d.editPurpose("手动用途")
        check(!d.receiveSuggestions(current, LocalSetupTemplates.suggest(current)))
        check(d.snapshot().purpose.value == "手动用途")
    }
    test("same revision superseded request cannot publish; cancel discards late results") {
        val d = ready()
        val first = d.requestSuggestions(); val second = d.requestSuggestions()
        check(!d.receiveSuggestions(first, LocalSetupTemplates.suggest(first)))
        check(d.receiveSuggestions(second, LocalSetupTemplates.suggest(second)))
        val third = d.requestSuggestions(); d.cancel()
        check(!d.receiveSuggestions(third, LocalSetupTemplates.suggest(third)))
        d.resume()
        check(d.snapshot().purpose.value == "整理当前项目文献")
    }
    test("template proposal never mutates user fields; selection explicit and locked") {
        val d = ready()
        val request = d.requestSuggestions()
        val proposal = LocalSetupTemplates.suggest(request)
        check(proposal.source.label == "本地模板建议")
        check(d.receiveSuggestions(request, proposal))
        check(d.snapshot().role.value.isEmpty())
        check(d.acceptRoleSuggestion(request))
        check(d.snapshot().role.origin == FieldOrigin.TEMPLATE)
        d.editRole("我的角色")
        val next = d.requestSuggestions()
        check(d.receiveSuggestions(next, LocalSetupTemplates.suggest(next)))
        check(!d.acceptRoleSuggestion(next))
        check(d.snapshot().role.value == "我的角色")
        check(d.snapshot().role.userLocked)
        check(d.snapshot().role.revision <= d.snapshot().revision)
    }
    test("manual completion, back and cancellation preserve values") {
        val d = ready(); d.editRole("研究员"); d.next()
        check(d.snapshot().step == SetupStep.REVIEW)
        val before = d.preview()
        d.back(); check(d.snapshot().role.value == "研究员"); d.next()
        d.cancel(); check(d.snapshot().cancelled); d.resume()
        check(d.preview().name == before.name)
        check(d.preview().purpose == before.purpose)
        check(d.preview().role == before.role)
        rejects { d.restoreScope("different/project") }
    }
    test("no authority, cost or capability inferred from name and role") {
        val d = ready(); d.editName("采购付款 Bot"); d.editRole("自动支付"); d.next()
        val p = d.preview()
        check(p.capabilities.isEmpty() && p.materialScope.isEmpty())
        check(p.permissionSummary == "未配置；未授予新权限")
        check(p.costSummary == "费用未知；未配置执行预算")
        check(p.actualCost == null && p.heldCost == null)
        check(!p.canCreate && !p.canStart)
    }
    test("review revision binding and unknown original intent freeze duplicate creation") {
        val d = ready(); d.editRole("研究员"); d.next()
        val old = d.preview(); d.editName("改名")
        rejects { d.observePendingCreation("intent-1", old.revision) }
        d.next(); val p = d.preview()
        d.observePendingCreation("intent-1", p.revision)
        rejects { d.observePendingCreation("intent-2", p.revision) }
        d.observeCreationResult("intent-1", CreationStatus.UNKNOWN)
        rejects { d.editName("重建") }
        rejects { d.cancel() }
        rejects { d.observePendingCreation("intent-2", p.revision) }
        rejects { d.observeCreationResult("other", CreationStatus.CREATED, "agent-other") }
        check(d.snapshot().creation.intentId == "intent-1")
        d.observeCreationResult("intent-1", CreationStatus.UNKNOWN)
        d.observeCreationResult("intent-1", CreationStatus.CREATED, "agent-1")
        check(d.snapshot().creation.agentId == "agent-1")
        rejects { d.observeCreationResult("intent-1", CreationStatus.REJECTED) }
    }
    test("definite rejection preserves draft; invalid transitions rejected") {
        val d = ready(); d.editRole("研究员"); d.next()
        rejects { d.observeCreationResult("none", CreationStatus.UNKNOWN) }
        d.observePendingCreation("i", d.preview().revision)
        d.observeCreationResult("i", CreationStatus.REJECTED)
        check(d.snapshot().purpose.value == "整理当前项目文献")
        d.editPurpose("补充说明")
        check(d.snapshot().creation.status == CreationStatus.NOT_REQUESTED)
    }
    println("PASS $passed offline checks")
}
