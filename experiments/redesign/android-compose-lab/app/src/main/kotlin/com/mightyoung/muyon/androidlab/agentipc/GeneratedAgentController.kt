package com.mightyoung.muyon.androidlab.agentipc

import com.mightyoung.muyon.androidbridge.*
import com.mightyoung.muyon.androidlab.*

/** Service-only adapter. Actual generated Object, no fallback controller or business logic. */
internal class GeneratedAgentController private constructor(private val native:AgentServiceController, private val hooks:ServiceLifecycleHooks, onDrained:()->Unit, private val onCleaned:()->Unit):AgentRetainedLifetime {
    private val cleanupNotified=java.util.concurrent.atomic.AtomicBoolean()
    private val disposeRequested=java.util.concurrent.atomic.AtomicBoolean()
    private val admission=AgentHandleAdmission(onDrained)
    override val cleanupComplete get()=admission.cleanupComplete
    @Volatile private var disposedSettlement:UiAgentWireReply?=null
    /** Only trusted compile-time Service bootstrap composition invokes this metadata operation. */
    fun serviceAdmissionProbe(operation:ServiceAdmissionProbeOperation)=admission.call{native.serviceAdmissionProbe(operation).also{hooks.probeReturned()}}
    fun connect(key:String)=admission.call{projectAgentReply(native.connect(AgentConnectRequest(1u,key))).also{hooks.connected()}}
    fun start(client:UiAgentClientRef,id:String,variant:UiAgentVariant)=admission.call{projectAgentReply(native.startRun(AgentStartRequest(client.native(),id,AgentReadVariant.valueOf(variant.name))))}
    fun status(client:UiAgentClientRef,id:String,variant:UiAgentVariant,runId:String?)=admission.call{projectAgentReply(native.status(AgentStatusRequest(client.native(),AgentRunRef(id,AgentReadVariant.valueOf(variant.name),runId))))}
    fun current(client:UiAgentClientRef)=admission.call{projectAgentReply(native.current(client.native()))}
    fun lookup(client:UiAgentClientRef,kind:Int,key:String)=admission.call{projectAgentReply(native.lookup(AgentLookupRequest(client.native(),when(kind){0->AgentLookupKey.RequestId(key);1->AgentLookupKey.RunId(key);else->error("invalid_request")})))}
    fun visibility(client:UiAgentClientRef,generation:Long,visible:Boolean)=admission.call{projectAgentReply(native.setVisibility(AgentVisibilityRequest(client.native(),generation,visible)))}
    fun release(client:UiAgentClientRef,generation:Long)=admission.call{projectAgentReply(native.releaseClient(AgentReleaseRequest(client.native(),generation)))}
    fun cancel(client:UiAgentClientRef,id:String,variant:UiAgentVariant,runId:String?)=admission.call{projectAgentReply(native.cancel(AgentCancelRequest(client.native(),AgentRunRef(id,AgentReadVariant.valueOf(variant.name),runId))))}
    fun submitOrdinaryChat(client:UiAgentClientRef,id:String,conversation:String,text:String)=admission.call{native.submitOrdinaryChat(client.native(),id,conversation,text)}
    fun submitSupplierRead(client:UiAgentClientRef,id:String,text:String,key:String,revision:String)=admission.call{native.submitSupplierRead(client.native(),id,text,key,revision)}
    fun supplierReadEvents(client:UiAgentClientRef,id:String,after:Long)=admission.call{native.supplierReadEvents(client.native(),id,after)}
    fun close(client:UiAgentClientRef)=admission.call{projectAgentReply(native.close(client.native()))}
    fun gone(key:String)=admission.call{projectAgentReply(native.clientGone(key))}
    fun settle():UiAgentWireReply {
        val result=disposedSettlement ?: admission.call{projectAgentReply(native.awaitSettled())}
        val closed=result is UiAgentWireReply.Snapshot && result.value.phase==UiAgentServicePhase.CLOSED
        if(closed)disposedSettlement=result
        if(admission.disposeIfIdle(closed,disposeRequested.get()){hooks.beforeNativeClose();native.close();hooks.nativeClosed()} && cleanupNotified.compareAndSet(false,true))onCleaned()
        return result
    }
    override fun awaitSettled() { settle() }
    fun requestDisposal(){disposeRequested.set(true)}
    override fun retire() { retireRuntime(disposeHandle=true) }
    fun retireRuntime(disposeHandle:Boolean=false) {
        if(disposeHandle) disposeRequested.set(true)
        if(disposedSettlement!=null) return
        admission.call {
            if(native.retireService().outcome is AgentCloseOutcome.Rejected) error("retirement_unavailable")
        }
    }
    private fun UiAgentClientRef.native()=AgentClientRef(1u,epoch,lease)
    companion object {
        /** Called exclusively by the Service bootstrap worker with its Context-derived root. */
        fun open(privateRoot:String,expectedBuild:String,hostLease:ServiceHostLease,tools:RegisteredToolSettings?=null,syntheticTools:Boolean=false,onDrained:()->Unit,onCleaned:()->Unit):GeneratedAgentController {
            require(Regex("[0-9a-f]{40}").matches(expectedBuild)){"native_unavailable"}
            try {
                val info=bridgeInfo()
                check(info.protocol==1u && info.buildIdentity==expectedBuild){"native_incompatible"}
                val config=AgentServiceConfig(1u,privateRoot)
                hostLease.enteringNativeConstruction()
                val native=when(val host=hostLease.binding) {
                    ServiceHostBinding.SyntheticLab->AgentServiceController(config)
                    is ServiceHostBinding.Installed->if(tools==null)AgentServiceController.withHost(config,ServiceHostBindings.callback(host.owner),host.mode,host.budget) else AgentServiceController.withRegisteredTools(config,ServiceHostBindings.callback(host.owner),host.mode,host.budget,tools,syntheticTools)
                }
                return GeneratedAgentController(native,hostLease.hooks,onDrained,onCleaned)
            } catch(_:LinkageError) { throw IllegalStateException("native_unavailable") }
        }
    }
}
