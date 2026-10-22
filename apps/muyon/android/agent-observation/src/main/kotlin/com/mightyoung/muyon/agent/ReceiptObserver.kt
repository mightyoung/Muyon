package com.mightyoung.muyon.agent

import com.mightyoung.muyon.androidlab.*

/** Private transport boundary for original run/receipt summaries; no execution operation. */
interface ReceiptObservationPort {
    fun connect(): UiAgentWireReply
    fun current(client: UiAgentClientRef): UiAgentWireReply
    fun lookup(client: UiAgentClientRef, requestId: String): UiAgentWireReply
    fun release(client: UiAgentClientRef, generation: Long)
    /** Retire/unbind the port-owned liveness identity even when a reply lost the lease. */
    fun disconnect()
}

enum class ReceiptObservation { DISABLED, APPLIED, UNKNOWN, REJECTED }

/**
 * Optional production-host consumer of the existing private Service summary ABI.
 * All methods must be serialized on one caller-owned background worker: ports may block.
 * Android binding and UI delivery are intentionally outside this dependency slice.
 * This consumer never makes a lease visible or submits work, including after reconnect.
 */
class ReceiptObserver(private val expectedBuild: String, private val enabled: Boolean = false) {
    private val state = AgentServiceClientState(expectedBuild)
    private var connection: UiAgentConnectionTicket? = null
    private var activePort: ReceiptObservationPort? = null
    val snapshot get() = state.snapshot
    val historical get() = state.historical
    val observationUnknown get() = state.observationUnknown

    fun reconcile(port: ReceiptObservationPort): ReceiptObservation {
        if (!enabled) return ReceiptObservation.DISABLED
        if (activePort != null && activePort !== port) return ReceiptObservation.REJECTED
        if (state.client == null) {
            val ticket = state.beginBinding()
            connection = ticket
            activePort = port
            val reply = receive { port.connect() }
            if (reply !is UiAgentWireReply.Connected || reply.client.epoch != reply.meta.serviceEpoch ||
                state.connected(ticket, reply.meta, reply.client.lease, reply.phase) != UiAgentApply.APPLIED) {
                lost()
                return if (rejected(reply)) ReceiptObservation.REJECTED else ReceiptObservation.UNKNOWN
            }
        }
        val ticket = state.capture() ?: return ReceiptObservation.UNKNOWN
        return apply(ticket, receive { port.current(ticket.client) })
    }

    fun lookupOriginal(port: ReceiptObservationPort, intent: UiAgentIntent): ReceiptObservation {
        if (!enabled) return ReceiptObservation.DISABLED
        if (activePort !== port) return ReceiptObservation.REJECTED
        val ticket = state.captureLookup(intent) ?: return ReceiptObservation.REJECTED
        return apply(ticket, receive { port.lookup(ticket.client, intent.requestId) })
    }

    /** Release only this consumer's current lease. A failed reply leaves observation uncertain. */
    fun disconnect(port: ReceiptObservationPort) {
        if (!enabled || activePort !== port) return
        val ticket = connection
        val release = state.release()
        activePort = null
        connection = null
        var failed = false
        try {
            if (release != null) port.release(release.client, release.generation)
        } catch (_: Exception) {
            failed = true
        } finally {
            try { port.disconnect() } catch (_: Exception) {
                failed = true
                // Keep the original owner until explicit cleanup succeeds; no port replacement.
                activePort = port
                connection = ticket
            }
        }
        if (failed) ticket?.let(state::transportLost)
    }

    private fun receive(read: () -> UiAgentWireReply): UiAgentWireReply? = try {
        // Reuse exact existing field/identity/size validation even for a typed transport port.
        val reply = read()
        if (AgentServiceWire.encode(reply, expectedBuild) != null) reply
        else UiAgentWireReply.Local(UiAgentLocalStatus.INVALID_REQUEST)
    } catch (_: Exception) { null }

    private fun apply(ticket: UiAgentObservationTicket, reply: UiAgentWireReply?): ReceiptObservation {
        if (reply is UiAgentWireReply.Snapshot) {
            return if (state.apply(ticket, reply.value) == UiAgentApply.APPLIED) ReceiptObservation.APPLIED
            else { lost(); ReceiptObservation.REJECTED }
        }
        lost()
        return if (rejected(reply)) ReceiptObservation.REJECTED else ReceiptObservation.UNKNOWN
    }

    private fun rejected(reply: UiAgentWireReply?) = reply is UiAgentWireReply.Rejected ||
        reply == UiAgentWireReply.Local(UiAgentLocalStatus.INVALID_REQUEST)

    private fun lost() {
        connection?.let(state::transportLost)
        // Keep the port owner until explicit disconnect: an uncertain connect may have a lease.
        // Reconcile with the same port may establish/read it again; never swap Binder identity.
    }
}
