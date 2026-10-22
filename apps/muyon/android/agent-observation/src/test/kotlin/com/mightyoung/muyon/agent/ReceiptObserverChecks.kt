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
    var connectReply: UiAgentWireReply = UiAgentWireReply.Connected(meta, client, UiAgentServicePhase.CLOSED)
    var failRead = false
    var failRelease = false
    var failDisconnect = false
    var reply: UiAgentWireReply = UiAgentWireReply.Snapshot(original)
    override fun connect(): UiAgentWireReply { events += "connect"; return connectReply }
    override fun current(client: UiAgentClientRef): UiAgentWireReply { events += "current"; check(client == com.mightyoung.muyon.agent.client); if (failRead) error("transport unavailable"); return reply }
    override fun lookup(client: UiAgentClientRef, requestId: String): UiAgentWireReply { events += "lookup:$requestId"; return reply }
    override fun disconnect() { events += "disconnect"; if (failDisconnect) error("unbind unavailable") }
    override fun release(client: UiAgentClientRef, generation: Long) { events += "release"; check(generation > 0); if (failRelease) error("release unavailable") }
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
    check(port.events.last() == "disconnect")
    val lost = Port()
    val retained = ReceiptObserver(BUILD, enabled = true)
    check(retained.reconcile(lost) == ReceiptObservation.APPLIED)
    lost.failRead = true
    check(retained.reconcile(lost) == ReceiptObservation.UNKNOWN)
    check(retained.observationUnknown && retained.snapshot == original)
    retained.disconnect(lost)
    check(lost.events.last() == "disconnect") { "Lost reply must not leak the port liveness identity" }
    val badConnect = Port().apply { connectReply = UiAgentWireReply.Connected(meta, client.copy(epoch = "f".repeat(32)), UiAgentServicePhase.CLOSED) }
    val rejected = ReceiptObserver(BUILD, enabled = true)
    check(rejected.reconcile(badConnect) == ReceiptObservation.REJECTED)
    check(rejected.snapshot == null)
    rejected.disconnect(badConnect)
    check(badConnect.events == listOf("connect", "disconnect"))
    val owned = Port()
    val onePort = ReceiptObserver(BUILD, enabled = true)
    check(onePort.reconcile(owned) == ReceiptObservation.APPLIED)
    val stranger = Port()
    check(onePort.reconcile(stranger) == ReceiptObservation.REJECTED)
    onePort.disconnect(stranger)
    check(stranger.events.isEmpty())
    onePort.disconnect(owned)
    for (rejectedSnapshot in listOf(
        original.copy(meta = meta.copy(revision = 4)),
        original.copy(meta = meta.copy(serviceEpoch = "f".repeat(32))),
        original.copy(run = UiAgentRun.Unresolved(intent, null, UiAgentReceipt(null, UiAgentReceiptOutcome.UNKNOWN)))
    )) {
        val conflictPort = Port()
        val conflict = ReceiptObserver(BUILD, enabled = true)
        check(conflict.reconcile(conflictPort) == ReceiptObservation.APPLIED)
        conflictPort.reply = UiAgentWireReply.Snapshot(rejectedSnapshot)
        check(conflict.reconcile(conflictPort) == ReceiptObservation.REJECTED)
        check(conflict.observationUnknown) { "REJECTED_SNAPSHOT_RED: failed current observation must remain uncertain" }
        check(conflict.snapshot == original)
        conflict.disconnect(conflictPort)
    }
    for (duringRelease in listOf(true, false)) {
        val failing = Port()
        val closing = ReceiptObserver(BUILD, enabled = true)
        check(closing.reconcile(failing) == ReceiptObservation.APPLIED)
        if (duringRelease) failing.failRelease = true else failing.failDisconnect = true
        closing.disconnect(failing)
        check(closing.observationUnknown) { "FAILED_RELEASE_RED: failed lifecycle delivery must remain uncertain" }
        check(closing.snapshot == original)
        check(failing.events.takeLast(2) == listOf("release", "disconnect"))
        if (!duringRelease) {
            val replacement = Port()
            check(closing.reconcile(replacement) == ReceiptObservation.REJECTED) { "UNBIND_OWNER_RED: failed unbind must retain cleanup ownership" }
            check(replacement.events.isEmpty())
            failing.failDisconnect = false
            closing.disconnect(failing)
            check(failing.events.takeLast(2) == listOf("disconnect", "disconnect"))
            check(closing.reconcile(replacement) == ReceiptObservation.APPLIED)
            closing.disconnect(replacement)
        }
    }
    println("RECEIPT_OBSERVER_CHECKS_PASS")
}
