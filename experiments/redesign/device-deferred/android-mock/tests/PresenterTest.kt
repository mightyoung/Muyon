package muyon.rd.p04

private fun expect(value: Boolean, message: String) { check(value) { message } }
fun main() {
    var passed = 0; var failed = 0
    fun test(name: String, body: () -> Unit) {
        try { body(); println("PASS $name"); passed++ }
        catch (e: Throwable) { println("FAIL $name: ${e.message}"); failed++ }
    }
    fun fixture(): Pair<SupplierPresenter, MockRustCorePort> {
        val port = MockRustCorePort()
        val presenter = SupplierPresenter(port)
        port.emitSnapshot(Snapshot(Domain("store", "scope", "stream"), 4, listOf(Supplier("a", "Saved", "r4"), Supplier("b", "Saved", "r1"))), 0)
        presenter.select("a"); presenter.edit()
        return presenter to port
    }
    test("initial loading and snapshot detail") { val (p, _) = fixture(); expect(p.state.page == Page.EDIT, "expected edit"); expect(p.state.saved?.id == "a", "identity lost") }
    test("raw UTF16 is not trimmed or normalized") { val (p,m)=fixture(); val raw=" \u000b e\u0301 \uD800"; p.change(raw); p.save(); expect(m.previews.single().raw == raw, "raw altered") }
    test("back preserves draft and stable intent") { val(p,_)=fixture(); p.change(" Mine "); val i=p.state.draft!!.intent; p.back(); p.select("a"); p.edit(); expect(p.state.draft?.raw==" Mine " && p.state.draft?.intent==i,"draft/intent lost") }
    test("same names retain supplier identity") {val(p,m)=fixture(); p.change("Changed"); p.save(); expect(m.previews.single().supplierId=="a","wrong object")}
    test("double tap submits once per intent") {val(p,m)=fixture(); p.save(); p.save(); expect(m.commits.size==1,"duplicate submission")}
    test("no effect receipt never shows saved") {val(p,_)=fixture(); p.save(); expect(p.state.status==Status.SUBMITTING,"submission fabricated success")}
    test("unknown preserves draft and never retries automatically") {val(p,m)=fixture(); p.change("Mine"); p.save(); m.emitOutcome(Outcome.Unknown(m.commits.single())); p.save(); expect(p.state.status==Status.UNKNOWN && m.commits.size==1 && p.state.draft?.raw=="Mine","unknown retried/lost draft")}
    test("conflict preserves draft and saved version") {val(p,m)=fixture(); p.change("Mine"); p.save(); m.emitOutcome(Outcome.Conflict(m.commits.single(),Supplier("a","Other","r5"))); expect(p.state.status==Status.CONFLICT && p.state.saved?.name=="Other" && p.state.draft?.raw=="Mine","conflict overwrote draft")}
    test("old snapshot watermark cannot overwrite") {val(p,m)=fixture(); m.emitSnapshot(Snapshot(Domain("store","scope","stream"),3,listOf(Supplier("a","Old","r0"))),p.state.generation); expect(p.state.saved?.name=="Saved","old watermark applied")}
    test("cross domain snapshot cannot overwrite") {val(p,m)=fixture(); m.emitSnapshot(Snapshot(Domain("evil","scope","stream"),999,listOf(Supplier("a","Wrong","r9"))),p.state.generation); expect(p.state.saved?.name=="Saved","domain mixed")}
    test("old generation display is rejected") {val(p,m)=fixture(); val old=p.state.generation; p.back(); m.emitSnapshot(Snapshot(Domain("store","scope","stream"),5,listOf(Supplier("a","Stale","r5"))),old); p.select("a"); expect(p.state.saved?.name=="Saved","stale display applied")}
    test("late receipt retained by original identity without stale display") {val(p,m)=fixture(); p.save(); val c=m.commits.single(); p.back(); p.select("b"); m.emitOutcome(Outcome.Effect(c,"receipt-a",Supplier("a","Updated","r5"))); expect(p.receipts[c.intent]?.supplier?.id=="a","receipt lost"); expect(p.state.saved?.id=="b" && p.state.status!=Status.SAVED,"stale effect changed view")}
    test("matching authoritative mock effect enables saved") {val(p,m)=fixture(); p.save(); val c=m.commits.single(); m.emitOutcome(Outcome.Effect(c,"receipt-a",Supplier("a","Updated","r5"))); expect(p.state.status==Status.SAVED && p.state.saved?.name=="Updated","effect not shown")}
    test("unregistered intent receipt rejected") {val(p,m)=fixture(); m.emitOutcome(Outcome.Effect(Command("foreign","a","plan",Domain("store","scope","stream"),0),"fake",Supplier("a","Fake","r5"))); expect(p.receipts.isEmpty() && p.state.status!=Status.SAVED,"foreign receipt trusted")}
    test("mismatched supplier receipt rejected") {val(p,m)=fixture(); p.save(); m.emitOutcome(Outcome.Effect(m.commits.single(),"bad",Supplier("b","Fake","r5"))); expect(p.receipts.isEmpty() && p.state.saved?.id=="a","wrong identity receipt")}
    test("FullAllow high risk does not ask extra question") {val(p,m)=fixture(); m.decision=Decision.ALLOW; p.save(); expect(m.commits.size==1 && p.state.status==Status.SUBMITTING,"allow gated")}
    test("trusted hard deny blocks even FullAllow") {val(p,m)=fixture(); m.decision=Decision.HARD_DENY; p.save(); expect(m.commits.isEmpty() && p.state.status==Status.DENIED,"hard deny bypassed")}
    test("Auto confirmation projects separate state") {val(p,m)=fixture(); m.decision=Decision.CONFIRM; p.save(); expect(m.commits.isEmpty() && p.state.status==Status.CONFIRM,"confirmation skipped")}
    test("confirmed Auto plan submits once") {val(p,m)=fixture(); m.decision=Decision.CONFIRM; p.save(); p.confirm(); p.confirm(); expect(m.commits.size==1,"confirmation duplicated")}
    test("effect cannot be downgraded by late unknown") {val(p,m)=fixture(); p.save(); val c=m.commits.single(); m.emitOutcome(Outcome.Effect(c,"receipt",Supplier("a","Updated","r5"))); m.emitOutcome(Outcome.Unknown(c)); expect(p.state.status==Status.SAVED,"late timeout downgraded effect")}
    test("new edit after saved requires fresh intent and revision") {val(p,m)=fixture(); p.save(); val c=m.commits.single(); m.emitOutcome(Outcome.Effect(c,"receipt",Supplier("a","Updated","r5"))); p.edit(); p.change("Next"); p.save(); expect(m.commits.size==2 && m.commits.last().intent!=c.intent && m.previews.last().expectedRevision=="r5","fresh intent missing")}
    test("returning to unknown intent still displays unknown") {val(p,m)=fixture(); p.save(); m.emitOutcome(Outcome.Unknown(m.commits.single())); p.back(); p.select("a"); p.edit(); expect(p.state.status==Status.UNKNOWN,"unknown hidden by navigation")}
    test("blank receipt cannot mark saved") {val(p,m)=fixture(); p.save(); m.emitOutcome(Outcome.Effect(m.commits.single(),"",Supplier("a","Fake","r5"))); expect(p.state.status==Status.SUBMITTING && p.receipts.isEmpty(),"empty receipt trusted")}
    println("RESULT $passed passed / $failed failed")
    check(failed==0) { "$failed failed assertions" }
}
