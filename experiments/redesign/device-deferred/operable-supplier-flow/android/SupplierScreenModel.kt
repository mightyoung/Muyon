package muyon.rd.p08.android

/** Experimental host projection DTOs only. M03 production wire remains blocked_contract.
 * Adapter supplies typed host truth; this file has no JSON parser or business implementation. */
data class SupplierRow(val supplier: String, val name: String, val revision: String)
data class PreviewProjection(val normalized_name: String, val candidate_revision: String)
data class OriginalBinding(val domain: String, val scope: String, val supplier: String, val intent: String,
    val operation: String, val raw_utf16: List<Int>, val expected_revision: String, val plan: String, val candidate: String)
data class OriginalReceipt(val intent: String, val binding: OriginalBinding, val binding_sha256: String,
    val source: String, val supplier: String, val old_name: String, val new_name: String,
    val old_revision: String, val new_revision: String)
data class EditorProjection(val intent: String, val supplier: String, val raw: String, val status: String,
    val expected_revision: String, val preview: PreviewProjection?, val current: SupplierRow?,
    val receipt: OriginalReceipt?, val reason: String?)
data class RecoverableSession(val session: String, val supplier: String?, val status: String?)
data class HostProjection(val suppliers: List<SupplierRow>, val selected: SupplierRow?, val editor: EditorProjection?,
    val capability: String, val session: String, val csrf: String, val list_status: String,
    val recoverable_sessions: List<RecoverableSession>)
sealed interface HostAction {
    data class Select(val supplier: String) : HostAction
    data object Edit : HostAction
    data class Draft(val raw: String) : HostAction
    data object Preview : HostAction
    data object Save : HostAction
    data object Cancel : HostAction
    data object Lookup : HostAction
}
sealed interface PortReply {
    data class Projected(val projection: HostProjection) : PortReply
    data object Unavailable : PortReply
}
/** The adapter retains exact session/CSRF metadata and obtains verified host projections.
 * Deliver callbacks on UI thread, once. No retry of writes; refresh/restore are GET only.
 * Native HTTP/JNI adapter is NOT_IMPLEMENTED, never implied by this injection seam. */
interface SupplierActionPort {
    fun action(action: HostAction, reply: (PortReply) -> Unit)
    fun refresh(reply: (PortReply) -> Unit)
    fun restoreOriginalSession(session: String, reply: (PortReply) -> Unit)
}
enum class ScreenPage { LIST, DETAIL, EDITOR }
/** Presentation/navigation state only. Every business status and receipt comes from the host.
 * Local request tokens reject duplicate callbacks; they are not business revisions or cursors. */
class SupplierScreenModel(initial: HostProjection, private val port: SupplierActionPort) {
    var projection = initial; private set
    var page = ScreenPage.LIST; private set
    var buffer = initial.editor?.raw.orEmpty(); private set
    var busy = false; private set
    var discardConfirmation = false; private set
    var transportMessage: String? = null; private set
    var onChanged: () -> Unit = {}
    private var sequence = 0L
    private var activeRequest: Long? = null
    private var transportUncertain = false
    private var syncingDraft = false
    private val dirty get() = buffer != projection.editor?.raw.orEmpty()
    private val editableStatus get() = projection.editor?.status in setOf("editing", "prepared", "rejected")
    val canChangeRaw get() = editableStatus && !transportUncertain && (!busy || syncingDraft)
    val canRestoreSession get() = !busy && !dirty
    val canEdit get() = !busy && !transportUncertain && projection.selected != null && projection.editor == null
    val canPreview get() = !busy && canChangeRaw && !dirty
    val canSave get() = !busy && !transportUncertain && !dirty && projection.editor?.status == "prepared" && projection.editor?.preview != null
    val canLookup get() = !busy && projection.editor != null && (transportUncertain || projection.editor?.status in setOf("unknown", "saving", "unavailable") || (projection.editor?.status == "saved" && !saved))
    val canCancel get() = !busy && !transportUncertain && (projection.editor?.status in setOf("editing", "prepared", "rejected") || saved || (projection.editor?.status == "conflict" && projection.editor?.reason == "Revision"))
    val saved get() = projection.editor?.status == "saved" && originalReceipt != null && !transportUncertain
    val statusText get() = when {
        transportUncertain -> "结果未知，请核对原回执"
        saved -> "已保存"
        else -> when (projection.editor?.status) {
            null -> "未编辑"
            "editing" -> "草稿未保存"
            "prepared" -> "Rust 校验通过，尚未保存"
            "saving" -> "保存中，等待原回执"
            "conflict" -> "版本冲突，保留原输入"
            "unknown" -> "结果未知，请核对原回执"
            "rejected" -> "主机拒绝，请查看原因"
            else -> "无法核实结果，请核对原操作"
        }
    }
    val currentRow get() = projection.editor?.current
    val originalReceipt get() = projection.editor?.receipt

