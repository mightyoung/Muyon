package com.mightyoung.muyon.androidlab

import android.app.Application
import android.os.Handler
import android.os.Looper
import com.mightyoung.muyon.androidlab.agentipc.*
import android.content.Context

/** Process ownership is intentional: UI recreation must not release or replace a blocked native slot. */
@Suppress("EXPOSED_FUNCTION_RETURN_TYPE")
open class MuyonLabApplication : Application(), ServiceHostOwnerInstallation {
    /** Only a dedicated trusted build supplies an in-process secure credential entry. */
    internal open fun openChatCredentialEntry(activity:android.app.Activity) {}
    /** Trusted build composition only; caller cannot supply a storage path. */
    internal open fun useAuthorizedChatFollowup(serviceContext:Context):Boolean=false
    private val chatOwner by lazy {ServiceAdmissionProcessOwner.unconfigured()}
    override fun serviceHostBinding(serviceContext:Context):ServiceHostBinding=error("ordinary_chat_requires_owned_lease")
    override fun acquireServiceHost(serviceContext:Context):ServiceHostLease=chatOwner.acquire(serviceContext,com.mightyoung.muyon.androidbridge.ServiceOwnerCallBudget(1uL,1uL,false,false))
    // Every Android process gets its own Application. Service never reads this UI proxy.
    private val visibleActivities=mutableSetOf<String>()
    private var nextActivity=0L
    private var agentValue:AgentServiceClient?=null
    internal val agents:AgentServiceClient get()=agentValue ?: AgentServiceClient(this,BuildConfig.MUYON_BRIDGE_SOURCE_SHA).also{value->
        agentValue=value
        visibleActivities.forEach{value.visibility(it,true)}
    }
    internal fun newActivityIdentity():String {nextActivity=Math.incrementExact(nextActivity);return "activity_$nextActivity"}
    internal fun activityVisibility(id:String,visible:Boolean) {
        if(visible)visibleActivities.add(id)else visibleActivities.remove(id)
        agentValue?.visibility(id,visible)
    }
    internal open val syntheticRegisteredTools:Boolean get()=false
    internal val searchSettings:SearchSettingsPort by lazy{SearchSettingsRepository(this,syntheticRegisteredTools)}
    val chats:ChatReadPort get()=agents.chats
    val diagnostics: RustDiagnosticCoordinator by lazy {
        val main = Handler(Looper.getMainLooper())
        createRustDiagnosticCoordinator(GeneratedDiagnosticPort(BuildConfig.MUYON_BRIDGE_PROTOCOL.toUInt(), BuildConfig.MUYON_BRIDGE_SOURCE_SHA)) { deliver ->
            if (Looper.myLooper() == Looper.getMainLooper()) deliver() else main.post { deliver() }
        }
    }
}
