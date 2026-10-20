package com.mightyoung.muyon.androidlab.agentipc

import com.mightyoung.muyon.androidbridge.*
import org.json.JSONObject
import java.io.File
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption

/** Installed in the existing owner, never a second owner or a SearchHost. */
internal class OrdinaryChatLiveInstallation(val root:File,val credentials:OrdinaryChatTemporaryCredential,
    private val authorizedFollowup:Boolean=false,
    val exchange:(ByteArray,CharArray,()->Boolean,((()->Unit)->Boolean))->ByteArray=OrdinaryChatHttpsTransport()::exchange) {
    val budget:OrdinaryChatCanaryBudget
    val verifier=if(authorizedFollowup)OrdinaryChatProductionConfig.followupVerifier else OrdinaryChatProductionConfig.verifier
    fun prove(payload:ByteArray)=OrdinaryChatProductionConfig.prove(payload,authorizedFollowup)
    init {
        val marker=root.toPath().resolve("ordinary-chat-canary-20261019.lock")
        budget=if(authorizedFollowup)OrdinaryChatCanaryBudget.openAuthorizedFollowup(root.toPath())
            else if(Files.exists(marker))OrdinaryChatCanaryBudget.openExisting(root.toPath()) else OrdinaryChatCanaryBudget.provisionNewBatch(root.toPath())
    }
    fun facts(cap:ServiceOwnerCredentialCapability=credentials.current() ?: error("chat_credential_unavailable")):ServiceAdmissionAuthority.State {
        val grant=if(authorizedFollowup)"canary-followup-grant-v1" else "canary-grant-v1"
        val quota=ServiceOwnerBudget(budget.batchIdentity,OrdinaryChatProductionConfig.QUOTA_PROOF,2uL,33024uL,budget.ceilingMicroCny.toULong())
        val provider=ServiceOwnerProvider(OrdinaryChatProductionConfig.profile,"live-profile-v1","canary-policy-v1",grant,"ordinary-live-owner",true,true,quota,true)
        val authority=ServiceOwnerChatAuthority("ordinary-live-synthetic-workspace","*","ordinary-live-owner","full-allow","canary-policy-v1",grant,"USER-TEXT-v1","synthetic-only-v1","personal",true,true,true,true,false)
        return ServiceAdmissionAuthority.State(null,provider,{_,bytes->try{prove(bytes);true}catch(_:Exception){false}},
            {_,bytes,call->try{if(call!=OrdinaryChatProductionConfig.call)null else {prove(bytes);OrdinaryChatProductionConfig.QUOTA_PROOF}}catch(_:Exception){null}},authority,cap,null,this)
    }
    data class Candidate(val permit:OrdinaryChatCanaryBudget.Permit,val response:ServiceOwnerChatResponse,val usage:OrdinaryChatCanaryBudget.Usage,val providerMetadata:JSONObject)
    fun candidateFile(admission:String)=File(root,"live-chat-${OrdinaryChatProductionConfig.sha(admission.toByteArray())}.json")
    fun failureFile(admission:String)=File(root,"live-chat-failure-${OrdinaryChatProductionConfig.sha(admission.toByteArray())}.json")
    /** Diagnostic only: never a settlement, never raw exception/response/credential text. */
    fun recordFailure(admission:String,stage:OrdinaryChatFailureStage,httpStatus:Int?) {
        var temporary:java.nio.file.Path?=null
        try {
            val path=failureFile(admission).toPath()
            if(Files.exists(path,LinkOption.NOFOLLOW_LINKS))return
            val value=JSONObject().put("version","ordinary-live-failure-v1")
                .put("admission_sha256",OrdinaryChatProductionConfig.sha(admission.toByteArray()))
                .put("stage",stage.name).put("outcome","unknown")
            if(httpStatus!=null && httpStatus in 100..599)value.put("http_status",httpStatus)
            val bytes=value.toString().toByteArray(Charsets.UTF_8);require(bytes.size<=1024)
            val temp=Files.createTempFile(root.toPath(),".live-failure-",".pending");temporary=temp
            FileChannel.open(temp,StandardOpenOption.WRITE).use { channel->
                val buffer=ByteBuffer.wrap(bytes);while(buffer.hasRemaining())channel.write(buffer);channel.force(true)
            }
            Files.move(temp,path,StandardCopyOption.ATOMIC_MOVE)
            FileChannel.open(root.toPath(),StandardOpenOption.READ).use{it.force(true)}
        } catch(_:Exception) {
            // Stopping the durable budget and the caller's unknown result take precedence.
        } finally {try{temporary?.let{Files.deleteIfExists(it)}}catch(_:Exception){}}
    }
    /** Only synthetic prompt/answer/usage are persisted, never headers or credential material. */
    fun writeCandidate(admission:String,context:ByteArray,payload:ByteArray,candidate:Candidate) {
        val value=JSONObject().put("version","ordinary-live-candidate-v1").put("admission",admission)
            .put("request",candidate.permit.request).put("payload_sha256",candidate.permit.payloadSha256)
            .put("reserved_micro_cny",candidate.permit.reservedMicroCny).put("context_sha256",OrdinaryChatProductionConfig.sha(context))
            .put("payload",JSONObject(String(payload,Charsets.UTF_8))).put("answer",candidate.response.answer)
            .put("input_tokens",candidate.response.inputTokens.toLong()).put("output_tokens",candidate.response.outputTokens.toLong())
            .put("cost_upper_micro_cny",candidate.usage.reportedFeeMicroCny).put("currency","CNY")
            .put("price_rule",OrdinaryChatProductionConfig.PRICE).put("counting_rule",OrdinaryChatProductionConfig.COUNTING)
            .put("provider",candidate.providerMetadata).put("received_at_epoch_ms",System.currentTimeMillis())
        val bytes=value.toString().toByteArray(Charsets.UTF_8);require(bytes.size<=32768)
        val temp=Files.createTempFile(root.toPath(),".live-candidate-",".pending")
        try {
            FileChannel.open(temp,StandardOpenOption.WRITE).use { channel->val buffer=ByteBuffer.wrap(bytes);while(buffer.hasRemaining())channel.write(buffer);channel.force(true) }
            Files.move(temp,candidateFile(admission).toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING)
            FileChannel.open(root.toPath(),StandardOpenOption.READ).use{it.force(true)}
        } finally {Files.deleteIfExists(temp)}
    }
    fun lookup(admission:String):String?=try {
        val path=candidateFile(admission).toPath()
        require(!Files.isSymbolicLink(path) && Files.size(path) in 1..32768)
        val bytes=Files.newInputStream(path).use{input->
            val buffer=ByteArray(32769);var size=0
            while(size<buffer.size){val count=input.read(buffer,size,buffer.size-size);if(count<0)break;size+=count}
            require(size<=32768);buffer.copyOf(size)
        }
        val candidate=JSONObject(String(bytes,Charsets.UTF_8))
        require(candidate.getString("admission")==admission && candidate.getString("version")=="ordinary-live-candidate-v1")
        val record=budget.record(candidate.getString("request")) ?: return null
        require(record.permit.payloadSha256==candidate.getString("payload_sha256") && record.permit.reservedMicroCny==candidate.getLong("reserved_micro_cny"))
        if(record.state=="success") {
            val usage=checkNotNull(record.usage)
            require(usage.inputTokens==candidate.getLong("input_tokens") && usage.outputTokens==candidate.getLong("output_tokens") && usage.reportedFeeMicroCny==candidate.getLong("cost_upper_micro_cny"))
            "success"
        } else if(record.state=="unknown")"unknown" else "pending"
    } catch(_:Exception){null}
    fun decode(bytes:ByteArray,proof:OrdinaryChatCanaryBudget.TokenProof,permit:OrdinaryChatCanaryBudget.Permit):Candidate {
        require(bytes.size in 1..65536)
        val text=Charsets.UTF_8.newDecoder().onMalformedInput(java.nio.charset.CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
        val value=JSONObject(text)
        require(value.get("model") in setOf("deepseek-flash","DeepSeek-V4.1-Flash-1017"))
        require(value.getString("id").isNotBlank() && value.getString("id").length<=512)
        val choices=value.getJSONArray("choices");require(choices.length()==1)
        val choice=choices.getJSONObject(0)
        require(OrdinaryChatProductionConfig.integer(choice,"index")==0L && choice.get("finish_reason")=="stop")
        val message=choice.getJSONObject("message")
        require(message.get("role")=="assistant" && (!message.has("tool_calls") || message.isNull("tool_calls")) && (!message.has("function_call") || message.isNull("function_call")))
        require(!message.has("reasoning_content") || message.isNull("reasoning_content") || message.get("reasoning_content")=="")
        val answer=message.get("content") as? String ?: error("chat_response_refused")
        require(ordinaryTextSupported(answer))
        val usage=value.getJSONObject("usage")
        val input=OrdinaryChatProductionConfig.integer(usage,"prompt_tokens")
        val output=OrdinaryChatProductionConfig.integer(usage,"completion_tokens")
        require(input in 1..proof.fullInputTokenUpperBound && output in 1..128 && OrdinaryChatProductionConfig.integer(usage,"total_tokens")==input+output)
        // Cache/idle discounts never increase this peak all-miss bound. It is not an invoice.
        val cost=Math.addExact(Math.multiplyExact(input,2),Math.multiplyExact(output,8))
        require(cost<=permit.reservedMicroCny)
        val details=usage.optJSONObject("completion_tokens_details")
        if(details?.has("reasoning_tokens")==true)require(OrdinaryChatProductionConfig.integer(details,"reasoning_tokens")==0L)
        val metadata=JSONObject().put("id",value.getString("id")).put("model",value.getString("model")).put("finish_reason","stop").put("usage",JSONObject(usage.toString()))
        return Candidate(permit,ServiceOwnerChatResponse(answer,input.toULong(),output.toULong(),false),OrdinaryChatCanaryBudget.Usage(input,output,cost,"CNY"),metadata)
    }
}
