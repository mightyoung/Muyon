package com.mightyoung.muyon.androidlab.agentipc

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.os.RemoteException
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import com.mightyoung.muyon.androidlab.*
import java.io.File
import java.util.UUID
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/** Ordinary private :agent process. Exactly this Service constructs the Rust controller. */
class AgentRuntimeService:Service() {
    private val ownership=Any()
    private var platformGeneration=0L
    private var retired=false
    private var destroyed=false
    private var setupFailed=false
    private var controller:GeneratedAgentController?=null
    private var registry:AgentLivenessRegistry<IBinder>?=null
    private var settlementTarget:GeneratedAgentController?=null
    private var settlementPump:AgentSettlementPump?=null
    private val retirementRequested=AtomicBoolean()
    private val backend=ThreadPoolExecutor(1,1,0L,TimeUnit.MILLISECONDS,ArrayBlockingQueue<Runnable>(1),
        {work->Thread(work,"muyon-agent-settlement")},ThreadPoolExecutor.AbortPolicy())
    private lateinit var bootstrap:AgentServiceBootstrap
    private val build get()=BuildConfig.MUYON_BRIDGE_SOURCE_SHA

    override fun onCreate() {
        super.onCreate()
        val generation=synchronized(ownership){platformGeneration}
        bootstrap=AgentServiceBootstrap(backend,construct={
            check(Regex("[0-9a-f]{40}").matches(build)){"native_unavailable"}
            GeneratedAgentController.open(privateRoot(),build)
        },installed={lifetime->
            val value=lifetime as GeneratedAgentController
            val clients=AgentLivenessRegistry<IBinder>(ServiceProcessKeys.keys){key->
                try{safe{value.gone(key)}}finally{requestSettlement(value)}
            }
            val accepted=synchronized(ownership){
                if(retired || destroyed || generation!=platformGeneration) false
                else {controller=value;registry=clients;true}
            }
            if(!accepted) {
                try{clients.dispose()}finally{try{value.retire()}finally{value.awaitSettled()}}
            }
        },unavailable={synchronized(ownership){setupFailed=true}})
        bootstrap.start()
    }
    /** Only Service Context-derived canonical private storage. No UI/Binder path parameter. */
    private fun privateRoot():String {
        val root=File(filesDir.canonicalFile,"native-agent-service-v1")
        if(!root.exists()) try{Os.mkdir(root.absolutePath,448)}catch(error:ErrnoException){if(error.errno!=OsConstants.EEXIST)throw error}
        check(root.absolutePath==root.canonicalPath){"root_unavailable"}
        return root.absolutePath // Rust still validates owner/mode/symlink, lock, quota and index.
    }
    override fun onBind(intent:Intent?):IBinder=binder
    override fun onUnbind(intent:Intent?):Boolean { stopPlatform(dispose=false);return true }
    override fun onDestroy() {
        try{stopPlatform(dispose=true)}finally{backend.shutdown();super.onDestroy()}
    }
    private fun stopPlatform(dispose:Boolean) {
        val captured=synchronized(ownership){
            if(!retired){retired=true;platformGeneration=Math.incrementExact(platformGeneration)}
            if(dispose)destroyed=true
            controller to registry
        }
        // Even an unexpected unlink failure cannot prevent the real Rust stop signal.
        try{if(dispose)captured.second?.dispose()}catch(_:Exception){synchronized(ownership){setupFailed=true}}finally{
            val value=captured.first
            if(value==null) bootstrap.retire()
            else try{safe{value.retireRuntime(disposeHandle=dispose)}}finally{
                retirementRequested.set(true)
                requestSettlement(value)
            }
        }
    }
    /** One tested coalesced waiter; Binder controls never wait behind native settlement. */
    private fun requestSettlement(value:GeneratedAgentController) {
        val pump=synchronized(ownership){
            if(settlementTarget!=null && settlementTarget!==value) return
            settlementPump ?: AgentSettlementPump(backend,settle={
                if(retirementRequested.getAndSet(false)) safe{value.retireRuntime(disposeHandle=synchronized(ownership){destroyed})}
                value.awaitSettled()
            },failure={synchronized(ownership){setupFailed=true}}).also{settlementTarget=value;settlementPump=it}
        }
        if(!pump.request())synchronized(ownership){setupFailed=true}
    }
    private inline fun <T> safe(work:()->T):T?=try{work()}catch(_:LinkageError){synchronized(ownership){setupFailed=true};null}catch(_:Exception){synchronized(ownership){setupFailed=true};null}
    private fun local(status:UiAgentLocalStatus)=AgentReplyParcel.from(UiAgentWireReply.Local(status),build)
    private inline fun invoke(work:(GeneratedAgentController,AgentLivenessRegistry<IBinder>)->UiAgentWireReply):AgentReplyParcel {
        val capture=synchronized(ownership){
            if(destroyed)null else controller?.let{value->registry?.let{clients->value to clients}}
        }
        if(capture==null)return local(synchronized(ownership){if(retired || setupFailed)UiAgentLocalStatus.UNAVAILABLE else UiAgentLocalStatus.INITIALIZING})
        return AgentReplyParcel.from(safe{work(capture.first,capture.second)} ?: UiAgentWireReply.Local(UiAgentLocalStatus.UNAVAILABLE),build)
    }
    private fun client(epoch:String?,lease:String?):UiAgentClientRef? {
        if(epoch==null || lease==null || !HEX.matches(epoch) || !HEX.matches(lease))return null
        return UiAgentClientRef(epoch,lease)
    }
    private fun readVariant(value:Int)=UiAgentVariant.entries.getOrNull(value)
    private fun validRequest(value:String?)=value!=null && REQUEST.matches(value)
    private fun validRun(value:String?)=value==null || HEX.matches(value)

