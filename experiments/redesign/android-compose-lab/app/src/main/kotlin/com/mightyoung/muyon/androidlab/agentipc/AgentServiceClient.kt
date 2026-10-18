package com.mightyoung.muyon.androidlab.agentipc

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Binder
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.mightyoung.muyon.androidlab.*
import java.util.UUID
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicInteger

internal data class AgentClientPresentation(
    val transport:UiAgentTransport=UiAgentTransport.UNBOUND,
    val snapshot:UiAgentSnapshot?=null,
    val historical:UiAgentSnapshot?=null,
    val selected:UiAgentIntent?=null,
    val message:String="尚未连接独立执行进程",
    val observationBusy:Boolean=false,
    val startPending:Boolean=false,
    val visible:Boolean=false,
)
/** Application-owned UI proxy only. This file imports no Rust binding and opens no store. */
internal class AgentServiceClient(private val context:Context,private val build:String) {
    private val main=Handler(Looper.getMainLooper())
    private val state=AgentServiceClientState(build)
    private val observeExecutor=executor("muyon-agent-observe",1)
    private val controlExecutor=executor("muyon-agent-control",1)
    // One in-flight positive visibility and one final stop; a stop cannot sit behind status
    // or an ordinary user control. No additional positive observation is queued after stop.
    private val lifecycleExecutor=executor("muyon-agent-lifecycle",1)
    private val lanes=AgentRpcLanes(observeExecutor,controlExecutor)
    private val lifecycleOutstanding=AtomicInteger()
    private val liveness=Binder()
    private var connection:ServiceConnection?=null
    private var ticket:UiAgentConnectionTicket?=null
    private var remote:BoundedAgentProxy?=null
    private var chatHandshakeAttempts=0
    private var pendingSubmit:PendingChatAction?=null
    private var pendingChat:(()->Unit)?=null
    private var pendingChatFailure:(()->Unit)?=null
    internal val chats:ChatReadPort by lazy { AgentChatReadSession(context,this) }
    private fun failPendingChat() {
        pendingSubmit?.fail();pendingSubmit=null
        val failure=pendingChatFailure
        pendingChat=null;pendingChatFailure=null
        failure?.invoke()
    }
    internal fun chatRpc(submitId:String?=null,work:(BoundedAgentProxy,UiAgentClientRef)->String,done:(String?)->Unit) {
        requireMain()
        val completion=ChatReadCompletion(done)
        val api=remote;val client=state.client;val captured=ticket
        if(api==null || client==null || captured==null) {
            if(pendingChat!=null){completion.complete(null);return}
            val action=submitId?.let(::PendingChatAction)
            pendingSubmit=action
            val deferred={if(action==null || action.dispatch()){pendingSubmit=null;chatRpc(submitId,work){completion.complete(it)}};Unit}
            pendingChat=deferred
            pendingChatFailure={completion.complete(null);Unit};chatHandshakeAttempts=0
            // Binding, initializing and visibility acknowledgement all have a bounded exit.
            main.postDelayed({if(pendingChat===deferred)failPendingChat()},5000)
            connect();return
        }
        val accepted=lanes.observe {
            val reply=try{work(api,client)}catch(_:Exception){null}
            main.post{completion.complete(if(ticket!==captured || state.client!=client)null else reply)}
        }
        if(!accepted)completion.complete(null)
        else main.postDelayed({completion.complete(null)},5000) // Unknown if native RPC does not return; never redispatch.
    }
    internal fun chatCancel(id:String,run:String?,done:(String?)->Unit) {
        requireMain()
        // This branch is definitive: no worker/IPC was scheduled for this token.
        if(pendingSubmit?.cancel(id)==true) {
            val failure=pendingChatFailure
            pendingChat=null;pendingChatFailure=null;pendingSubmit=null
            failure?.invoke() // releases the original UI in-flight slot
            done("not_sent_cancelled");return
        }
        val api=remote;val client=state.client;val captured=ticket
        if(api==null || client==null || captured==null){done(null);return}
        val accepted=lanes.control {
            val reply=try{api.cancel(client.epoch,client.lease,id,UiAgentVariant.INQUIRY.ordinal,run).decode(build)}catch(_:Exception){null}
            main.post{done(if(ticket===captured && state.client==client && reply is UiAgentWireReply.Ack && (reply.value==UiAgentAck.APPLIED || reply.value==UiAgentAck.REQUESTED))"cancel_requested" else null)}
        }
        if(!accepted)done(null)
    }
    private var observationBusy=false
    private var startPending=false
    private var stopping=false
    private var sentVisibility:Pair<UiAgentClientRef,Long>?=null
    var presentation by mutableStateOf(AgentClientPresentation());private set

