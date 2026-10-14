package muyon.rd.p04

data class Domain(val store: String, val scope: String, val stream: String)
data class Supplier(val id: String, val name: String, val revision: String)
data class Snapshot(val domain: Domain, val coveredThrough: Long, val suppliers: List<Supplier>)
data class Draft(val intent: String, val raw: String, val expectedRevision: String)
data class Preview(val intent: String, val supplierId: String, val raw: String, val expectedRevision: String)
enum class Decision { ALLOW, CONFIRM, HARD_DENY }
data class Plan(val ref: String, val decision: Decision)
data class Command(val intent: String, val supplierId: String, val plan: String, val domain: Domain, val generation: Long, val expectedRevision: String)
/** Mock-only revision grammar. No product wire encoding or opaque-version ordering.
 * Canonical r<decimal u64> counter, one effect increments exactly once; max has no successor.
 */
private fun mockRevisionSuccessor(revision: String): String? {
    if(!Regex("r(?:0|[1-9][0-9]*)").matches(revision)) return null
    val value=revision.substring(1).toULongOrNull() ?: return null
    if(value==ULong.MAX_VALUE) return null
    return "r${value+1uL}"
}
sealed interface Outcome {
    val command: Command
    data class Unknown(override val command: Command): Outcome
    data class Conflict(override val command: Command, val current: Supplier): Outcome
    data class Effect(override val command: Command, val receipt: String, val supplier: Supplier): Outcome
}
enum class Page { LIST, DETAIL, EDIT }
enum class Status { LOADING, READY, SUBMITTING, SAVED, CONFLICT, UNKNOWN, DENIED, CONFIRM }
data class ScreenState(val page: Page=Page.LIST, val status: Status=Status.LOADING, val generation: Long=0, val suppliers: List<Supplier> = emptyList(), val saved: Supplier?=null, val draft: Draft?=null)
interface RustCorePort {
    fun attach(snapshot: (Snapshot, Long)->Unit, outcome: (Outcome)->Unit)
    fun preview(input: Preview): Plan
    fun commit(command: Command)
}
class MockRustCorePort: RustCorePort {
    var decision=Decision.ALLOW
    val previews=mutableListOf<Preview>(); val commits=mutableListOf<Command>()
    private var snapshotSink: (Snapshot, Long)->Unit = {_,_->}; private var outcomeSink: (Outcome)->Unit = {}
    override fun attach(snapshot: (Snapshot, Long)->Unit, outcome: (Outcome)->Unit) {snapshotSink=snapshot; outcomeSink=outcome}
    override fun preview(input: Preview): Plan {previews.add(input); return Plan("mock-plan-${input.intent}",decision)}
    override fun commit(command: Command) {commits.add(command)}
    fun emitSnapshot(snapshot: Snapshot, generation: Long) {snapshotSink(snapshot,generation)}
    fun emitOutcome(outcome: Outcome) {outcomeSink(outcome)}
}
/** Provisional in-memory adapter. All callbacks must be serialized on the UI thread.
 * Port adapters, not UI flags, must validate source, permissions and actual receipts.
 */
