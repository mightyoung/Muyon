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
    }
}
