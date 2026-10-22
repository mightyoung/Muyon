package muyon.rd.p05c

/** Provisional local-process controller; synthetic kernel authority only.
 * Sent intents survive snapshot/reconnect/unknown; lookup is the only recovery action.
 */
class Controller(private val port:CorePort,val presentation:Presentation) {
    private var active:Business?=null
    private var bound:BoundPlan?=null
    private val sent=mutableSetOf<String>()
    var unresolved:BoundPlan?=null;private set
    fun edit(input:Business) {
        if(unresolved!=null || input.intent in sent) return
        active=input;bound=null;presentation.draft=input.raw;presentation.currentIntent=input.intent
    }
    fun read():Reply {
        val reply=port.request("snapshot",presentation.domain,presentation.epoch)
        presentation.accept(reply)
        if(unresolved!=null) presentation.localStatus("unknown")
        return reply
    }
    fun preview():Reply? {
        if(unresolved!=null) return null
        val input=active ?: return null
        val reply=port.request("preview",presentation.domain,presentation.epoch,input.fields())
        bound=null
        reply.plan?.let {plan->
            if(reply.kind=="prepared" && reply.domain==presentation.domain && plan["intent"]==input.intent
                &&plan["object_id"]==input.objectId && plan["expected_revision"]==input.expectedRevision) {
                bound=BoundPlan(presentation.domain,input,plan.toMap())
            }
        }
        presentation.accept(reply)
        return reply
    }
    fun commit():Reply? {
        val b=bound ?: return null
        if(unresolved!=null || !sent.add(b.business.intent)) return null
        unresolved=b;presentation.localStatus("submitting")
        val reply=try {port.request("commit",b.domain,presentation.epoch,b.business.fields(b.plan.text("id")))}
        catch(e:TransportUnavailable) {presentation.localStatus("unknown");return null}
        presentation.accept(reply,b)
        if(reply.kind=="conflict" || (reply.kind=="committed" && presentation.receipts.containsKey(b.business.intent))) unresolved=null
        return reply
    }
    fun lookup():Reply? {
        val b=unresolved ?: return null
        val reply=try {port.request("lookup",b.domain,presentation.epoch,b.business.fields(b.plan.text("id")))}
        catch(e:TransportUnavailable) {presentation.localStatus("unknown");return null}
        presentation.accept(reply,b)
        if(reply.kind=="committed" && presentation.receipts.containsKey(b.business.intent)) unresolved=null
        return reply
    }
    fun reconnect(epoch:String):Reply {
        val reply=port.request("reconnect",presentation.domain,presentation.epoch,mapOf("new_display_epoch" to epoch))
        presentation.epoch=epoch;presentation.accept(reply)
        if(unresolved!=null) presentation.localStatus("unknown")
        return reply
    }
}
