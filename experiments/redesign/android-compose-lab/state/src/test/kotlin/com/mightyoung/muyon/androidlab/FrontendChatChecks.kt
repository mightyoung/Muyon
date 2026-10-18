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
    println("PASS frontend input/status policy (21 assertions; no Android/model execution)")
}
