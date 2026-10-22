package com.mightyoung.muyon.androidlab.agentipc

import android.app.Activity
import android.content.Context
import android.content.Intent
import com.mightyoung.muyon.androidlab.MuyonLabApplication

/** Each Android process has one Application. Both credential Activity and Service are :agent. */
@Suppress("EXPOSED_FUNCTION_RETURN_TYPE")
class OrdinaryChatLiveApplication:MuyonLabApplication() {
    private val credentials=OrdinaryChatTemporaryCredential()
    private val authority=ServiceAdmissionAuthority(ServiceAdmissionAuthority.State(null,null,{_,_->false},{_,_,_->null}))
    private val processOwner=ServiceAdmissionProcessOwner(authority,ordinaryChat=true)
    private var installation:OrdinaryChatLiveInstallation?=null
    @Synchronized private fun installed(context:Context):OrdinaryChatLiveInstallation = installation ?: OrdinaryChatLiveInstallation(privateAdmissionRoot(context),credentials,authorizedFollowup=true).also{installation=it}
    internal fun installTemporaryCredential(context:Context,input:CharArray) {
        check(android.os.Looper.myLooper()!=android.os.Looper.getMainLooper())
        val live=installed(context)
        authority.installLiveCredential(live,input)
    }
    override fun acquireServiceHost(serviceContext:Context):ServiceHostLease = processOwner.acquire(serviceContext,OrdinaryChatProductionConfig.call)
    override fun useAuthorizedChatFollowup(serviceContext:Context)=OrdinaryChatAuthorizedSession.allowed(serviceContext,installed(serviceContext))
    override fun openChatCredentialEntry(activity:Activity) {
        activity.startActivity(Intent(activity,OrdinaryChatCredentialActivity::class.java))
    }
}
