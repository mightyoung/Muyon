package com.mightyoung.muyon.androidlab
fun runChatReadChecks() {
    check(!ChatReadBounds.validText(" \n"))
    check(ChatReadBounds.validText("a".repeat(4096)))
    check(!ChatReadBounds.validText("a".repeat(4097)))
    check(!ChatReadBounds.validText("供".repeat(1366)))
    check(ChatReadBounds.validSelection("a".repeat(128)))
    check(!ChatReadBounds.validSelection("a".repeat(129)))
    check(ChatReadBounds.validReply("a".repeat(65536)))
    check(!ChatReadBounds.validReply("a".repeat(65537)))
    check(ChatReadConversation(status="unknown",requestId="original").requestId=="original")
    val original=ChatReadConversation(requestId="request",runId="run",admittedServiceEpoch="old-epoch",answer="hidden",receipt="original-ref",projection="hidden",status="completed",cursor=4,originalReceiptIdentity="original")
    val recovered=original.disclosureLost("binder_lost")
    check(recovered.cursor==0L && recovered.answer.isEmpty() && recovered.projection==null && recovered.receipt==null)
    check(recovered.requestId==original.requestId && recovered.runId==original.runId && recovered.admittedServiceEpoch==original.admittedServiceEpoch && recovered.originalReceiptIdentity==original.originalReceiptIdentity)
    println("PASS 11 chat read UTF-8 bounds and immutable identity checks; Binder/native NOT_RUN")
}
