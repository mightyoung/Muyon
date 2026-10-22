package com.mightyoung.muyon.agent
import com.mightyoung.muyon.androidlab.*

interface ReceiptObservationPort {
    fun connect(): UiAgentWireReply
    fun current(client: UiAgentClientRef): UiAgentWireReply
    fun lookup(client: UiAgentClientRef, requestId: String): UiAgentWireReply
    fun release(client: UiAgentClientRef, generation: Long)
}
enum class ReceiptObservation { DISABLED, APPLIED, UNKNOWN, REJECTED }
class ReceiptObserver(expectedBuild: String, private val enabled: Boolean = false) {
    private val state = AgentServiceClientState(expectedBuild)
    val snapshot get() = state.snapshot
    val historical get() = state.historical
    fun reconcile(port: ReceiptObservationPort): ReceiptObservation = if (enabled) ReceiptObservation.UNKNOWN else ReceiptObservation.DISABLED
    fun lookupOriginal(port: ReceiptObservationPort, intent: UiAgentIntent): ReceiptObservation = ReceiptObservation.UNKNOWN
    fun disconnect(port: ReceiptObservationPort) {}
}
