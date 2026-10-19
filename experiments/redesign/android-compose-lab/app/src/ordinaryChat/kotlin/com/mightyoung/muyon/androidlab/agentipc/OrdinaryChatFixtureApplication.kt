package com.mightyoung.muyon.androidlab.agentipc

import android.content.Context
import com.mightyoung.muyon.androidbridge.*
import com.mightyoung.muyon.androidlab.MuyonLabApplication
import org.json.JSONObject

/** Compile-time, no-network fixture. No user key, paid model, real currency or price is installed. */
@Suppress("EXPOSED_FUNCTION_RETURN_TYPE")
class OrdinaryChatFixtureApplication:MuyonLabApplication() {
    private val call=ServiceOwnerCallBudget(8192uL,1uL,false,false)
    private val owner=ServiceAdmissionProcessOwner(ServiceAdmissionAuthority(facts()),ordinaryChat=true)
    override fun acquireServiceHost(serviceContext:Context)=owner.acquire(serviceContext,call)
    private fun facts():ServiceAdmissionAuthority.State {
        val profile=ServiceOwnerProfile("ordinary-fixture-profile","https://ordinary-chat.invalid/v1/chat/completions","ordinary-fixture-endpoint","synthetic","ordinary-fixture-model",ServiceOwnerLocation.OWN_DEVICE,ServiceOwnerPurpose.CHAT,"synthetic-capability-ref",ServiceOwnerCapabilities(false,false),ServiceOwnerCapabilities(false,false))
        val quota=ServiceOwnerBudget("ordinary-synthetic-epoch-v1","synthetic-byte-bound-v1",2uL,16384uL,2uL)
        val provider=ServiceOwnerProvider(profile,"profile1","policy1","grant1","ordinary-fixture-owner",true,true,quota,true)
        val chat=ServiceOwnerChatAuthority("ordinary-fixture-workspace","*","ordinary-fixture-owner","full-allow","policy1","grant1","USER-TEXT-v1","source1","personal",true,true,true,true,true)
        fun review(bytes:ByteArray):Boolean=try {
            val body=JSONObject(String(bytes,Charsets.UTF_8));val messages=body.getJSONArray("messages");val msg=messages.getJSONObject(0)
            body.keys().asSequence().toSet()==setOf("model","messages","n","stream","max_tokens") && body.getString("model")==profile.model && messages.length()==1 && msg.keys().asSequence().toSet()==setOf("role","content") && msg.getString("role")=="user" && ordinaryTextSupported(msg.getString("content")) && body.getInt("n")==1 && !body.getBoolean("stream") && body.getLong("max_tokens") in 1..1024 && bytes.size<=8192
        }catch(_:Exception){false}
        return ServiceAdmissionAuthority.State(null,provider,{_,bytes->review(bytes)},
            {_,bytes,budget->if(review(bytes) && budget==call && bytes.size.toULong()+1024uL<=budget.maxTokens)"synthetic-total-bound-v1" else null},
            chat,ServiceOwnerCredentialCapability("synthetic-chat-handle",1uL),{bytes->
                check(review(bytes))
                ServiceOwnerChatResponse("离线普通文本响应",32uL,32uL,true)
            })
    }
}
