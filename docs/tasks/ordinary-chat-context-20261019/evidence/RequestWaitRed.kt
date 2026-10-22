package com.mightyoung.muyon.androidlab
fun main() {
    val first=ChatReadConversation(text="first",requestId="first",answer="离线普通文本响应",status="completed")
    val second=ChatReadConversation(text="第二条普通文本",requestId="second",status="submitting")
    // Freeze the permitted interleaving before the Shell's next snapshot copy.
    check(frontendStatusLabel(first.status)=="已完成")
    check(second.text=="第二条普通文本")
    check(second.answer=="离线普通文本响应") { "old status-only wait passed for first request while second answer is empty" }
}
