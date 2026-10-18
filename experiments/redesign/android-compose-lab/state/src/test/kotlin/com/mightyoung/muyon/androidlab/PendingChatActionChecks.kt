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
    val refused=PendingChatAction("refused")
    check(refused.fail())
    check(!refused.dispatch())
    check(!refused.fail())
    var deliveries=0
    val completion=ChatReadCompletion{value->check(value==null);deliveries++}
    check(completion.complete(null))
    check(!completion.complete("late-success"))
    check(deliveries==1)
    listOf("busy","rejected","invisible","stopping","queue_refusal","bind_timeout").forEach{reason->
        val action=PendingChatAction(reason)
        var callbacks=0
        val once=ChatReadCompletion{callbacks++}
        check(action.fail());once.complete(null)
        check(!action.dispatch())
        once.complete("late_handshake");check(callbacks==1)
    }
    println("PASS 31 pending chat cancellation/late bootstrap checks; Android runtime NOT_RUN")
}
