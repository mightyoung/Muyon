package com.mightyoung.muyon.androidlab.agentipc

import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.androidbridge.*
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/** Real Android durable owner, synthetic transport and control; no network/provider evidence. */
class OrdinaryChatLiveOwnerTest {
    @Test fun cancelledLateAndRejectedCandidatesStopSameOwnersBatchWithoutResend() {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        for(mode in listOf("cancel_before_write","late_after_write","reject_candidate","revoke_before_accept","transport_status","malformed_response","candidate_io")) {
            val root=Files.createTempDirectory(context.cacheDir.toPath(),"live-owner-new-root-").toFile()
            try {
                val credentials=OrdinaryChatTemporaryCredential();credentials.install("offline-owner-no-secret-key".toCharArray())
                val allowed=AtomicBoolean(true);val sends=AtomicInteger();val sent=CountDownLatch(1);val release=CountDownLatch(1)
                var activeAdmission=""
                lateinit var authority:ServiceAdmissionAuthority
                val live=OrdinaryChatLiveInstallation(root,credentials) { bytes,key,poll,authorize ->
                    try {
                        if(mode=="cancel_before_write")allowed.set(false)
                        check(authorize {check(poll());sends.incrementAndGet();sent.countDown()})
                        if(mode=="late_after_write")check(release.await(10,TimeUnit.SECONDS))
                        if(mode=="transport_status")throw OrdinaryChatHttpsFailure(OrdinaryChatFailureStage.HTTP_STATUS,401)
                        if(mode=="malformed_response")return@OrdinaryChatLiveInstallation "sensitive-provider-error-body".toByteArray()
                        if(mode=="candidate_io")assertTrue(File(root,"live-chat-${OrdinaryChatProductionConfig.sha(activeAdmission.toByteArray())}.json").mkdir())
                        JSONObject().put("id","offline-owner-protocol-fixture").put("model","deepseek-flash")
                            .put("choices",JSONArray().put(JSONObject().put("index",0).put("finish_reason","stop").put("message",JSONObject().put("role","assistant").put("content","CANARY-4827"))))
                            .put("usage",JSONObject().put("prompt_tokens",10).put("completion_tokens",8).put("total_tokens",18)).toString().toByteArray()
                    } finally {key.fill('\u0000')}
                }
                val facts=live.facts();authority=ServiceAdmissionAuthority(facts)
                val provider=checkNotNull(facts.provider);val a=checkNotNull(facts.chat);val cap=checkNotNull(facts.credential)
                val binding=ServiceOwnerAdmissionBinding(provider.profile,provider.profileRevision,provider.policyRevision,provider.grantRevision,provider.authorizationOwner,true,true,provider.budget)
                val auth=JSONObject().put("workspace",a.workspace).put("conversation","conversation").put("owner",a.owner).put("mode",a.mode).put("policy_revision",a.policyRevision).put("grant_revision",a.grantRevision).put("input_rule",a.ruleRevision).put("restriction_revision",a.restrictionRevision).put("sensitivity",a.sensitivity).put("output_rule","MODEL-TEXT-v1").put("synthetic",false)
                val ctx=JSONObject().put("authority",auth).put("workspace",a.workspace).put("conversation","conversation").put("input_ref","${"a".repeat(32)}:r1").put("task","task1").put("attempt","attempt1").put("input_version","utf8-exact-v1").put("history_version","ordinary-context-v1").put("history",JSONArray()).toString().toByteArray()
                val bytes=JSONObject().put("max_tokens",128).put("messages",JSONArray().put(JSONObject().put("content",OrdinaryChatProductionConfig.FIRST).put("role","user"))).put("model","deepseek-flash").put("n",1).put("stream",false).put("thinking",JSONObject().put("type","disabled")).toString().toByteArray()
                val control=object:ServiceOwnerRunControl(NoHandle){override fun allowed()=allowed.get()}
                DurableServiceHostOwner(File(root,"owner.sqlite"),authority,ordinaryChat=true).use { owner ->
                    val reservation=checkNotNull(owner.reserveBudget(binding,"r1",bytes,OrdinaryChatProductionConfig.call))
                    assertTrue(owner.bindChatContext(reservation,binding,"r1",bytes,ctx,cap))
                    val admission=checkNotNull(owner.commitAdmission(reservation,binding,"r1",bytes,provider.profile.id,provider.profile.credentialRef))
                    activeAdmission=admission
                    if(mode=="late_after_write") {
                        var result:ServiceOwnerChatResponse?=null
                        val request=Thread{result=owner.exchangeLiveChat(admission,binding,ctx,bytes,cap,control)}
                        request.start();assertTrue(sent.await(10,TimeUnit.SECONDS));allowed.set(false)
                        val reserveDone=CountDownLatch(1);val reserveFailure=java.util.concurrent.atomic.AtomicReference<Throwable?>(null)
                        var secondReservation:String?=null
                        val second=Thread{try{secondReservation=owner.reserveBudget(binding,"r2",bytes,OrdinaryChatProductionConfig.call)}catch(error:Throwable){reserveFailure.set(error)}finally{reserveDone.countDown()}}
                        second.start()
                        try {assertTrue("response wait held the owner lock",reserveDone.await(2,TimeUnit.SECONDS));assertNull(secondReservation);assertNull(reserveFailure.get())}
                        finally {release.countDown();second.join(5000);request.join(10000)}
                        assertFalse(second.isAlive);assertFalse(request.isAlive);assertNull(result)
                    } else {
                        val response=owner.exchangeLiveChat(admission,binding,ctx,bytes,cap,control)
                        if(mode in setOf("cancel_before_write","transport_status","malformed_response","candidate_io"))assertNull(response) else {
                            assertNotNull(response)
                            if(mode=="revoke_before_accept")authority.replace(ServiceAdmissionAuthority.State(facts.scope,facts.provider,facts.payloadReview,facts.budgetProof,a.copy(active=false),cap,null,live))
                            if(mode=="reject_candidate")assertTrue(owner.settleChat(admission,false)) else assertFalse(owner.settleChat(admission,true))
                            assertFalse(owner.settleChat(admission,true))
                        }
                    }
                    val snapshot=live.budget.snapshot();assertTrue(snapshot.stopped);assertTrue(snapshot.reservedMicroCny>0)
                    val diagnostic=live.failureFile(admission)
                    val recorded=if(mode in setOf("reject_candidate","revoke_before_accept"))null else {
                        val text=diagnostic.readText();assertTrue(diagnostic.length()<=1024)
                        val value=JSONObject(text)
                        val expectedStage=when(mode){"transport_status"->"HTTP_STATUS";"malformed_response"->"RESPONSE_VALIDATION";"candidate_io"->"CANDIDATE_PERSIST";else->"OWNER_AUTHORITY"}
                        assertEquals(expectedStage,value.getString("stage"));assertEquals("unknown",value.getString("outcome"))
                        assertEquals(OrdinaryChatProductionConfig.sha(admission.toByteArray()),value.getString("admission_sha256"))
                        assertEquals(if(mode=="transport_status")401 else -1,value.optInt("http_status",-1))
                        assertFalse(text.contains("sensitive-provider-error-body"));assertFalse(text.contains("offline-owner-no-secret-key"))
                        text
                    }
                    assertEquals(if(mode=="cancel_before_write")0 else 1,sends.get())
                    assertNull(owner.exchangeLiveChat(admission,binding,ctx,bytes,cap,control))
                    if(recorded!=null)assertEquals(recorded,diagnostic.readText())
                    else assertFalse(diagnostic.exists())
                    assertNull(owner.reserveBudget(binding,"r3",bytes,OrdinaryChatProductionConfig.call))
                    assertEquals(snapshot,live.budget.snapshot())
                    assertEquals(if(mode=="cancel_before_write")0 else 1,sends.get())
                }
            } finally {root.deleteRecursively()}
        }
    }
}
