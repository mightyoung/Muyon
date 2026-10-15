package com.mightyoung.muyon.androidlab

/** Service-process correlation only. Keys are never accepted from or returned to a UI client. */
class AgentClientKeys(private val processPrefix: String) {
    fun next(): String = error("key_source_unavailable")
}
class AgentLivenessRegistry<T:Any>(private val keys:AgentClientKeys, private val gone:(String)->Unit) {
    fun connect(token:T, link:((()->Unit)->Boolean), native:(String)->UiAgentWireReply):UiAgentWireReply = UiAgentWireReply.Local(UiAgentLocalStatus.UNAVAILABLE)
    /** Call only after actual native release acknowledgement; not a Rust stop implementation. */
    fun markReleased(client:UiAgentClientRef):Boolean = false
    internal fun retainedTokens():Int = 0
}
