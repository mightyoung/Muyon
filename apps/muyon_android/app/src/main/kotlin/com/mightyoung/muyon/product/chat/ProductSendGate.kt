package com.mightyoung.muyon.product.chat

/** One local linearization boundary for write/flush and authority revocation.
 * Native checks and durable updates MUST happen outside this monitor. Advisory
 * reads are volatile so deadline/socket-close workers never wait for a write. */
internal class ProductSendGate {
    internal class Ticket internal constructor(val request: String, val session: String, val generation: Long) {
        @Volatile internal var cancelled = false
        internal var written = false // monitor only
    }
    private val monitor = Any()
    @Volatile private var generation = 0L
    @Volatile private var ready = false
    @Volatile private var closed = false
    private val released = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
    private val tickets = mutableMapOf<String, Ticket>()
    fun invalidateConfiguration(): Long = synchronized(monitor) {
        check(!closed)
        ready = false; generation = Math.addExact(generation, 1)
        tickets.values.forEach { it.cancelled = true }
        generation
    }
    fun activateConfiguration(expected: Long) = synchronized(monitor) {
        check(!closed && generation == expected)
        ready = true
    }
    fun register(request: String, session: String): Ticket = synchronized(monitor) {
        check(!closed && ready && session !in released && request !in tickets)
        Ticket(request, session, generation).also { tickets[request] = it }
    }
    fun advisoryAllowed(ticket: Ticket): Boolean = !closed && ready && !ticket.cancelled &&
        ticket.generation == generation && ticket.session !in released
    fun authorizeWrite(ticket: Ticket, write: () -> Unit): Boolean = synchronized(monitor) {
        if (!advisoryAllowed(ticket) || tickets[ticket.request] !== ticket || ticket.written) return@synchronized false
        ticket.written = true
        write() // includes actual OutputStream.write AND flush, no FFI
        true
    }
    fun cancel(request: String) = synchronized(monitor) { tickets[request]?.cancelled = true }
    fun releaseSession(session: String) = synchronized(monitor) {
        released.add(session)
        tickets.values.filter { it.session == session }.forEach { it.cancelled = true }
    }
    fun invalidateSessionScope(session: String) = synchronized(monitor) {
        tickets.values.filter { it.session == session }.forEach { it.cancelled = true }
    }
    fun finish(ticket: Ticket) = synchronized(monitor) { if (tickets[ticket.request] === ticket) tickets.remove(ticket.request) }
    fun close() = synchronized(monitor) {
        closed = true; ready = false
        tickets.values.forEach { it.cancelled = true }
    }
}

/** Control-queue scope identity. Switching away and back never restores an old
 * generation. Project selection itself grants no disclosure or write right. */
internal class ProductScopeRegistry {
    data class Scope(val project: String?, val generation: Long)
    private val current = mutableMapOf<String, Scope>()
    fun get(session: String): Scope? = current[session]
    fun update(session: String, project: String?): Scope {
        val old = current[session]
        if (old != null && old.project == project) return old
        return Scope(project, Math.addExact(old?.generation ?: 0L, 1L)).also { current[session] = it }
    }
    fun matches(session: String, project: String?, generation: Long): Boolean = current[session]?.let { it.project == project && it.generation == generation } == true
    fun release(session: String) { current.remove(session) }
}

/** Any surviving request owner is authoritative, including a settled tool call
 * that no longer has an active network task or unconfirmed HTTP plan. */
internal fun productRequestOwnedBy(session: String, vararg owners: String?): Boolean = owners.all { it == null || it == session }
