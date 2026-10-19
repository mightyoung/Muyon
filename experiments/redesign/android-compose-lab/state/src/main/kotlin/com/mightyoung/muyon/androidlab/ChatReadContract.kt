package com.mightyoung.muyon.androidlab

/** Business selection is requested input, never a grant. The Service owns the source. */
data class ChatReadSelection(val key:String="11111111-1111-4111-8111-111111111111",val revision:String="7",val synthetic:Boolean=true)
data class ChatReadConversation(val text:String="",val requestId:String?=null,val runId:String?=null,val admittedServiceEpoch:String?=null,val answer:String="",val receipt:String?=null,val projection:String?=null,val status:String="idle",val reason:String="",val synthetic:Boolean=true,val cursor:Long=0,val originalReceiptIdentity:String?=null,val providerReceipt:Boolean=false)
data class ChatReadView(val conversations:Map<String,ChatReadConversation> = emptyMap(),val selected:ChatReadSelection=ChatReadSelection())
interface ChatReadPort {
    val snapshot:ChatReadView
    fun submit(conversationId:String,text:String)
    fun cancel(conversationId:String)
    fun reconcile(conversationId:String)
}
object ChatReadBounds {
    fun validText(value:String)=value.isNotBlank() && value.toByteArray(Charsets.UTF_8).size<=4096
    fun validSelection(value:String)=value.isNotBlank() && value.toByteArray(Charsets.UTF_8).size<=128
    fun validReply(value:String)=value.toByteArray(Charsets.UTF_8).size<=65536
}

/** Loss hides disclosure and restarts only event lookup; stable request/run/receipt identities survive. */
fun ChatReadConversation.disclosureLost(reason:String)=copy(status="unknown",reason=reason,answer="",projection=null,receipt=null,cursor=0)

/** Source kind is supplied by the Service and immutable once a run is admitted. */
fun ChatReadConversation.withServiceSource(synthetic:Boolean):ChatReadConversation {
    require((runId==null && admittedServiceEpoch==null) || this.synthetic==synthetic)
    return copy(synthetic=synthetic)
}

/** Main-thread ownership token. Dispatch and unsent cancellation are mutually exclusive. */
class PendingChatAction(private val requestId:String) {
    private var pending=true
    fun cancel(id:String):Boolean {
        if(!pending || id!=requestId)return false
        pending=false;return true
    }
    fun fail():Boolean {
        if(!pending)return false
        pending=false;return true
    }
    fun dispatch():Boolean {
        if(!pending)return false
        pending=false;return true
    }
}

/** Main-thread completion; duplicate transport/timeout/late callbacks cannot complete twice. */
class ChatReadCompletion(private val deliver:(String?)->Unit) {
    private var completed=false
    fun complete(value:String?):Boolean {
        if(completed)return false
        completed=true;deliver(value);return true
    }
}

/** A denied final disclosure is a terminal UNKNOWN envelope with no business events. */
fun ChatReadConversation.finishEnvelope(terminal:Boolean,eventCount:Int):ChatReadConversation {
    require(!terminal || status in setOf("completed","cancelled","failed","outcome_unknown") || (status=="unknown" && eventCount==0))
    return if(status in setOf("unknown","rejected"))disclosureLost(reason)else this
}

/** Called only after the decoder validates request/run/epoch and source identity. */
fun ChatReadConversation.preserveTerminalLookup(old:ChatReadConversation,terminal:Boolean,eventCount:Int,nextCursor:Long):ChatReadConversation {
    if(old.status !in setOf("completed","cancelled","failed","outcome_unknown"))return this
    require(eventCount==0 && terminal && nextCursor==old.cursor)
    return if(status !in setOf("unknown","rejected"))copy(status=old.status,reason=old.reason)else this
}
