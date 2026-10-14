package muyon.rd.p08.android

// These synthetic projections exercise the presentation seam, never Rust/SQLite semantics.
private val s1 = SupplierRow("S1", "同名合成供应商", "1")
private val s2 = SupplierRow("S2", s1.name, "18446744073709551615")
private fun projection(editor: EditorProjection? = null, selected: SupplierRow? = s1) = HostProjection(
    suppliers = listOf(s1, s2), selected = selected, editor = editor,
    capability = "合成实验可信本机能力；正式授权未接线；M03 blocked_contract",
    session = "original-session", csrf = "transport-owned", list_status = "available",
    recoverable_sessions = listOf(RecoverableSession("original-session", editor?.supplier, editor?.status))
)
private fun editor(status: String = "editing", raw: String = " 新名称 ") = EditorProjection(
    intent = "original-intent", supplier = "S1", raw = raw, status = status,
    expected_revision = "1", preview = if (status == "prepared") PreviewProjection("新名称", "2") else null,
    current = s1, receipt = null, reason = null
)
private class RecordingPort : SupplierActionPort {
    data class Call(val action: HostAction?, val restore: String?, val refresh: Boolean, val reply: (PortReply) -> Unit)
    val calls = mutableListOf<Call>()
    override fun action(action: HostAction, reply: (PortReply) -> Unit) { calls += Call(action, null, false, reply) }
    override fun refresh(reply: (PortReply) -> Unit) { calls += Call(null, null, true, reply) }
    override fun restoreOriginalSession(session: String, reply: (PortReply) -> Unit) { calls += Call(null, session, false, reply) }
    fun succeed(state: HostProjection) { calls.last().reply(PortReply.Projected(state)) }
}
private fun expect(condition: Boolean, reason: String) { check(condition) { reason } }
private val tests = linkedMapOf<String, () -> Unit>(
    "input is locked during save and preview callbacks" to {
        val port = RecordingPort(); val m = SupplierScreenModel(projection(editor("prepared")), port)
        m.save(); m.changeRaw("new input during save")
        expect(!m.canChangeRaw && m.buffer == " 新名称 ", "in-flight business command must lock its raw input")
        val previewPort = RecordingPort(); val previewModel = SupplierScreenModel(projection(editor()), previewPort)
        previewModel.preview(); previewModel.changeRaw("new input during preview")
        expect(!previewModel.canChangeRaw && previewModel.buffer == " 新名称 ", "preview input remains bound while callback pending")
    },
    "saved without receipt cannot discard original operation" to {
        val port = RecordingPort(); val m = SupplierScreenModel(projection(editor("saved")), port)
        expect(!m.canCancel && m.canLookup, "unverified saved label cannot permit replacement")
        m.requestCancel(); m.confirmDiscard(); expect(port.calls.isEmpty(), "no cancel without original outcome")
    },
    "wrong session response after save stays unknown" to {
        val port = RecordingPort(); val m = SupplierScreenModel(projection(editor("prepared")), port)
        m.save(); port.succeed(projection(editor("saved")).copy(session = "unrelated-session"))
        expect(m.projection.session == "original-session" && m.canLookup && !m.saved, "foreign-session response cannot establish success")
    },
    "non-CAS conflict cannot discard original binding" to {
        val port = RecordingPort(); val m = SupplierScreenModel(projection(editor("conflict").copy(reason = "Binding")), port)
        expect(!m.canCancel, "only confirmed CAS rejection permits explicit fresh edit")
        m.requestCancel(); m.confirmDiscard(); expect(port.calls.isEmpty(), "binding conflict cannot hide original intent")
    },
    "read refresh can synchronize retained unsent draft" to {
        val port = RecordingPort(); val m = SupplierScreenModel(projection(editor()), port)
        m.changeRaw(" keep exact "); port.calls.last().reply(PortReply.Unavailable)
        m.refresh(); port.succeed(projection(editor()))
        expect(port.calls.last().action == HostAction.Draft(" keep exact "), "known pre-dispatch editor should resync retained local raw")
    },
    "selection preserves raw not yet acknowledged by host" to {
        val port = RecordingPort(); val m = SupplierScreenModel(projection(editor()), port)
        m.changeRaw(" locally retained "); port.calls.last().reply(PortReply.Unavailable)
        m.select("S2"); port.succeed(projection(editor(), s2))
        expect(m.buffer == " locally retained " && m.projection.editor?.supplier == "S1", "selection must not drop unsynchronized original draft")
    },
    "session navigation cannot discard unsynchronized local draft" to {
        val port = RecordingPort(); val m = SupplierScreenModel(projection(editor()).copy(recoverable_sessions = listOf(RecoverableSession("other-original", "S2", "unknown"))), port)
        m.changeRaw(" locally retained "); port.calls.last().reply(PortReply.Unavailable)
        m.restoreOriginalSession("other-original")
        expect(port.calls.size == 1 && m.buffer == " locally retained " && !m.canRestoreSession, "sync or explicitly discard local buffer before changing session")
    },
    "missing current read stays unavailable despite historical receipt" to {
        val binding = OriginalBinding("domain", "scope", "S1", "original-intent", "supplier.name", listOf(65), "1", "plan", "candidate")
        val receipt = OriginalReceipt("original-intent", binding, "digest", "domain", "S1", "old", "A", "1", "2")
        val m = SupplierScreenModel(projection(editor("saved").copy(receipt = receipt, current = null)), RecordingPort())
        expect(m.saved && m.currentRow == null, "historical success does not fill unavailable current row")
    },
    "stable supplier ID and decimal revision stay exact" to {
        val port = RecordingPort(); val m = SupplierScreenModel(projection(), port)
        expect(m.projection.suppliers[1].revision == "18446744073709551615", "revision must remain decimal text")
        m.select("S2"); expect(port.calls.single().action == HostAction.Select("S2"), "selection must send stable ID")
        expect(m.page == ScreenPage.LIST, "navigation must wait for host selection")
        port.succeed(projection(selected = s2)); expect(m.page == ScreenPage.DETAIL, "selected detail must open")
    },
    "selecting preserves unresolved original editor" to {
        val port = RecordingPort(); val m = SupplierScreenModel(projection(editor("unknown")), port)
        m.select("S2"); port.succeed(projection(editor("unknown"), s2))
        expect(m.projection.editor?.supplier == "S1", "host editor identity must remain separate")
        m.openOriginalEditor(); expect(m.page == ScreenPage.EDITOR, "original unknown editor must stay reachable")
        expect(!m.canEdit, "selected S2 must not start an implicit replacement intent")
    },
    "explicit edit has no renderer intent or binding" to {
        val port = RecordingPort(); val m = SupplierScreenModel(projection(), port)
        m.edit(); expect(port.calls.single().action == HostAction.Edit, "host creates intent")
        port.succeed(projection(editor())); expect(m.page == ScreenPage.EDITOR, "full editor route")
        expect(m.projection.editor?.intent == "original-intent", "intent comes from host")
    },
    "raw whitespace combining mark control and lone surrogate unchanged" to {
        val port = RecordingPort(); val m = SupplierScreenModel(projection(editor()), port)
        val raw = " \t e\u0301\u000b\uD800 \n"
        m.changeRaw(raw); expect(m.buffer == raw, "local buffer must be exact")
        expect(port.calls.single().action == HostAction.Draft(raw), "raw callback must be exact UTF16")
    },
    "rapid draft updates serialize without dropping latest input" to {
        val port = RecordingPort(); val m = SupplierScreenModel(projection(editor()), port)
        m.changeRaw(" first "); m.changeRaw(" second ")
        expect(port.calls.size == 1 && m.buffer == " second ", "latest raw must survive in-flight draft")
        port.succeed(projection(editor(raw = " first ")))
        expect(port.calls.size == 2 && port.calls.last().action == HostAction.Draft(" second "), "latest raw must sync next")
        port.succeed(projection(editor(raw = " second ")))
        expect(!m.busy && m.canPreview, "preview available only once exact draft synchronized")
    },
    "editing prepared input disables save until host invalidates preview" to {
        val port = RecordingPort(); val m = SupplierScreenModel(projection(editor("prepared")), port)
        expect(m.canSave, "host prepared projection enables save")
        m.changeRaw(" changed "); m.save()
        expect(!m.canSave && port.calls.single().action == HostAction.Draft(" changed "), "stale prepared binding must not save")
        port.succeed(projection(editor(raw = " changed ")))
        expect(!m.canSave && m.projection.editor?.preview == null, "host cleared preparation")
    },
    "preview and save are narrow host callbacks and double clicks suppressed" to {
        val port = RecordingPort(); val m = SupplierScreenModel(projection(editor()), port)
        m.preview(); m.preview(); expect(port.calls.single().action == HostAction.Preview, "one pending preview callback")
        port.succeed(projection(editor("prepared"))); m.save(); m.save()
        expect(port.calls.size == 2 && port.calls.last().action == HostAction.Save, "one pending save callback")
        expect(!m.saved && m.projection.editor?.status == "prepared", "save click is not saved authority")
    },
    "conflict preserves original expected revision and raw with current row" to {
        val port = RecordingPort(); val original = editor("conflict", " my draft ").copy(current = s1.copy(name = "other window", revision = "2"), reason = "Revision")
        val m = SupplierScreenModel(projection(original), port)
        expect(m.buffer == " my draft " && m.projection.editor?.expected_revision == "1", "conflict must not silently rebase")
        expect(m.currentRow?.revision == "2" && m.currentRow?.name == "other window", "current row displayed separately")
        m.save(); m.edit(); expect(port.calls.isEmpty(), "conflict requires explicit cancel before fresh edit")
    },
    "original receipt stays separate from later current row" to {
        val binding = OriginalBinding("synthetic-domain", "scope", "S1", "original-intent", "supplier.name", listOf(32, 65, 32), "1", "host-plan", "host-candidate")
        val receipt = OriginalReceipt("original-intent", binding, "host-verified-digest", "synthetic-domain", "S1", s1.name, "A", "1", "2")
        val e = editor("saved").copy(receipt = receipt, current = s1.copy(name = "B", revision = "3"))
        val m = SupplierScreenModel(projection(e), RecordingPort())
        expect(m.saved && m.originalReceipt === receipt, "host original receipt must be retained verbatim as supplied")
        expect(m.originalReceipt?.new_revision == "2" && m.currentRow?.revision == "3", "receipt cannot overwrite current row")
    },
    "saved status without a receipt never displays saved" to {
        val m = SupplierScreenModel(projection(editor("saved")), RecordingPort())
        expect(!m.saved && m.statusText != "已保存", "no receipt cannot yield saved label")
    },
    "unknown exposes original lookup only with no new save or cancel" to {
        val port = RecordingPort(); val m = SupplierScreenModel(projection(editor("unknown")), port)
        m.save(); m.preview(); m.edit(); m.changeRaw("replacement"); m.confirmDiscard()
        expect(port.calls.isEmpty() && m.buffer == " 新名称 ", "unknown must stay immutable")
        m.lookup(); expect(port.calls.single().action == HostAction.Lookup, "lookup original session only")
        port.succeed(projection(editor("unknown"))); expect(!m.saved && m.canLookup, "missing receipt remains unknown")
    },
    "save transport loss blocks replacement and uses lookup" to {
        val port = RecordingPort(); val m = SupplierScreenModel(projection(editor("prepared")), port)
        m.save(); port.calls.last().reply(PortReply.Unavailable)
        expect(m.canLookup && !m.canSave && !m.canChangeRaw && !m.saved, "uncertain dispatch must be reconciled")
        m.save(); m.edit(); m.confirmDiscard(); m.lookup()
        expect(port.calls.map { it.action } == listOf(HostAction.Save, HostAction.Lookup), "never retry save on transport loss")
    },
    "cancel unsaved buffer requires explicit discard and host result" to {
        val port = RecordingPort(); val m = SupplierScreenModel(projection(editor()), port)
        m.openOriginalEditor(); m.back()
        expect(m.discardConfirmation && port.calls.isEmpty(), "back must disclose unsaved buffer")
        m.keepEditing(); expect(!m.discardConfirmation && m.page == ScreenPage.EDITOR, "keep draft")
        m.back(); m.confirmDiscard(); expect(port.calls.single().action == HostAction.Cancel, "explicit host cancellation")
        expect(m.buffer == " 新名称 ", "draft remains until host confirms")
        port.succeed(projection()); expect(m.page == ScreenPage.DETAIL && m.buffer.isEmpty(), "confirmed discard returns same selected detail")
    },
    "late duplicate callback cannot overwrite a newer projection" to {
        val port = RecordingPort(); val m = SupplierScreenModel(projection(editor()), port)
        m.preview(); val late = port.calls.last().reply
        port.succeed(projection(editor("prepared"))); m.save()
        late(PortReply.Projected(projection(editor("editing", "stale"))))
        expect(m.projection.editor?.status == "prepared" && m.busy, "closed callback must not mutate newer request")
    },
    "restore selects exact original session and does not send business action" to {
        val port = RecordingPort(); val m = SupplierScreenModel(projection().copy(recoverable_sessions = listOf(RecoverableSession("recovered-original", "S1", "unknown"))), port)
        m.restoreOriginalSession("recovered-original")
        expect(port.calls.single().restore == "recovered-original" && port.calls.single().action == null, "restore transport uses original session GET")
        port.succeed(projection(editor("unknown")).copy(session = "recovered-original"))
        expect(m.page == ScreenPage.EDITOR && m.canLookup && !m.canEdit, "restored unknown cannot mint intent")
    },
    "refresh preserves local unsynchronized raw on failure" to {
        val port = RecordingPort(); val m = SupplierScreenModel(projection(editor()), port)
        m.changeRaw(" unsent local "); port.calls.last().reply(PortReply.Unavailable)
        m.refresh(); expect(port.calls.last().refresh, "read-only refresh")
        port.calls.last().reply(PortReply.Unavailable)
        expect(m.buffer == " unsent local " && !m.canSave, "transport failure cannot lose local draft or fabricate save")
    }
)
fun main() {
    var failed = 0
    tests.forEach { (name, test) ->
        try { test(); println("PASS $name") } catch (e: Throwable) { failed++; println("FAIL $name: ${e.message}") }
    }
    println("${tests.size - failed}/${tests.size} JVM projection/action checks passed; native Compose NOT_RUN")
    check(failed == 0) { "$failed checks failed" }
}
