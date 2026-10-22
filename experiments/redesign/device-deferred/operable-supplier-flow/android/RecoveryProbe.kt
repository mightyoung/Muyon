package muyon.rd.p08.android

private val row = SupplierRow("S1", "synthetic", "1")
private fun e(status: String, reason: String? = null) = EditorProjection("intent-A", "S1", "raw", status, "1", if(status == "prepared") PreviewProjection("raw", "2") else null, row, null, reason)
private fun p(session: String, editor: EditorProjection?) = HostProjection(listOf(row), row, editor, "synthetic; M03 blocked_contract", session, "nonce", "available", listOf(RecoverableSession("A", "S1", "prepared"), RecoverableSession("B", "S1", "editing")))
private class Port: SupplierActionPort {
    var callback: ((PortReply) -> Unit)? = null
    val actions = mutableListOf<HostAction>()
    override fun action(action: HostAction, reply: (PortReply) -> Unit) { actions += action; callback = reply }
    override fun refresh(reply: (PortReply) -> Unit) { callback = reply }
    override fun restoreOriginalSession(session: String, reply: (PortReply) -> Unit) { callback = reply }
    fun success(projection: HostProjection) { callback!!(PortReply.Projected(projection)) }
    fun lost() { callback!!(PortReply.Unavailable) }
}
fun main() {
    var failures = 0
    fun probe(name: String, run: () -> Unit) { try { run(); println("PASS $name") } catch (x: Throwable) { failures++; println("FAIL $name: ${x.message}") } }
    probe("known pre-dispatch preview outage has a usable retry or discard") {
        val port = Port(); val model = SupplierScreenModel(p("A", e("editing")), port)
        model.preview(); port.success(p("A", e("unavailable", "preview_unavailable")))
        println("preview outage: changeRaw=${model.canChangeRaw}, preview=${model.canPreview}, cancel=${model.canCancel}, lookup=${model.canLookup}")
        check(model.canCancel || model.canPreview || model.canChangeRaw) { "only lookup enabled, but fixed host requires e.dispatched for lookup; refresh retains unavailable" }
    }
    probe("uncertain save in A does not lock an independently restored pre-dispatch B") {
        val port = Port(); val model = SupplierScreenModel(p("A", e("prepared")), port)
        model.save(); port.lost(); check(model.canLookup && !model.canSave)
        model.restoreOriginalSession("B"); port.success(p("B", e("editing").copy(intent="intent-B")))
        println("restored B: session=${model.projection.session}, status=${model.projection.editor?.status}, changeRaw=${model.canChangeRaw}, cancel=${model.canCancel}, lookup=${model.canLookup}")
        check(model.canChangeRaw && model.canCancel && !model.canLookup) { "A uncertainty leaked into B; lookup targets B rather than A" }
    }
    probe("visiting resolved B does not unlock uncertain A save replay") {
        val port = Port(); val model = SupplierScreenModel(p("A", e("prepared")), port)
        model.save(); port.lost()
        model.restoreOriginalSession("B"); port.success(p("B", e("rejected", "Required").copy(intent="intent-B")))
        model.restoreOriginalSession("A"); port.success(p("A", e("prepared")))
        println("returned A: save=${model.canSave}, lookup=${model.canLookup}")
        check(!model.canSave && model.canLookup) { "B result cleared A uncertainty; same stale prepared projection is now saveable" }
    }
    println("Independent probes: ${3 - failures}/3 passed")
    check(failures == 0) { "$failures independent recovery failures" }
}
