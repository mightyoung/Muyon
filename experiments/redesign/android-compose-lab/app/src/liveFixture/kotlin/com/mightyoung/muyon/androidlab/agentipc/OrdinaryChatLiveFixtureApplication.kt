package com.mightyoung.muyon.androidlab.agentipc

import android.content.Context
import com.mightyoung.muyon.androidlab.MuyonLabApplication
import org.json.JSONArray
import org.json.JSONObject

/** Socket-free live-PROTOCOL fixture. Responses/usage are synthetic, never vendor acceptance. */
@Suppress("EXPOSED_FUNCTION_RETURN_TYPE")
class OrdinaryChatLiveFixtureApplication:MuyonLabApplication() {
    private val credentials=OrdinaryChatTemporaryCredential()
    private val authority=ServiceAdmissionAuthority(ServiceAdmissionAuthority.State(null,null,{_,_->false},{_,_,_->null}))
    private val owner=ServiceAdmissionProcessOwner(authority,ordinaryChat=true)
    private var installed=false
    override fun acquireServiceHost(serviceContext:Context):ServiceHostLease {
        if(!installed) {
            credentials.install("offline-protocol-fixture-not-a-secret".toCharArray())
            val live=OrdinaryChatLiveInstallation(privateAdmissionRoot(serviceContext),credentials) { bytes,key,allowed,authorize ->
                try {
                    check(allowed());var wrote=false;check(authorize{check(!wrote);wrote=true});check(wrote)
                    val input=OrdinaryChatProductionConfig.prove(bytes)
                    JSONObject().put("id","offline-live-protocol-fixture").put("model","deepseek-flash")
                        .put("choices",JSONArray().put(JSONObject().put("index",0).put("finish_reason","stop").put("message",JSONObject().put("role","assistant").put("content","CANARY-4827"))))
                        .put("usage",JSONObject().put("prompt_tokens",input.fullInputTokenUpperBound).put("completion_tokens",8).put("total_tokens",input.fullInputTokenUpperBound+8)).toString().toByteArray()
                } finally {key.fill('\u0000')}
            }
            authority.replace(live.facts());installed=true
        }
        return owner.acquire(serviceContext,OrdinaryChatProductionConfig.call)
    }
}
