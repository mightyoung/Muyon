package com.mightyoung.muyon.androidlab.agentipc

import com.mightyoung.muyon.androidbridge.*
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest

/** Trusted, chat-only installation. No endpoint/model or token-count input from UI. */
internal object OrdinaryChatProductionConfig {
    const val MODEL = "deepseek-flash"
    const val ENDPOINT = "https://api.deepseek.com/chat/completions"
    const val PROFILE = "ordinary-deepseek-flash-canary"
    const val QUOTA_PROOF = "deepseek-flash-1017-full-prompt-bound-cny-v1"
    const val COUNTING = "deepseek-flash-1017-bpe-upper-v1"
    const val PRICE = "deepseek-cny-peak-miss-20261020-v1"
    const val FIRST = "For this synthetic test, the code is CANARY-4827. Answer with that code only."
    const val SECOND = "Repeat the code from my first message. Answer with the code only."
    val call = ServiceOwnerCallBudget(16512uL,33792uL,false,false)
    val profile = ServiceOwnerProfile(PROFILE,ENDPOINT,"deepseek-https-chat-v1","deepseek",MODEL,
        ServiceOwnerLocation.REMOTE,ServiceOwnerPurpose.CHAT,"temporary-chat-capability",
        ServiceOwnerCapabilities(false,false),ServiceOwnerCapabilities(false,false))

    /** Trust basis: the current provider-declared 1017 model uses its published reference format.
     * Re-render all history with the pinned encoder; no JSON-byte synthetic accounting.
     */
    fun prove(payload:ByteArray):OrdinaryChatCanaryBudget.TokenProof {
        require(payload.size in 1..8192)
        val body = parse(payload)
        require(body.keys().asSequence().toSet()==setOf("model","messages","n","stream","max_tokens","thinking"))
        require(body.get("model")==MODEL && integer(body,"n")==1L && body.get("stream")==false && integer(body,"max_tokens")==128L)
        val thinking=body.getJSONObject("thinking")
        require(thinking.keys().asSequence().toSet()==setOf("type") && thinking.get("type")=="disabled")
        val messages=body.getJSONArray("messages")
        require(messages.length() in 1..5 && messages.length()%2==1)
        val input=(0 until messages.length()).map { index ->
            val msg=messages.getJSONObject(index)
            require(msg.keys().asSequence().toSet()==setOf("role","content"))
            require(msg.get("role")==if(index%2==0)"user" else "assistant")
            val text=msg.get("content") as? String ?: error("chat_payload_refused")
            require(ordinaryTextSupported(text))
            OrdinaryChatReferenceTokenBound.Message(msg.getString("role"),text)
        }
        val bound=OrdinaryChatReferenceTokenBound.render(MODEL,input,true)
        require(input.first().content==FIRST && input.indices.filter{it>0 && it%2==0}.all{input[it].content==SECOND})
        return OrdinaryChatCanaryBudget.TokenProof(QUOTA_PROOF,sha(payload),bound.publishedModelInputTokenUpperBound)
    }
    val verifier=OrdinaryChatCanaryBudget.FullPayloadProofVerifier { payload,proof ->
        try { prove(payload)==proof } catch(_:Exception) { false }
    }
    fun parse(bytes:ByteArray):JSONObject {
        val text=Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
        val body=JSONObject(text)
        // Rust's canonical encoder supplies this exact form. Reject duplicate keys/trailing data.
        require(body.toString()==text)
        return body
    }
    fun integer(body:JSONObject,key:String):Long {
        val value=body.get(key)
        require(value is Int || value is Long)
        return (value as Number).toLong()
    }
    fun sha(bytes:ByteArray)=MessageDigest.getInstance("SHA-256").digest(bytes).joinToString(""){"%02x".format(it)}
}
