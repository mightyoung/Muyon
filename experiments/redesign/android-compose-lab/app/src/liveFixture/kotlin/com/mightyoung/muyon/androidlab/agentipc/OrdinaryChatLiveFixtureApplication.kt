package com.mightyoung.muyon.androidlab.agentipc

import android.content.Context
import com.mightyoung.muyon.androidlab.MuyonLabApplication
import com.mightyoung.muyon.androidlab.BuildConfig
import java.io.File
import org.json.JSONArray
import org.json.JSONObject

/** Socket-free live-PROTOCOL fixture. Responses/usage are synthetic, never vendor acceptance. */
@Suppress("EXPOSED_FUNCTION_RETURN_TYPE")
class OrdinaryChatLiveFixtureApplication:MuyonLabApplication() {
    private val credentials=OrdinaryChatTemporaryCredential()
    private val authority=ServiceAdmissionAuthority(ServiceAdmissionAuthority.State(null,null,{_,_->false},{_,_,_->null}))
    private val owner=ServiceAdmissionProcessOwner(authority,ordinaryChat=true)
    private var installation:OrdinaryChatLiveInstallation?=null
    @Synchronized private fun installed(serviceContext:Context):OrdinaryChatLiveInstallation {
        installation?.let{return it}
        val root=privateAdmissionRoot(serviceContext)
        val followup=BuildConfig.MUYON_AUTHORIZED_FOLLOWUP
        if(followup && !File(root,"ordinary-chat-canary-20261019.lock").exists()) {
            check(root.listFiles()?.isEmpty()==true)
            // Reproduce public, synthetic prior evidence only in this no-INTERNET fixture.
            val prior=OrdinaryChatCanaryBudget.provisionNewBatch(root.toPath())
            val wire="""{"max_tokens":128,"messages":[{"content":"For this synthetic test, the code is CANARY-4827. Answer with that code only.","role":"user"}],"model":"deepseek-flash","n":1,"stream":false,"thinking":{"type":"disabled"}}""".toByteArray()
            val permit=prior.reserve("chat_eb1eeb36ef9748c7900f5eb810622d00",wire,OrdinaryChatProductionConfig.prove(wire),"CNY",OrdinaryChatProductionConfig.verifier)
            prior.handoff(permit);prior.stop(permit)
        }
            credentials.install("offline-protocol-fixture-not-a-secret".toCharArray())
            val live=OrdinaryChatLiveInstallation(root,credentials,authorizedFollowup=followup) { bytes,key,allowed,authorize ->
                try {
                    check(allowed());var wrote=false;check(authorize{check(!wrote);wrote=true});check(wrote)
                    val input=OrdinaryChatProductionConfig.prove(bytes,followup)
                    val answer=if(followup)"CANARY-7391" else "CANARY-4827"
                    JSONObject().put("id","offline-live-protocol-fixture").put("model","deepseek-flash")
                        .put("choices",JSONArray().put(JSONObject().put("index",0).put("finish_reason","stop").put("message",JSONObject().put("role","assistant").put("content",answer))))
                        .put("usage",JSONObject().put("prompt_tokens",input.fullInputTokenUpperBound).put("completion_tokens",8).put("total_tokens",input.fullInputTokenUpperBound+8)).toString().toByteArray()
                } finally {key.fill('\u0000')}
            }
            authority.replace(live.facts());installation=live
            return live
    }
    override fun useAuthorizedChatFollowup(serviceContext:Context)=BuildConfig.MUYON_AUTHORIZED_FOLLOWUP && OrdinaryChatAuthorizedSession.allowed(serviceContext,installed(serviceContext))
    override fun acquireServiceHost(serviceContext:Context):ServiceHostLease {
        installed(serviceContext)
        return owner.acquire(serviceContext,OrdinaryChatProductionConfig.call)
    }
}
