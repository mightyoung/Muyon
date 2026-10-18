package com.mightyoung.muyon.androidlab

/** Business selection is requested input, never a grant. The Service owns the source. */
data class ChatReadSelection(val key:String="11111111-1111-4111-8111-111111111111",val revision:String="7",val synthetic:Boolean=true)
data class ChatReadConversation(val text:String="",val requestId:String?=null,val runId:String?=null,val admittedServiceEpoch:String?=null,val answer:String="",val receipt:String?=null,val projection:String?=null,val status:String="idle",val reason:String="",val synthetic:Boolean=true,val cursor:Long=0,val originalReceiptIdentity:String?=null)
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

/** Main-thread ownership token. Dispatch and unsent cancellation are mutually exclusive. */
class PendingChatAction(private val requestId:String) {
    private var pending=true
    fun cancel(id:String):Boolean {
        if(!pending || id!=requestId)return false
        pending=false;return true
    }
    fun dispatch():Boolean {
        if(!pending)return false
        pending=false;return true
    }
}