    fun select(supplier: String) {
        if (busy || projection.suppliers.none { it.supplier == supplier }) return
        issue({ port.action(HostAction.Select(supplier), it) }, preserveLocal = true) {
            if (projection.selected?.supplier == supplier) page = ScreenPage.DETAIL
        }
    }
    fun edit() {
        if (!canEdit) return
        issue({ port.action(HostAction.Edit, it) }) {
            if (projection.editor != null) page = ScreenPage.EDITOR
        }
    }
    fun openOriginalEditor() {
        if (projection.editor == null) return
        page = ScreenPage.EDITOR; changed()
    }
    fun changeRaw(raw: String) {
        if (!canChangeRaw) return
        buffer = raw; discardConfirmation = false; changed()
        syncDraft()
    }
    private fun syncDraft() {
        if (busy || !canChangeRaw || !dirty) return
        val raw = buffer
        issue({ port.action(HostAction.Draft(raw), it) }, preserveLocal = true, draftRequest = true) { syncDraft() }
    }
    fun preview() {
        if (!canPreview) return
        issue({ port.action(HostAction.Preview, it) }) {}
    }
    fun save() {
        if (!canSave) return
        issue({ port.action(HostAction.Save, it) }, uncertainOnFailure = true) {}
    }
    fun lookup() {
        if (!canLookup) return
        issue({ port.action(HostAction.Lookup, it) }, uncertainOnFailure = true) {}
    }
    fun back() {
        if (busy) return
        when (page) {
            ScreenPage.LIST -> Unit
            ScreenPage.DETAIL -> page = ScreenPage.LIST
            ScreenPage.EDITOR -> if (canCancel && !saved) discardConfirmation = true else page = ScreenPage.DETAIL
        }
        changed()
    }
    fun requestCancel() {
        if (!canCancel) return
        if (saved) cancelConfirmed() else { discardConfirmation = true; changed() }
    }
    fun keepEditing() { discardConfirmation = false; changed() }
    fun confirmDiscard() {
        if (!discardConfirmation || !canCancel) return
        cancelConfirmed()
    }
    private fun cancelConfirmed() {
        issue({ port.action(HostAction.Cancel, it) }) {
            if (projection.editor == null) { discardConfirmation = false; page = ScreenPage.DETAIL }
        }
    }
    fun restoreOriginalSession(session: String) {
        if (!canRestoreSession || projection.recoverable_sessions.none { it.session == session }) return
        issue({ port.restoreOriginalSession(session, it) }, expectedSession = session) {
            page = if (projection.editor == null) ScreenPage.LIST else ScreenPage.EDITOR
        }
    }
    fun refresh() {
        if (busy) return
        issue({ port.refresh(it) }, preserveLocal = true) { syncDraft() }
    }
    private fun changed() = onChanged()
    private fun issue(
        send: ((PortReply) -> Unit) -> Unit,
        preserveLocal: Boolean = false,
        uncertainOnFailure: Boolean = false,
        draftRequest: Boolean = false,
        expectedSession: String = projection.session,
        success: () -> Unit
    ) {
        if (busy) return
        val request = ++sequence
        activeRequest = request; busy = true; syncingDraft = draftRequest; transportMessage = null; changed()
        val receive: (PortReply) -> Unit = receive@{ reply ->
            if (activeRequest != request) return@receive
            activeRequest = null; busy = false; syncingDraft = false
            if (reply is PortReply.Projected && reply.projection.session == expectedSession) {
                val priorIntent = projection.editor?.intent
                projection = reply.projection
                // Once a host result is uncertain/dispatched, its original raw wins.
                val keep = preserveLocal && priorIntent == projection.editor?.intent && editableStatus
                if (!keep) buffer = projection.editor?.raw.orEmpty()
                // A refresh of a stale prepared projection cannot prove an uncertain save resolved.
                if (projection.editor?.status in setOf("saved", "conflict", "rejected", "unknown", "saving")) transportUncertain = false
                success()
            } else {
                if (uncertainOnFailure) transportUncertain = true
                transportMessage = "主机暂不可用；保留草稿与原操作，请刷新或核对。"
            }
            changed()
        }
        try { send(receive) } catch (_: Exception) { receive(PortReply.Unavailable) }
    }
}
