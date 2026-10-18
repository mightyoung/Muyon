package com.mightyoung.muyon.androidlab.agentipc

import android.content.Context
import com.mightyoung.muyon.androidbridge.*

/** Implemented by the actual application owner, never populated from an Intent or Binder. */
internal interface ServiceHostOwnerInstallation {
    fun serviceHostBinding(serviceContext:Context):ServiceHostBinding
    fun acquireServiceHost(serviceContext:Context):ServiceHostLease = ServiceHostLease(serviceHostBinding(serviceContext))
}

/** Current non-secret metadata and existence-only lookup. No credential read/create operation. */
internal interface ServiceHostOwnerSource {
    fun currentChatAuthority(conversation:String,text:String):ServiceOwnerChatAuthority?=null
    fun credentialCapability(profile:String,reference:String):ServiceOwnerCredentialCapability?=null
    fun exchangeChat(admission:String,binding:ServiceOwnerAdmissionBinding,context:ByteArray,payload:ByteArray,capability:ServiceOwnerCredentialCapability):ServiceOwnerChatResponse?=null
    fun currentScope():ServiceOwnerScope?
    fun currentProviderMetadata():ServiceOwnerProvider?
    fun credentialHandleExists(profileId:String,credentialRef:String):Boolean
    fun reviewPayload(binding:ServiceOwnerAdmissionBinding,payload:ByteArray):Boolean=false
    fun reserveBudget(binding:ServiceOwnerAdmissionBinding,requestId:String,payload:ByteArray,budget:ServiceOwnerCallBudget):String?=null
    /** Atomically consume the owner-bound reservation and its captured full budget.
     * Recheck exact policy/payload/credential existence; no secret or send capability.
     * Owner must bound total input+output tokens/spend, expire stranded holds and reject replay.
     */
    fun commitAdmission(reservation:String,binding:ServiceOwnerAdmissionBinding,requestId:String,payload:ByteArray,credentialProfileId:String,credentialRef:String):String?=null
    /** Cancel held budget using its opaque owner-local capability; preserve tombstones/consumed quota. */
    fun releaseReservation(reservation:String):Boolean=false
}

internal sealed interface ServiceHostBinding {
    /** Existing lab mode remains an explicit choice, never a fallback after owner failure. */
    data object SyntheticLab:ServiceHostBinding
    data class Installed(val owner:ServiceHostOwnerSource,val mode:ServiceOwnerMode,val budget:ServiceOwnerCallBudget):ServiceHostBinding
}

internal object ServiceHostBindings {
    /** Only the private Service calls this with its Context-derived application owner. */
    fun resolve(serviceContext:Context):ServiceHostBinding {
        val owner=serviceContext.applicationContext as? ServiceHostOwnerInstallation
            ?: return ServiceHostBinding.SyntheticLab
        // Installation exceptions propagate to Service unavailable, never silently switch modes.
        return owner.serviceHostBinding(serviceContext)
    }
    fun hooks(serviceContext:Context):ServiceLifecycleHooks? =
        serviceContext.applicationContext as? ServiceLifecycleHooks
    fun acquire(serviceContext:Context):ServiceHostLease =
        (serviceContext.applicationContext as? ServiceHostOwnerInstallation)?.acquireServiceHost(serviceContext)
            ?: ServiceHostLease(ServiceHostBinding.SyntheticLab)
    fun callback(owner:ServiceHostOwnerSource):ServiceHostOwnerCallback=object:ServiceHostOwnerCallback {
        override fun currentChatAuthority(conversation:String,text:String):ServiceOwnerChatAuthority?=try{owner.currentChatAuthority(conversation,text)}catch(_:Exception){null}
        override fun credentialCapability(profile:String,reference:String):ServiceOwnerCredentialCapability?=try{owner.credentialCapability(profile,reference)}catch(_:Exception){null}
        override fun exchangeChat(admission:String,binding:ServiceOwnerAdmissionBinding,context:ByteArray,payload:ByteArray,capability:ServiceOwnerCredentialCapability):ServiceOwnerChatResponse?=try{owner.exchangeChat(admission,binding,context,payload,capability)}catch(_:Exception){null}
        override fun currentScope():ServiceOwnerScope?=try{owner.currentScope()}catch(_:Exception){null}
        override fun currentProvider():ServiceOwnerProvider?=try {
            owner.currentProviderMetadata()?.let { metadata->
                metadata.copy(credentialHandleAvailable=owner.credentialHandleExists(metadata.profile.id,metadata.profile.credentialRef))
            }
        } catch(_:Exception){null}
        override fun reviewPayload(binding:ServiceOwnerAdmissionBinding,payload:ByteArray):Boolean=try {
            owner.reviewPayload(binding,payload)
        } catch(_:Exception){false}
        override fun reserveBudget(binding:ServiceOwnerAdmissionBinding,requestId:String,payload:ByteArray,budget:ServiceOwnerCallBudget):String?=try {
            owner.reserveBudget(binding,requestId,payload,budget)
        } catch(_:Exception){null}
        override fun releaseReservation(reservation:String):Boolean=try { owner.releaseReservation(reservation) } catch(_:Exception){false}
        override fun commitAdmission(reservation:String,binding:ServiceOwnerAdmissionBinding,requestId:String,payload:ByteArray,credentialProfileId:String,credentialRef:String):String?=try {
            owner.commitAdmission(reservation,binding,requestId,payload,credentialProfileId,credentialRef)
        } catch(_:Exception){null}
    }
}

/** Internal compile-time composition hooks; never selected from IPC or external state. */
internal interface ServiceLifecycleHooks {
    fun connected(){}
    fun probeReturned(){}
    fun acquired(){}
    fun constructed(){}
    fun beforeNativeClose(){}
    fun nativeClosed(){}
    fun destroyed(){}
    fun destroyedReturned(){}
    fun backendDrained(){}
    fun slotReleased(){}
    fun unavailable(){}
    fun replacementDenied(){}
}

/** Service bootstrap owns this lease until native handle cleanup is proven. */
internal class ServiceHostLease(
    val binding:ServiceHostBinding,
    private val release:()->Unit={},
    val onReady:(GeneratedAgentController)->Unit={},
    val onCleaned:()->Unit={},
    val hooks:ServiceLifecycleHooks=object:ServiceLifecycleHooks{}
):AutoCloseable {
    private var closeAttempted=false
    private var closed=false
    @Volatile var nativeConstructionStarted=false
        private set
    fun enteringNativeConstruction(){ nativeConstructionStarted=true }
    @Synchronized override fun close(){
        if(closed)return
        check(!closeAttempted){"owner_cleanup_uncertain"}
        closeAttempted=true
        release()
        closed=true
    }
}
