package com.mightyoung.muyon.product.chat.components

// Synthetic offline reproduction against c7c0d4729d034eb3d644e8945a56ca7dba467ff4.
fun main() {
    val scope = ComponentScope("workspace", "conversation", "project", "agent", 7)
    val component = ComponentDecoder.decode(mapOf<String, Any?>(
        "schema_version" to 1, "component_id" to "card", "message_id" to "message",
        "kind" to "native_choices", "revision" to 3, "text" to "Choose",
        "actions" to listOf(
            mapOf("action_id" to "choose", "type" to "local_edit", "label" to "Choose", "field" to "answer"),
            mapOf("action_id" to "save", "type" to "submit_local", "label" to "Save")
        )
    ), scope)
    val ledger = ComponentLedger(component, "attempt-A")
    ledger.edit(scope, 3, 0, "choose", "A")
    val originalA = ledger.submit(scope, 3, ledger.snapshot().stateRevision, "save", "intent-A").submission
    // This callback captures A's scope while A is pending. The old API cannot capture identity/CAS.
    val lateCancelForA = { ledger.requestCancel(scope) }
    ledger.observe(scope, OriginalReceipt(1, originalA.identity, ReceiptStatus.COMMITTED,
        "receipt-A", true, "2026-10-22T00:00:00Z", 2620, null))
    ledger.redo(scope, "attempt-B")
    ledger.edit(scope, 3, ledger.snapshot().stateRevision, "choose", "B")
    val pendingB = ledger.submit(scope, 3, ledger.snapshot().stateRevision, "save", "intent-B").submission
    val before = ledger.snapshot()
    lateCancelForA()
    val after = ledger.snapshot()
    println("legacy_source=c7c0d4729d034eb3d644e8945a56ca7dba467ff4; offline synthetic only")
    println("captured_cancel_intent=${originalA.identity.intentId}; current_pending=${pendingB.identity.intentId}")
    println("before_phase=${before.pending?.phase}; after_phase=${after.pending?.phase}")
    println("before_revision=${before.stateRevision}; after_revision=${after.stateRevision}; same_identity=${before.pending?.identity == after.pending?.identity}")
    check(after == before) { "Late cancel for attempt A changed pending attempt B" }
}
