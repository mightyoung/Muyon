package com.mightyoung.muyon.androidlab.agentipc

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.os.RemoteException
import android.os.Process
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import java.io.File
import com.mightyoung.muyon.androidlab.*
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
    private val cleanupCompleted=AtomicBoolean()
    private val backend=object:ThreadPoolExecutor(1,1,0L,TimeUnit.MILLISECONDS,ArrayBlockingQueue<Runnable>(1),
        {work->Thread(work,"muyon-agent-settlement")},ThreadPoolExecutor.AbortPolicy()) {
        override fun terminated(){try{hostLease?.hooks?.backendDrained()}finally{super.terminated()}}
    }
    private var bootstrap:AgentServiceBootstrap?=null
    private var reservation:AgentControllerRetention.Reservation?=null
    private var hostLease:ServiceHostLease?=null
    private val build get()=BuildConfig.MUYON_BRIDGE_SOURCE_SHA

    override fun onCreate() {
        super.onCreate()
        val slot=ServiceProcessKeys.controllers.reserve()
        if(slot==null){synchronized(ownership){setupFailed=true};ServiceHostBindings.hooks(this)?.replacementDenied();return}
        reservation=slot
        val generation=synchronized(ownership){platformGeneration}
        bootstrap=AgentServiceBootstrap(backend,construct={
            try {
                check(Regex("[0-9a-f]{40}").matches(build)){"native_unavailable"}
                val root=privateRoot()
                val lease=ServiceHostBindings.acquire(this)
                hostLease=lease
                ServiceProcessKeys.retainHost(slot,lease)
                lease.hooks.acquired()
                lateinit var value:GeneratedAgentController
                val tools=SearchSettingsRepository(this,(application as MuyonLabApplication).syntheticRegisteredTools)
                value=GeneratedAgentController.open(root,build,lease,tools=object:com.mightyoung.muyon.androidbridge.RegisteredToolSettings {override fun snapshot():String=tools.snapshotJson()},syntheticTools=(application as MuyonLabApplication).syntheticRegisteredTools,
                    onDrained={requestSettlement(value)},onCleaned={
                        // Native close returned and admission is sealed before touching owner storage.
                        lease.close()
                        ServiceProcessKeys.releaseHost(slot)
                        if(ServiceProcessKeys.controllers.releaseCleaned(slot,value)) {
                            cleanupCompleted.set(true)
                            lease.hooks.slotReleased()
                            lease.onCleaned()
                            if(synchronized(ownership){destroyed})backend.shutdown()
                        }
                    })
                try { lease.hooks.constructed() } catch(error:Throwable) {
                    ServiceProcessKeys.retainUncertain(value);throw error
                }
                if(!ServiceProcessKeys.controllers.publish(slot,value)){
                    ServiceProcessKeys.retainUncertain(value)
                    error("owner_unavailable")
                }
                value
            } catch(error:Throwable) {
                // Releases only a definitely unpublished slot; never drops a published object.
                val lease=hostLease
                if(lease?.nativeConstructionStarted!=true) {
                    lease?.close()
                    ServiceProcessKeys.releaseHost(slot)
                    if(ServiceProcessKeys.controllers.failedBeforePublish(slot)) {
                        cleanupCompleted.set(true)
                        lease?.hooks?.slotReleased()
                        if(synchronized(ownership){destroyed})backend.shutdown()
                    }
                }
                // Once the foreign constructor was entered, missing ownership outcome is uncertain.
                // The process roots retain slot and host; a second Service must remain unavailable.
                throw error
            }
        },installed={lifetime->
            val value=lifetime as GeneratedAgentController
            val clients=AgentLivenessRegistry<IBinder>(ServiceProcessKeys.keys){key->
                try{safe{value.gone(key)}}finally{requestSettlement(value)}
            }
            val accepted=synchronized(ownership){
                if(retired || destroyed || generation!=platformGeneration) false
                else {controller=value;registry=clients;true}
            }
            if(accepted) try {hostLease?.onReady?.invoke(value)} catch(error:Throwable) {
                synchronized(ownership){setupFailed=true}
                value.requestDisposal()
                retirementRequested.set(true)
                requestSettlement(value)
                throw error
            }
            if(!accepted) {
                try{clients.dispose()}finally{try{value.retire()}finally{value.awaitSettled()}}
            }
        },unavailable={synchronized(ownership){setupFailed=true};hostLease?.hooks?.unavailable()})
        bootstrap?.start()
    }
    /** Only Service Context-derived canonical private storage. No UI/Binder path parameter. */
    private fun privateRoot():String {
        val parent=filesDir.canonicalFile
        val followup=(application as MuyonLabApplication).useAuthorizedChatFollowup(this)
        val expected=File(parent,if(followup)OrdinaryChatAuthorizedSession.ROOT_NAME else "agent-service-root")
        val stat=try{Os.lstat(expected.absolutePath)}catch(error:ErrnoException){
            if(error.errno!=OsConstants.ENOENT)throw error
            try{Os.mkdir(expected.absolutePath,448)}catch(race:ErrnoException){
                if(race.errno!=OsConstants.EEXIST)throw race
            }
            Os.lstat(expected.absolutePath) // Reinspect creation and EEXIST races without following symlinks.
        }
        check((stat.st_mode and OsConstants.S_IFMT)==OsConstants.S_IFDIR &&
            (stat.st_mode and 4095)==448 && stat.st_uid==Process.myUid()){"root_unavailable"}
        val canonical=expected.canonicalFile
        check(canonical==expected && canonical.parentFile==parent){"root_unavailable"}
        // Rust alone owns native-agent-service-v1 below this dedicated 0700 parent.
        // Existing entries are never chmodded, repaired or removed by bootstrap.
        return canonical.absolutePath
    }
    override fun onBind(intent:Intent?):IBinder=binder
    override fun onUnbind(intent:Intent?):Boolean { stopPlatform(dispose=false);return true }
    override fun onDestroy() {
        try{hostLease?.hooks?.destroyed();stopPlatform(dispose=true)}finally{
            // The process holder and backend survive Service destruction until real cleanup.
            val slot=reservation
            if(slot==null || cleanupCompleted.get())backend.shutdown()
            super.onDestroy()
            ServiceHostBindings.hooks(this)?.destroyedReturned()
        }
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
            if(value==null) {
                bootstrap?.requestRetirement()
            } else {
                // Rust retirement can wait on a callback-held mutex. Platform callbacks only
                // revoke publication and enqueue; native settlement stays on the backend.
                if(dispose)value.requestDisposal()
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
            if(destroyed || retired || setupFailed)null else controller?.let{value->registry?.let{clients->value to clients}}
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

    private fun chatReply(id:String?,reason:String)="""{"protocol":1,"status":"unknown","reason":"$reason","request_id":"${id?.takeIf{validRequest(it)} ?: ""}","run_id":null,"admitted_service_epoch":null,"events":[],"next_cursor":0,"terminal":false,"synthetic":true}"""
    private fun invokeChat(id:String,work:(GeneratedAgentController)->String):String {
        val value=synchronized(ownership){if(destroyed || retired || setupFailed)null else controller}
            ?: return chatReply(id,"service_unavailable")
        val result=safe{work(value)} ?: return chatReply(id,"native_unavailable")
        return if(ChatReadBounds.validReply(result))result else chatReply(id,"reply_limit")
    }
    private val binder=object:BoundedAgentBinder(){
        override fun submitOrdinaryChat(epoch:String?,lease:String?,requestId:String?,conversation:String?,text:String?):String {
            val ref=client(epoch,lease)
            if(ref==null || !validRequest(requestId) || conversation==null || !ChatReadBounds.validSelection(conversation) || text==null || !ChatReadBounds.validText(text))return chatReply(requestId,"invalid_request")
            return invokeChat(requestId!!){value->value.submitOrdinaryChat(ref,requestId,conversation,text).also{requestSettlement(value)}}
        }
        override fun submitSupplierRead(epoch:String?,lease:String?,requestId:String?,text:String?,key:String?,revision:String?):String {
            val ref=client(epoch,lease)
            if(ref==null || !validRequest(requestId) || text==null || !ChatReadBounds.validText(text) || key==null || !ChatReadBounds.validSelection(key) || revision==null || !ChatReadBounds.validSelection(revision))return chatReply(requestId,"invalid_request")
            return invokeChat(requestId!!){value->value.submitSupplierRead(ref,requestId,text,key,revision).also{requestSettlement(value)}}
        }
        override fun supplierReadEvents(epoch:String?,lease:String?,requestId:String?,after:Long):String {
            val ref=client(epoch,lease)
            if(ref==null || !validRequest(requestId) || after<0)return chatReply(requestId,"invalid_request")
            return invokeChat(requestId!!){it.supplierReadEvents(ref,requestId,after)}
        }
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
private object ServiceProcessKeys {
    val controllers=AgentControllerRetention()
    private val hosts=mutableMapOf<AgentControllerRetention.Reservation,ServiceHostLease>()
    private val uncertain=mutableListOf<GeneratedAgentController>()
    @Synchronized fun retainHost(slot:AgentControllerRetention.Reservation,lease:ServiceHostLease){check(hosts.put(slot,lease)==null)}
    @Synchronized fun releaseHost(slot:AgentControllerRetention.Reservation){hosts.remove(slot)}
    @Synchronized fun retainUncertain(value:GeneratedAgentController){uncertain.add(value)}
    val keys=AgentClientKeys(UUID.randomUUID().toString().replace("-","").take(16))
}
