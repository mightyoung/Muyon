package com.mightyoung.muyon.androidlab
// The private predicate below is copied verbatim from the instrumentation test.
private fun requestCompleted(value:ChatReadConversation?,requestId:String)=value?.requestId==requestId && value.status=="completed"
fun main() {
    val first=ChatReadConversation(text="first",requestId="first",answer="离线普通文本响应",status="completed")
    val second=ChatReadConversation(text="第二条普通文本",requestId="second",status="submitting")
    check(frontendStatusLabel(first.status)=="已完成")
    check(!requestCompleted(first,"second"))
    for(status in listOf("submitting","accepted","existing","events","reconciling","unknown","outcome_unknown","failed","cancelled"))
        check(!requestCompleted(second.copy(status=status),"second")) { status }
    check(!requestCompleted(null,"second"))
    check(requestCompleted(second.copy(status="completed",answer="离线普通文本响应"),"second"))
    // The wait must stop even with a bad answer, leaving the original answer assertion effective.
    val emptyCompleted=second.copy(status="completed")
    check(requestCompleted(emptyCompleted,"second"))
    check(runCatching { check(emptyCompleted.answer=="离线普通文本响应") }.isFailure)
    println("PASS request identity and terminal wait; old rendered completion rejected; completed-empty still fails answer assertion; synthetic policy only, Compose NOT_RUN")
}
