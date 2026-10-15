package com.mightyoung.muyon.androidlab

/** Service-process correlation only. Keys are never accepted from or returned to a UI client. */
class AgentClientKeys(private val processPrefix: String) {
    init { require(Regex("[0-9a-f]{16}").matches(processPrefix)) }
    private var sequence=0L
    @Synchronized fun next(): String {
        sequence=Math.incrementExact(sequence)
        return processPrefix+sequence.toString(16).padStart(16,'0')
    }
}
/** The app owns Binder linking; all link/native/gone work runs outside this registry's lock. */
class AgentLivenessRegistry<T:Any>(private val keys:AgentClientKeys, private val gone:(String)->Unit) {
    private class Entry<T>(val token:T,val key:String) {
        var connecting=true
        var dead=false
        var released=false
        var client:UiAgentClientRef?=null
    }
    private val lock=Any()
    private val entries=mutableMapOf<T,Entry<T>>()
    fun connect(token:T, link:((()->Unit)->Boolean), native:(String)->UiAgentWireReply):UiAgentWireReply {
        val (entry,needsLink)=synchronized(lock) {
            val existing=entries[token]
            if(existing!=null) {
                if(existing.dead || existing.released) return unavailable()
                if(existing.connecting) return UiAgentWireReply.Local(UiAgentLocalStatus.BUSY)
                existing.connecting=true
                existing to false
            } else {
                if(entries.size>=2) return UiAgentWireReply.Local(UiAgentLocalStatus.BUSY)
                val value=Entry(token,keys.next())
                entries[token]=value
                value to true
            }
        }
        var nativeStarted=false
        try {
            if(needsLink && !link { died(entry) }) died(entry)
            if(synchronized(lock){entry.dead}) return unavailable()
            nativeStarted=true
            val result=native(entry.key)
            val dead=synchronized(lock) {
                if(!entry.dead && result is UiAgentWireReply.Connected) entry.client=result.client
                entry.dead
            }
            return if(dead) unavailable() else result
        } finally {
            val dead=synchronized(lock) {
                entry.connecting=false
                if(entry.dead && entries[token]===entry) entries.remove(token)
                entry.dead
            }
            // Death can have reached Rust before connect itself. Reissue only the original
            // key after the late connect so it cannot leave a newly created live lease.
            if(dead && nativeStarted) gone(entry.key)
        }
    }
    private fun died(entry:Entry<T>) {
        val notify=synchronized(lock) {
            if(entry.dead) false else {
                entry.dead=true
                if(!entry.connecting && entries[entry.token]===entry) entries.remove(entry.token)
                true
            }
        }
        if(notify) gone(entry.key)
    }
    /** Call only after actual native release acknowledgement; not a Rust stop implementation. */
    fun markReleased(client:UiAgentClientRef):Boolean = synchronized(lock) {
        val entry=entries.values.firstOrNull{!it.dead && it.client==client} ?: return false
        entry.released=true
        true
    }
    internal fun retainedTokens():Int=synchronized(lock){entries.size}
    private fun unavailable()=UiAgentWireReply.Local(UiAgentLocalStatus.UNAVAILABLE)
}
