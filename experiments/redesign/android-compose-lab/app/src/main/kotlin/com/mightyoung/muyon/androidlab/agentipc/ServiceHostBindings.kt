package com.mightyoung.muyon.androidlab.agentipc

import android.content.Context
import com.mightyoung.muyon.androidbridge.*

/** Implemented by the actual application owner, never populated from an Intent or Binder. */
internal interface ServiceHostOwnerInstallation {
    fun serviceHostBinding(serviceContext:Context):ServiceHostBinding
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
        override fun commitAdmission(reservation:String,binding:ServiceOwnerAdmissionBinding,requestId:String,payload:ByteArray,credentialProfileId:String,credentialRef:String):String?=try {
            owner.commitAdmission(reservation,binding,requestId,payload,credentialProfileId,credentialRef)
        } catch(_:Exception){null}
    }
}
