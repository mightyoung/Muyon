package com.mightyoung.muyon.agent

import com.mightyoung.muyon.androidlab.*

private const val BUILD = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
private val meta = UiAgentMeta(1u, BUILD, "b".repeat(32), 5)
private val client = UiAgentClientRef(meta.serviceEpoch, "c".repeat(32))
private val intent = UiAgentIntent("original_read", UiAgentVariant.EQUIPMENT, BUILD)
private val original = UiAgentSnapshot(meta, UiAgentServicePhase.CLOSED, UiAgentRun.Terminal(UiAgentSummary(
    intent, UiAgentRunIdentity("d".repeat(32), "e".repeat(32), UiAgentTask("task1", "attempt1")),
    UiAgentTerminal.COMPLETED, UiAgentReason.NONE, UiAgentReceipt("receipt1", UiAgentReceiptOutcome.RECORDED_SUCCESS))))

// A transport fixture is necessary here: no Android/FFI runtime is claimed by these checks.
// The regression oracle is the real shared state and retained original receipt, not call counts alone.
private class Port : ReceiptObservationPort {
    val events = mutableListOf<String>()
    var reply: UiAgentWireReply = UiAgentWireReply.Snapshot(original)
    override fun connect(): UiAgentWireReply { events += "connect"; return UiAgentWireReply.Connected(meta, client, UiAgentServicePhase.CLOSED) }
    override fun current(client: UiAgentClientRef): UiAgentWireReply { events += "current"; check(client == com.mightyoung.muyon.agent.client); return reply }
    override fun lookup(client: UiAgentClientRef, requestId: String): UiAgentWireReply { events += "lookup:$requestId"; return reply }
    override fun release(client: UiAgentClientRef, generation: Long) { events += "release"; check(generation > 0) }
}
fun main() {
    val disabledPort = Port()
    val disabled = ReceiptObserver(BUILD)
    check(disabled.reconcile(disabledPort) == ReceiptObservation.DISABLED)
    check(disabledPort.events.isEmpty())
    val port = Port()
    val observer = ReceiptObserver(BUILD, enabled = true)
    check(observer.reconcile(port) == ReceiptObservation.APPLIED) { "PRODUCTION_RECEIPT_RED: explicit reconciliation must apply the original native receipt" }
    check(observer.snapshot == original)
    check(port.events == listOf("connect", "current"))
    check(observer.lookupOriginal(port, intent) == ReceiptObservation.APPLIED)
    check(observer.historical == original)
    port.reply = UiAgentWireReply.Unresolved(meta)
    check(observer.reconcile(port) == ReceiptObservation.UNKNOWN)
    check(observer.snapshot == original) { "Unresolved cannot erase a known receipt or prove not started" }
    port.reply = UiAgentWireReply.Snapshot(original.copy(meta = meta.copy(buildIdentity = "f".repeat(40))))
    check(observer.reconcile(port) == ReceiptObservation.REJECTED)
    check(observer.snapshot == original)
    port.reply = UiAgentWireReply.Snapshot(original)
    check(observer.reconcile(port) == ReceiptObservation.APPLIED)
    check(observer.snapshot == original)
    check(observer.lookupOriginal(port, intent.copy(requestId = "wrong")) == ReceiptObservation.REJECTED)
    check(observer.historical == original)
    observer.disconnect(port)
    check(observer.snapshot == original)
    check(port.events.last() == "release")
    println("RECEIPT_OBSERVER_CHECKS_PASS")
}
