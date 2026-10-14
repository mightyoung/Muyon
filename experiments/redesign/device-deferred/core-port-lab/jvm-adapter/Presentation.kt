package muyon.rd.p05c

data class BoundPlan(val domain:Domain,val business:Business,val plan:Map<String,Any?>)
/** UI projection only. Real business validation/effect/receipt recovery stays in Rust. */
class Presentation(val domain:Domain,var epoch:String) {
    var snapshot:Map<String,Any?>?=null;private set
    var draft:String=""
    var currentIntent:String?=null
    var status:String="loading";private set
    private var appliedSeq:ULong?=null
    private val ledger=linkedMapOf<String,Map<String,Any?>>()
    val receipts:Map<String,Map<String,Any?>> get()=ledger.toMap()
    internal fun localStatus(value:String) {status=value}
    fun accept(reply:Reply,bound:BoundPlan?=null) {
        if(reply.domain!=domain) return
        reply.receipt?.let {receipt->
            if(bound!=null && bound.domain==domain && receipt["kind"]=="synthetic"
                &&receipt["intent"]==bound.business.intent && receipt["object_id"]==bound.business.objectId
                &&receipt["expected_revision"]==bound.business.expectedRevision
                &&receipt["parameters_digest"]==bound.plan["parameters_digest"]
                &&receipt["normalized_name"]==bound.plan["normalized_name"]
                &&receipt.text("id").isNotBlank()
                &&Domain.from(receipt["commit_cursor"].objectValue().filterKeys {it!="seq"})==domain) {
                decimal(receipt["result_revision"])
                ledger.putIfAbsent(bound.business.intent,receipt.toMap())
            }
        }
        if(reply.epoch!=epoch || reply.admission!="current") return
        reply.snapshot?.let {candidate->
            val cursor=candidate["cursor"].objectValue()
            if(Domain.from(cursor.filterKeys {it!="seq"})==domain) {
                val seq=decimal(cursor["seq"]).toULong()
                if(appliedSeq==null || seq>=appliedSeq!!) {snapshot=candidate.toMap();appliedSeq=seq}
            }
        }
        if(bound==null || currentIntent==bound.business.intent) status=reply.kind
    }
}
