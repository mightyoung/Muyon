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
    fun acquire(serviceContext:Context):ServiceHostLease =
        (serviceContext.applicationContext as? ServiceHostOwnerInstallation)?.acquireServiceHost(serviceContext)
            ?: ServiceHostLease(ServiceHostBinding.SyntheticLab)
    fun callback(owner:ServiceHostOwnerSource):ServiceHostOwnerCallback=object:ServiceHostOwnerCallback {
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

/** Service bootstrap owns this lease until native handle cleanup is proven. */
internal class ServiceHostLease(
    val binding:ServiceHostBinding,
    private val release:()->Unit={},
    val onReady:(GeneratedAgentController)->Unit={},
    val onCleaned:()->Unit={}
):AutoCloseable {
    private val closed=java.util.concurrent.atomic.AtomicBoolean()
    @Volatile var nativeConstructionStarted=false
        private set
    fun enteringNativeConstruction(){ nativeConstructionStarted=true }
    override fun close(){ if(closed.compareAndSet(false,true))release() }
}