class SupplierPresenter(private val port: RustCorePort) {
    var state=ScreenState(); private set
    private val drafts=mutableMapOf<String,Draft>()
    private val submitted=mutableMapOf<String,Command>()
    private val intentStatuses=mutableMapOf<String,Status>()
    private val retainedReceipts=mutableMapOf<String,Outcome.Effect>()
    private var domain: Domain?=null
    private var watermark: Long=-1
    private var nextIntent=0L
    private var pendingPlan: Command?=null
    val receipts: Map<String,Outcome.Effect> get()=retainedReceipts.toMap()
    init {port.attach(::applySnapshot,::applyOutcome)}
    private fun applySnapshot(snapshot: Snapshot, generation: Long) {
        if(generation!=state.generation || (domain!=null && snapshot.domain!=domain) || snapshot.coveredThrough<watermark) return
        domain=snapshot.domain; watermark=snapshot.coveredThrough
        state=state.copy(suppliers=snapshot.suppliers.toList(), saved=state.saved?.let { old->snapshot.suppliers.find {it.id==old.id} },status=if(state.status==Status.LOADING) Status.READY else state.status)
    }
    fun select(id: String) {
        val supplier=state.suppliers.find {it.id==id} ?: return
        pendingPlan=null
        state=state.copy(page=Page.DETAIL,generation=state.generation+1,saved=supplier,draft=drafts[id],status=drafts[id]?.intent?.let {intentStatuses[it]?.takeUnless {status->status==Status.SAVED}} ?: Status.READY)
    }
    fun edit() {
        val saved=state.saved ?: return
        if(drafts[saved.id]?.intent in retainedReceipts) drafts.remove(saved.id)
        val draft=drafts.getOrPut(saved.id) {Draft("mock-intent-${++nextIntent}",saved.name,saved.revision)}
        state=state.copy(page=Page.EDIT,draft=draft,status=if(submitted.containsKey(draft.intent)) state.status else Status.READY)
    }
    fun change(raw: String) {
        val saved=state.saved ?: return; val draft=state.draft ?: return
        if(state.page!=Page.EDIT || submitted.containsKey(draft.intent)) return
        val changed=draft.copy(raw=raw); drafts[saved.id]=changed; pendingPlan=null
        state=state.copy(draft=changed,status=Status.READY)
    }
    fun back() {
        pendingPlan=null
        state=state.copy(page=Page.LIST,generation=state.generation+1,status=Status.READY)
    }
    fun save() {
        val saved=state.saved ?: return; val draft=state.draft ?: return; val currentDomain=domain ?: return
        if(state.page!=Page.EDIT || submitted.containsKey(draft.intent) || pendingPlan!=null) return
        if(mockRevisionSuccessor(draft.expectedRevision)==null) {
            state=state.copy(status=Status.DENIED)
            return
        }
        val plan=port.preview(Preview(draft.intent,saved.id,draft.raw,draft.expectedRevision))
        val command=Command(draft.intent,saved.id,plan.ref,currentDomain,state.generation,draft.expectedRevision)
        when(plan.decision) {
            Decision.HARD_DENY->state=state.copy(status=Status.DENIED)
            Decision.CONFIRM->{pendingPlan=command; state=state.copy(status=Status.CONFIRM)}
            Decision.ALLOW->dispatch(command)
        }
    }
    fun confirm() {
        val command=pendingPlan ?: return; pendingPlan=null
        if(command.generation==state.generation && command.supplierId==state.saved?.id) dispatch(command)
    }
    private fun dispatch(command: Command) {
        if(submitted.putIfAbsent(command.intent,command)!=null) return
        intentStatuses[command.intent]=Status.SUBMITTING
        state=state.copy(status=Status.SUBMITTING)
        port.commit(command)
    }
    private fun applyOutcome(outcome: Outcome) {
        val command=outcome.command
        if(submitted[command.intent]!=command) return
        if(outcome is Outcome.Effect) {
            if(outcome.supplier.id!=command.supplierId || outcome.receipt.isBlank()) return
            val expectedResult=mockRevisionSuccessor(command.expectedRevision) ?: return
            if(outcome.supplier.revision!=expectedResult) return
            if(retainedReceipts.containsKey(command.intent)) return
            retainedReceipts[command.intent]=outcome
        }
        if(outcome is Outcome.Conflict && outcome.current.id!=command.supplierId) return
        if(outcome !is Outcome.Effect && retainedReceipts.containsKey(command.intent)) return
        intentStatuses[command.intent]=when(outcome) {
            is Outcome.Unknown->Status.UNKNOWN
            is Outcome.Conflict->Status.CONFLICT
            is Outcome.Effect->Status.SAVED
        }
        if(command.generation!=state.generation || command.supplierId!=state.saved?.id) return
        // A terminal effect cannot be downgraded by a late timeout or conflict.
        if(outcome !is Outcome.Effect && retainedReceipts.containsKey(command.intent)) return
        state=when(outcome) {
            is Outcome.Unknown->state.copy(status=Status.UNKNOWN)
            is Outcome.Conflict->if(outcome.current.id==command.supplierId) state.copy(status=Status.CONFLICT,saved=outcome.current) else state
            is Outcome.Effect->state.copy(status=Status.SAVED,saved=outcome.supplier)
        }
    }
}
