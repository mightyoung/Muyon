package com.mightyoung.muyon.androidlab

/** Standalone pure policy probe. No Android, Binder, database, HTTP or native target. */
fun main() {
    val completed = ChatReadConversation(
        text = "first", requestId = "request1", runId = "run1",
        admittedServiceEpoch = "epoch1", answer = "plain answer", receipt = "receipt1",
        originalReceiptIdentity = "identity1", providerReceipt = true,
        status = "completed", cursor = 3,
    )
    val unknown = completed.disclosureLost("last Activity stopped")
    check(unknown.status == "unknown" && unknown.cursor == 0L)
    check(unknown.answer.isEmpty() && unknown.receipt == null)
    check(unknown.requestId == completed.requestId && unknown.runId == completed.runId)
    check(unknown.admittedServiceEpoch == completed.admittedServiceEpoch)
    check(unknown.originalReceiptIdentity == completed.originalReceiptIdentity)
    check(!frontendCanSend("second nonblank prompt", unknown.status))
    check(frontendNeedsReconcile(unknown.status))
    var submissions = 0
    val port = object : ChatReadPort {
        override var snapshot = ChatReadView(mapOf("conversation1" to unknown))
        override fun submit(conversationId: String, text: String) { submissions++ }
        override fun cancel(conversationId: String) = error("not a cancellation test")
        override fun reconcile(conversationId: String) = error("no Service in this pure probe")
    }
    check(!frontendSubmit(port, "conversation1", "second nonblank prompt"))
    check(submissions == 0)
    // A verified terminal from an explicit lookup is required before a new user send.
    // Supplying the view here tests presentation policy only, not actual reconciliation.
    port.snapshot = ChatReadView(mapOf("conversation1" to completed))
    check(frontendCanSend("second nonblank prompt", completed.status))
    check(frontendSubmit(port, "conversation1", "second nonblank prompt"))
    check(submissions == 1)
    println("PASS ordinary recreation disclosure/identity/send policy; Android/Binder reconciliation NOT_RUN")
}
