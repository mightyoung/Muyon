package com.mightyoung.muyon.androidlab
fun runPendingChatActionChecks() {
    val cancelled=PendingChatAction("original")
    check(!cancelled.cancel("different"))
    check(cancelled.cancel("original"))
    check(!cancelled.dispatch()) // late successful bootstrap must never submit
    check(!cancelled.cancel("original"))
    val sent=PendingChatAction("sent")
    check(sent.dispatch())
    check(!sent.cancel("sent")) // dispatch is uncertain; use native cancel+lookup
    check(!sent.dispatch())
    println("PASS 7 pending chat cancellation/late bootstrap checks; Android runtime NOT_RUN")
}