    private fun requireMain(){check(Looper.myLooper()==Looper.getMainLooper())}
    private fun publish(message:String=presentation.message) {
        requireMain()
        presentation=AgentClientPresentation(state.transport,state.snapshot,state.historical,state.selectedIntent,message,observationBusy,startPending,state.visible)
    }
    fun visibility(activityId:String,visible:Boolean) {
        requireMain()
        val change=state.activityVisibility(activityId,visible)
        publish()
        if(change!=null)sendVisibility(change)
        else if(!state.visible && connection!=null && state.client==null) {
            // No native lease exists yet. Unbinding reaches the Service's explicit
            // late-constructor retirement path instead of inventing a native epoch.
            stopping=true;ticket?.let{state.transportLost(it)};unbind();publish("界面已不可见；原运行结果须重新核实")
        }
    }
    fun attach(){requireMain();publish()}
    fun detach(){requireMain();state.detachDisplay();publish()}
    fun connect() {
        requireMain()
        if(!state.visible){publish("请在界面可见时连接");failPendingChat();return}
        if(stopping || (remote==null && lifecycleOutstanding.get()>0)){publish("停止请求尚未返回；请先核实原运行");failPendingChat();return}
        if(remote!=null){handshake();return}
        if(connection!=null){publish("正在绑定独立执行进程");return}
        val localTicket=state.beginBinding();ticket=localTicket
        val callback=object:ServiceConnection {
            override fun onServiceConnected(name:ComponentName?,service:IBinder?) {
                if(connection!==this)return
                remote=IAgentRuntime.Stub.asInterface(service)?.let(::BoundedAgentProxy)
                if(remote==null){lost(localTicket);return}
                // Android may rebind a dead Service. This performs only connect/current;
                // it never generates an admission ID or resubmits a previous run.
                handshake()
            }
            override fun onServiceDisconnected(name:ComponentName?){if(connection===this){remote=null;lost(localTicket);unbind()}}
            override fun onBindingDied(name:ComponentName?){if(connection===this){remote=null;lost(localTicket);unbind()}}
            override fun onNullBinding(name:ComponentName?){if(connection===this){remote=null;lost(localTicket);unbind()}}
        }
        connection=callback
        try {
            if(!context.bindService(Intent(context,AgentRuntimeService::class.java),callback,Context.BIND_AUTO_CREATE)){connection=null;lost(localTicket)}
            else publish("正在绑定独立执行进程")
        } catch(_:Exception){connection=null;lost(localTicket)}
    }
    private fun handshake() {
        val api=remote ?: run{failPendingChat();return};val localTicket=ticket ?: run{failPendingChat();return}
        val scheduled=observe(localTicket,{api.connect(liveness).decode(build)}) { reply ->
            when(reply) {
                is UiAgentWireReply.Connected -> {
                    if(state.connected(localTicket,reply.meta,reply.client.lease,reply.phase)==UiAgentApply.APPLIED){
                        state.visibilityForCurrentLease()?.let(::sendVisibility)
                        publish("已连接独立进程；先核实当前记录")
                        // This is a read-only reconciliation, never automatic execution.
                        main.post{if(pendingChat==null)refresh()}
                    } else failPendingChat()
                }
                is UiAgentWireReply.Local -> {
                    if(reply.status==UiAgentLocalStatus.INITIALIZING) {
                        state.transportInitializing(localTicket)
                        // Only lease/bootstrap observation retries. No admitted request is retried.
                        if(pendingChat!=null && chatHandshakeAttempts++<20) main.postDelayed({if(ticket===localTicket)handshake()},250)
                        else if(pendingChat!=null)failPendingChat()
                    } else if(pendingChat!=null)failPendingChat()
                    publish(localLabel(reply.status))
                }
                is UiAgentWireReply.Busy -> {publish("独立执行进程忙；未自动重试");failPendingChat()}
                is UiAgentWireReply.Rejected -> {publish("连接返回 ${reply.error.name}；未自动重试");failPendingChat()}
                else -> lost(localTicket)
            }
        }
        if(!scheduled)failPendingChat()
    }
    fun refresh() {
        requireMain()
        val api=remote ?: run{connect();return};val localTicket=ticket ?: return
        val client=state.client ?: run{handshake();return}
        val observation=state.capture() ?: return
        observe(localTicket,{api.current(client.epoch,client.lease).decode(build)}){reply->applyObservation(observation,reply)}
    }
    fun lookupOriginal() {
        requireMain()
        val api=remote ?: return;val localTicket=ticket ?: return
        val intent=state.selectedIntent ?: run{refresh();return}
        val client=state.client ?: return
        val observation=state.captureLookup(intent) ?: return
        observe(localTicket,{api.lookup(client.epoch,client.lease,0,intent.requestId).decode(build)}){reply->applyObservation(observation,reply)}
    }
    fun start(variant:UiAgentVariant) {
        requireMain()
        val api=remote ?: run{publish("执行进程未连接");return};val localTicket=ticket ?: return
        if(observationBusy){publish("状态查询尚未返回；未提交新请求");return}
        // Reserve a real observer admission before changing local pending state. The
        // worker waits only for this immediate main-thread decision, never for Rust.
        val ready=java.util.concurrent.CountDownLatch(1)
        val payload=java.util.concurrent.atomic.AtomicReference<Pair<UiAgentStartDecision.Submit,UiAgentObservationTicket>?>()
        observationBusy=true
        val admitted=lanes.observe {
            ready.await()
            val request=payload.get()
            val reply=if(request==null)null else try{api.start(request.first.client.epoch,request.first.client.lease,request.first.intent.requestId,variant.ordinal).decode(build)}catch(_:Exception){null}
            main.post{
                observationBusy=false
                if(ticket!==localTicket)return@post
                if(request!=null)when(reply){
                    is UiAgentWireReply.Started -> {publish(if(reply.existing)"返回原请求记录；未重复执行" else "已易失排队；等待 Rust 持久接纳与实际收尾");main.post{refresh()}}
                    is UiAgentWireReply.Busy,is UiAgentWireReply.Rejected -> if(state.rejectedStart(request.second,reply)){startPending=false;publish("执行服务返回拒绝或忙；请先核实当前状态");main.post{refresh()}}
                    else -> lost(localTicket)
                }
                publish()
            }
        }
        if(!admitted){observationBusy=false;publish("状态通道忙；未提交新请求");return}
        try {
            val decision=state.userStart("u_"+UUID.randomUUID().toString().replace("-",""),variant)
            if(decision is UiAgentStartDecision.Submit) {
                val original=state.capture(UiAgentObservationKind.STATUS) ?: error("local_ticket_unavailable")
                payload.set(decision to original)
                startPending=true
                publish("正在请求离线合成运行；排队不代表持久接纳")
            } else publish(when(decision){UiAgentStartDecision.Busy->"已有待核实请求；不会重复提交";UiAgentStartDecision.ReconcileFirst->"请先核实当前记录";else->"当前不能开始离线运行"})
        } finally {ready.countDown()}
    }
    fun cancel()=runControl { api,client,intent,run -> api.cancel(client.epoch,client.lease,intent?.requestId ?: return@runControl null,intent.variant.ordinal,run) }
    fun closeRuntime()=runControl { api,client,_,_ -> api.close(client.epoch,client.lease) }
    private fun runControl(work:(BoundedAgentProxy,UiAgentClientRef,UiAgentIntent?,String?)->AgentReplyParcel?) {
        requireMain()
        val api=remote ?: return;val localTicket=ticket ?: return;val client=state.client ?: return
        val intent=state.selectedIntent
        val run=agentControlRunId(state.snapshot?.run,intent)
        val admitted=lanes.control {
            val reply=try{work(api,client,intent,run)?.decode(build)}catch(_:Exception){null}
            main.post{
                if(ticket!==localTicket || state.client!=client)return@post
                when(reply){is UiAgentWireReply.Ack->publish("控制请求 ${reply.value.name}；以 Rust 实际终态为准");is UiAgentWireReply.Rejected->publish("控制返回 ${reply.error.name}；请核实原运行");else->lost(localTicket)}
            }
        }
        publish(if(admitted)"正在发送控制请求；尚未确认取消或关闭" else "控制通道忙；本次请求未进入客户端通道")
    }
    private fun sendVisibility(change:UiAgentVisibility) {
        val api=remote ?: return;val localTicket=ticket ?: return
        if(change.visible && (stopping || sentVisibility==(change.client to change.generation)))return
        if(!change.visible){stopping=true;(chats as AgentChatReadSession).transportLost()}
        val release=if(!change.visible)state.release() else null
        sentVisibility=change.client to change.generation
        lifecycleOutstanding.incrementAndGet()
        try{lifecycleExecutor.execute{
            val result=try{
                val visibility=api.setVisibility(change.client.epoch,change.client.lease,change.generation,change.visible).decode(build)
                if(release!=null)api.release(release.client.epoch,release.client.lease,release.generation)
                visibility
            }catch(_:Exception){null}
            finally{lifecycleOutstanding.decrementAndGet()}
            main.post{
                if(ticket!==localTicket)return@post
                val accepted=result is UiAgentWireReply.Ack && (result.value==UiAgentAck.APPLIED || result.value==UiAgentAck.REQUESTED)
                state.visibilityAcknowledged(change.client,change.generation,accepted)
                if(!change.visible){state.release();unbind();publish("已请求停止并解除绑定；原结果须核实，不能认定已取消")}
                else if(accepted){publish("可见性已确认；离线运行仍须显式开始");val work=pendingChat;pendingChat=null;pendingChatFailure=null;work?.invoke()}
                else {publish("可见性未确认；不会开始新运行");failPendingChat()}
            }
        }}catch(_:RejectedExecutionException){lifecycleOutstanding.decrementAndGet();failPendingChat();publish("可见性控制通道不可用；结果须核实");if(!change.visible){unbind();state.release()}}
    }
    private fun observe(localTicket:UiAgentConnectionTicket,work:()->UiAgentWireReply?,deliver:(UiAgentWireReply)->Unit):Boolean {
        if(observationBusy){publish("状态通道忙；未排队或自动重试");return false}
        observationBusy=true
        val admitted=lanes.observe {
            val reply=try{work()}catch(_:Exception){null}
            main.post{
                observationBusy=false
                if(ticket!==localTicket)return@post
                if(reply==null)lost(localTicket) else deliver(reply)
                publish()
            }
        }
        if(!admitted)observationBusy=false
        publish()
        return admitted
    }
    /** Delivers the captured LOCAL ticket object; never reconstructs one from an IPC DTO. */
    private fun applyObservation(observation:UiAgentObservationTicket,reply:UiAgentWireReply) {
        when(reply){
            is UiAgentWireReply.Snapshot -> {
                when(state.apply(observation,reply.value)) {
                    UiAgentApply.APPLIED -> {if(reply.value.run?.intent==state.selectedIntent)startPending=false;publish("显示 Rust 原始运行记录；未恢复或重放执行")}
                    UiAgentApply.STALE -> Unit
                    else -> publish("返回记录与当前请求不一致；保留原记录待核实")
                }
            }
            is UiAgentWireReply.Unresolved -> publish("原生观察尚不确定；不能认定未执行或已取消")
            is UiAgentWireReply.Rejected -> publish("核实返回 ${reply.error.name}；保留原运行身份")
            else -> ticket?.let(::lost)
        }
    }
    private fun lost(localTicket:UiAgentConnectionTicket){if(ticket!==localTicket)return;state.transportLost(localTicket);(chats as AgentChatReadSession).transportLost();failPendingChat();publish("连接不可用，结果未知；请核实原运行，未自动重发")}
    private fun unbind(){failPendingChat();(chats as AgentChatReadSession).transportLost();val old=connection;connection=null;remote=null;ticket=null;sentVisibility=null;try{if(old!=null)context.unbindService(old)}catch(_:IllegalArgumentException){};stopping=false}
    companion object {
        private fun executor(name:String,queue:Int)=ThreadPoolExecutor(1,1,0L,TimeUnit.MILLISECONDS,ArrayBlockingQueue<Runnable>(queue),{job->Thread(job,name)},ThreadPoolExecutor.AbortPolicy())
        private fun localLabel(value:UiAgentLocalStatus)=when(value){UiAgentLocalStatus.INITIALIZING->"独立执行进程初始化中；尚无原生连接身份";UiAgentLocalStatus.BUSY->"执行进程忙；未自动重试";UiAgentLocalStatus.INVALID_REQUEST->"请求格式被拒绝；请核实当前状态";UiAgentLocalStatus.UNAVAILABLE->"执行进程不可用；结果须核实"}
    }
}
