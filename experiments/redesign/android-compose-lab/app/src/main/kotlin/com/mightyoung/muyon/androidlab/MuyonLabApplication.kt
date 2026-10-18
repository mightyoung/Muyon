package com.mightyoung.muyon.androidlab

import android.app.Application
import android.os.Handler
import android.os.Looper
import com.mightyoung.muyon.androidlab.agentipc.*
import android.content.Context

/** Process ownership is intentional: UI recreation must not release or replace a blocked native slot. */
@Suppress("EXPOSED_FUNCTION_RETURN_TYPE")
open class MuyonLabApplication : Application(), ServiceHostOwnerInstallation {
    // Ordinary offline UI keeps its explicit lab composition. No real authority is inferred.
    override fun serviceHostBinding(serviceContext:Context):ServiceHostBinding=ServiceHostBinding.SyntheticLab
    override fun acquireServiceHost(serviceContext:Context):ServiceHostLease=ServiceHostLease(serviceHostBinding(serviceContext))
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
    val chats:ChatReadPort get()=agents.chats
    val diagnostics: RustDiagnosticCoordinator by lazy {
        val main = Handler(Looper.getMainLooper())
        createRustDiagnosticCoordinator(GeneratedDiagnosticPort(BuildConfig.MUYON_BRIDGE_PROTOCOL.toUInt(), BuildConfig.MUYON_BRIDGE_SOURCE_SHA)) { deliver ->
            if (Looper.myLooper() == Looper.getMainLooper()) deliver() else main.post { deliver() }
        }
    }
}
