package com.mightyoung.muyon.androidlab.agentipc

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.mightyoung.muyon.androidlab.*
import org.json.JSONObject
import java.util.UUID

/** UI proxy: no source access, model configuration or authority supplied by callers. */
internal class AgentChatReadSession(context:Context,private val client:AgentServiceClient):ChatReadPort {
    private val preferences=context.getSharedPreferences("supplier-read-identities-v1",Context.MODE_PRIVATE)
    private val main=Handler(Looper.getMainLooper())
    private val inFlight=mutableSetOf<String>()
    override var snapshot by mutableStateOf(ChatReadView());private set
    init {
        val restored=mutableMapOf<String,ChatReadConversation>()
        preferences.all.entries.take(64).forEach{(conversation,value)->
            try{val o=JSONObject(value as String);require(ChatReadBounds.validText(o.string("text")) && o.string("key")==snapshot.selected.key && o.string("revision")==snapshot.selected.revision);restored[conversation]=ChatReadConversation(text=o.string("text"),requestId=o.string("request"),runId=o.optString("run").takeIf{it.isNotBlank()},admittedServiceEpoch=o.optString("epoch").takeIf{it.isNotBlank()},originalReceiptIdentity=o.optString("receiptIdentity").takeIf{it.isNotBlank()},synthetic=if(o.has("synthetic"))o.boolean("synthetic") else true,status="unknown",reason="进程恢复；请核实原请求，未重新执行")}catch(_:Exception){restored[conversation]=ChatReadConversation(status="unknown",reason="恢复记录不可核实；禁止重新提交")}
        }
        snapshot=ChatReadView(restored)
    }
    private fun update(id:String,value:ChatReadConversation) {
        snapshot=snapshot.copy(conversations=snapshot.conversations+(id to value))
        val record=JSONObject().put("receiptIdentity",value.originalReceiptIdentity ?: "").put("text",value.text).put("key",snapshot.selected.key).put("revision",snapshot.selected.revision).put("request",value.requestId).put("run",value.runId ?: "").put("epoch",value.admittedServiceEpoch ?: "").put("synthetic",value.synthetic)
        check(preferences.edit().putString(id,record.toString()).commit()){ "request_identity_not_persisted" }
    }
    internal fun transportLost() {
        snapshot=snapshot.copy(conversations=snapshot.conversations.mapValues{(_,value)->value.disclosureLost("连接失效；请核实原请求，未自动重发")})
    }
    override fun submit(conversationId:String,text:String) {
        check(Looper.myLooper()==Looper.getMainLooper())
        if(!ChatReadBounds.validText(text) || conversationId.length !in 1..128)return
        val old=snapshot.conversations[conversationId]
        if(old!=null && old.status !in setOf("completed","cancelled","failed","rejected")){reconcile(conversationId);return}
        if(snapshot.conversations.size>=64 && old==null)return
        val value=ChatReadConversation(text=text,requestId="chat_"+UUID.randomUUID().toString().replace("-",""),status="submitting",reason="等待私有 Service 核实来源与当前授权；未调用真实模型")
        // Persist identity before the very first Binder submission. Failure prevents dispatch.
        try{update(conversationId,value)}catch(_:Exception){snapshot=snapshot.copy(conversations=snapshot.conversations+(conversationId to value.copy(status="failed",reason="请求身份持久化失败；未提交")));return}
        val selected=snapshot.selected
        rpc(conversationId,submitId=value.requestId){api,ref->api.submitSupplierRead(ref.epoch,ref.lease,value.requestId!!,text,selected.key,selected.revision)}
    }
    override fun reconcile(conversationId:String) {
        val value=snapshot.conversations[conversationId] ?: return
        val id=value.requestId ?: return
        rpc(conversationId){api,ref->api.supplierReadEvents(ref.epoch,ref.lease,id,value.cursor)}
    }
    override fun cancel(conversationId:String) {
        val value=snapshot.conversations[conversationId] ?: return
        val id=value.requestId ?: return
        client.chatCancel(id,value.runId){result->
            if(result=="not_sent_cancelled") {
                update(conversationId,(snapshot.conversations[conversationId] ?: value).copy(status="cancelled",reason="已撤销尚未发送的请求；未执行供应商读取"))
                return@chatCancel
            }
            update(conversationId,(snapshot.conversations[conversationId] ?: value).copy(status=if(result!=null)"cancel_requested" else "unknown",reason=if(result!=null)"已请求取消；以原运行终态与回执为准" else "取消未确认；核实原运行"))
            reconcile(conversationId)
        }
    }
    private fun rpc(conversation:String,submitId:String?=null,work:(BoundedAgentProxy,UiAgentClientRef)->String) {
        if(!inFlight.add(conversation))return
        client.chatRpc(submitId,work){raw->
            inFlight.remove(conversation)
            val old=snapshot.conversations[conversation] ?: return@chatRpc
            val result=try{if(raw==null)error("transport_lost");decode(old,raw)}catch(_:Exception){old.disclosureLost("连接或协议不可核实；保留原请求，不自动重发")}
            try{update(conversation,result)}catch(_:Exception){snapshot=snapshot.copy(conversations=snapshot.conversations+(conversation to result.disclosureLost("身份记录写入失败")))}
            if(result.status in setOf("accepted","existing","events"))main.postDelayed({reconcile(conversation)},250)
        }
    }
    private fun JSONObject.string(field:String):String { val value=get(field);require(value is String);return value }
    private fun JSONObject.boolean(field:String):Boolean { val value=get(field);require(value is Boolean);return value }
    private fun decode(old:ChatReadConversation,raw:String):ChatReadConversation {
        require(ChatReadBounds.validReply(raw))
        val o=JSONObject(raw)
        require(o.keys().asSequence().toSet()==setOf("protocol","status","reason","request_id","run_id","admitted_service_epoch","events","next_cursor","terminal","synthetic"))
        require(o.get("protocol") is Int && o.getInt("protocol")==1 && o.string("request_id")==old.requestId)
        val source=old.withServiceSource(o.boolean("synthetic"))
        val run=if(o.isNull("run_id"))null else o.string("run_id")
        val epoch=if(o.isNull("admitted_service_epoch"))null else o.string("admitted_service_epoch")
        require(run==null || Regex("[0-9a-f]{32}").matches(run))
        require(epoch==null || Regex("[0-9a-f]{32}").matches(epoch))
        require(old.runId==null || old.runId==run);require(old.admittedServiceEpoch==null || old.admittedServiceEpoch==epoch)
        var value=source.copy(runId=run ?: old.runId,admittedServiceEpoch=epoch ?: old.admittedServiceEpoch,status=o.string("status"),reason=o.string("reason").take(512))
        require(value.status in setOf("accepted","existing","events","rejected","unknown"))
        val events=o.getJSONArray("events");require(events.length()<=32)
        if(old.status in setOf("completed","cancelled","failed","outcome_unknown")) {
            require(events.length()==0 && o.boolean("terminal") && o.getLong("next_cursor")==old.cursor)
            if(value.status !in setOf("unknown","rejected"))value=value.copy(status=old.status)
        }
        for(index in 0 until events.length()) {
            val event=events.getJSONObject(index);require(event.keys().asSequence().toSet()==setOf("cursor","kind","payload"))
            require(event.get("cursor") is Int || event.get("cursor") is Long);val cursor=event.getLong("cursor");require(cursor==value.cursor+1)
            require(value.status !in setOf("completed","cancelled","failed","outcome_unknown"))
            val p=event.getJSONObject("payload")
            value=when(event.string("kind")) {
                "answer_delta"->{require(p.keys().asSequence().toSet()==setOf("text") && p.get("text") is String);val delta=p.string("text");require(delta.toByteArray().size<=1024 && (value.answer+delta).toByteArray().size<=32768);value.copy(answer=value.answer+delta)}
                "supplier_projection"->{require(p.keys().asSequence().toSet()==setOf("supplier","name") && p.get("name") is String);val supplier=p.getJSONObject("supplier");require(supplier.keys().asSequence().toSet()==setOf("module_id","type","key","revision","schema_version") && supplier.get("schema_version") is Int);require(supplier.string("key")==snapshot.selected.key && supplier.string("revision")==snapshot.selected.revision && supplier.string("module_id")=="inquiry" && supplier.string("type")=="supplier" && supplier.getInt("schema_version")==1);val name=p.string("name");require(name.toByteArray().size<=512);value.copy(projection=name)}
                "receipt"->{require(p.keys().asSequence().toSet()==setOf("owner","invocation_id","binding_id","identity"));require(p.string("owner")=="ToolRegistry" && p.string("binding_id")=="host-supplier-name-read" && Regex("[0-9a-f]{32}").matches(p.string("identity")) && p.string("invocation_id").toByteArray().size<=256);val identity=p.string("identity");require(value.originalReceiptIdentity==null || value.originalReceiptIdentity==identity);val receipt=p.toString();require(receipt.toByteArray().size<=4096 && (value.receipt==null || value.receipt==receipt));value.copy(receipt=receipt,originalReceiptIdentity=identity)}
                "terminal"->{require(p.keys().asSequence().toSet()==setOf("state","reason") && p.get("state") is String && p.get("reason") is String);val state=p.string("state");require(state in setOf("completed","cancelled","failed","outcome_unknown"));if(state=="completed")require(value.receipt!=null && value.projection!=null);value.copy(status=state,reason=p.string("reason").take(512))}
                else->error("unknown_event")
            }.copy(cursor=cursor)
        }
        require(o.get("next_cursor") is Int || o.get("next_cursor") is Long);require(o.getLong("next_cursor")==value.cursor)
        return value.finishEnvelope(o.boolean("terminal"),events.length())
    }
}
