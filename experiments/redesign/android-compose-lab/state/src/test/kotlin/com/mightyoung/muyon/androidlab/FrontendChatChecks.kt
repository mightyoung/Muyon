package com.mightyoung.muyon.androidlab

/** Standalone checks; no Android/Binder/model evidence is claimed. */
fun runFrontendChatChecks() {
    check(!frontendCanSend("", "idle"))
    check(!frontendCanSend("x".repeat(4097), "idle"))
    check(!frontendCanSend("供".repeat(1366), "idle"))
    check(frontendCanSend("读取供应商", "idle"))
    listOf("running", "queued", "unknown", "UNKNOWN", "cancel_requested").forEach {
        check(!frontendCanSend("读取", it)) { "must not resubmit $it" }
    }
    check(frontendCanSend("读取", "completed"))
    check(frontendCanCancel("running"))
    check(!frontendCanCancel("cancel_requested"))
    check(!frontendCanCancel("completed"))
    check(frontendNeedsReconcile("UNKNOWN"))
    check(frontendNeedsReconcile("outcome_unknown"))
    check(frontendStatusLabel("cancel_requested").contains("等待"))
    check(frontendStatusLabel("UNKNOWN").contains("未知"))
    check(frontendStatusLabel("failed", "provider_budget_reservation_failed")=="预算不足 · 未发送到 provider")
    check(frontendNeedsReconcile("failed", "provider_budget_reservation_failed"))
    check(!frontendNeedsReconcile("failed", "chat_authority_denied"))
    check(frontendBudgetGuidance("failed", "provider_budget_reservation_failed")?.contains("保存") == true)
    check(frontendBudgetGuidance("failed", "provider_budget_reservation_failed")?.contains("手动发送") == true)
    check(frontendBudgetGuidance("unknown", "provider_budget_reservation_failed") == null)
    check(frontendStatusLabel("failed","chat_context_budget_exceeded")=="上下文超出预算 · 未发送到 provider")
    check(frontendBudgetGuidance("failed","chat_context_budget_exceeded")?.contains("不会自动删历史重试")==true)
    check(frontendNeedsReconcile("failed","chat_context_budget_exceeded"))
    check(frontendBudgetGuidance("unknown","chat_context_budget_exceeded")==null)
    val calls = mutableListOf<Pair<String,String>>()
    val port = object : ChatReadPort {
        override var snapshot = ChatReadView()
        override fun submit(conversationId:String,text:String) { calls += conversationId to text }
        override fun cancel(conversationId:String) { error("send must not cancel") }
        override fun reconcile(conversationId:String) { error("send must not reconcile") }
    }
    check(frontendSubmit(port,"old-chat","原输入"))
    check(calls.single() == "old-chat" to "原输入")
    port.snapshot=ChatReadView(mapOf("old-chat" to ChatReadConversation(status="UNKNOWN")))
    check(!frontendSubmit(port,"old-chat","不得重发"))
    check(calls.size==1)
    check(frontendSubmit(port,"new-chat","另一个会话"))
    check(calls.last()=="new-chat" to "另一个会话")
    println("PASS frontend input/status/budget policy (no Android/model execution)")
}