    private val binder=object:BoundedAgentBinder(){
        override fun connect(liveness:IBinder?):AgentReplyParcel {
            if(liveness==null)return local(UiAgentLocalStatus.INVALID_REQUEST)
            return invoke{value,clients->
                val callback=AtomicReference<()->Unit>()
                val recipient=IBinder.DeathRecipient{callback.get()?.invoke()}
                clients.connectLinked(liveness,link={onDeath->
                    callback.set(onDeath)
                    if(!liveness.isBinderAlive)false else try{liveness.linkToDeath(recipient,0);liveness.isBinderAlive}catch(_:RemoteException){false}
                },unlink={try{liveness.unlinkToDeath(recipient,0)}catch(_:NoSuchElementException){}},native={key->value.connect(key)})
            }
        }
        override fun start(epoch:String?,lease:String?,requestId:String?,variant:Int):AgentReplyParcel {
            val client=client(epoch,lease) ?: return local(UiAgentLocalStatus.INVALID_REQUEST)
            val selected=readVariant(variant) ?: return local(UiAgentLocalStatus.INVALID_REQUEST)
            if(!validRequest(requestId))return local(UiAgentLocalStatus.INVALID_REQUEST)
            return invoke{value,_->val result=value.start(client,requestId!!,selected);if(result is UiAgentWireReply.Started)requestSettlement(value);result}
        }
        override fun status(epoch:String?,lease:String?,requestId:String?,variant:Int,runId:String?):AgentReplyParcel {
            val client=client(epoch,lease) ?: return local(UiAgentLocalStatus.INVALID_REQUEST)
            val selected=readVariant(variant) ?: return local(UiAgentLocalStatus.INVALID_REQUEST)
            if(!validRequest(requestId) || !validRun(runId))return local(UiAgentLocalStatus.INVALID_REQUEST)
            return invoke{value,_->value.status(client,requestId!!,selected,runId)}
        }
        override fun current(epoch:String?,lease:String?):AgentReplyParcel {
            val client=client(epoch,lease) ?: return local(UiAgentLocalStatus.INVALID_REQUEST)
            return invoke{value,_->value.current(client)}
        }
        override fun lookup(epoch:String?,lease:String?,keyKind:Int,key:String?):AgentReplyParcel {
            val client=client(epoch,lease) ?: return local(UiAgentLocalStatus.INVALID_REQUEST)
            if(key==null || (keyKind!=0 && keyKind!=1) || (keyKind==0 && !validRequest(key)) || (keyKind==1 && !HEX.matches(key)))return local(UiAgentLocalStatus.INVALID_REQUEST)
            return invoke{value,_->value.lookup(client,keyKind,key)}
        }
        override fun setVisibility(epoch:String?,lease:String?,generation:Long,visible:Boolean):AgentReplyParcel {
            val client=client(epoch,lease) ?: return local(UiAgentLocalStatus.INVALID_REQUEST)
            if(generation<0)return local(UiAgentLocalStatus.INVALID_REQUEST)
            return invoke{value,_->val result=value.visibility(client,generation,visible);if(!visible)requestSettlement(value);result}
        }
        override fun release(epoch:String?,lease:String?,generation:Long):AgentReplyParcel {
            val client=client(epoch,lease) ?: return local(UiAgentLocalStatus.INVALID_REQUEST)
            if(generation<0)return local(UiAgentLocalStatus.INVALID_REQUEST)
            return invoke{value,clients->val result=value.release(client,generation);if(result is UiAgentWireReply.Ack && (result.value==UiAgentAck.APPLIED || result.value==UiAgentAck.REQUESTED))clients.markReleased(client);requestSettlement(value);result}
        }
        override fun cancel(epoch:String?,lease:String?,requestId:String?,variant:Int,runId:String?):AgentReplyParcel {
            val client=client(epoch,lease) ?: return local(UiAgentLocalStatus.INVALID_REQUEST)
            val selected=readVariant(variant) ?: return local(UiAgentLocalStatus.INVALID_REQUEST)
            if(!validRequest(requestId) || !validRun(runId))return local(UiAgentLocalStatus.INVALID_REQUEST)
            return invoke{value,_->val result=value.cancel(client,requestId!!,selected,runId);requestSettlement(value);result}
        }
        override fun close(epoch:String?,lease:String?):AgentReplyParcel {
            val client=client(epoch,lease) ?: return local(UiAgentLocalStatus.INVALID_REQUEST)
            return invoke{value,_->val result=value.close(client);requestSettlement(value);result}
        }
    }
    companion object {
        private val HEX=Regex("[0-9a-f]{32}")
        private val REQUEST=Regex("[A-Za-z0-9_-]{1,64}")
    }
}
/** :agent process lifetime, accessed only after actual Service background initialization. */
private object ServiceProcessKeys { val keys=AgentClientKeys(UUID.randomUUID().toString().replace("-","").take(16)) }
