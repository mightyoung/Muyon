package com.mightyoung.muyon.androidlab.agentipc

import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.androidbridge.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.UUID

/** Only new v2 files and an in-memory fake. Directly tests the same durable owner used by Service. */
class OrdinaryChatOwnerContractTest {
    @Test fun pinnedContextGenerationAndOneShotAttemptAreEnforcedBySameOwner() {
        val p=ServiceOwnerProfile("p","https://ordinary.invalid/v1/chat/completions","endpoint","synthetic","model",ServiceOwnerLocation.OWN_DEVICE,ServiceOwnerPurpose.CHAT,"ref",ServiceOwnerCapabilities(false,false),ServiceOwnerCapabilities(false,false))
        val b=ServiceOwnerAdmissionBinding(p,"profile1","policy1","grant1","owner",true,true,ServiceOwnerBudget("epoch","synthetic-proof",4uL,32768uL,4uL))
        val chat=ServiceOwnerChatAuthority("workspace","*","owner","full-allow","policy1","grant1","USER-TEXT-v1","source1","personal",true,true,true,true,true)
        val cap=ServiceOwnerCredentialCapability("synthetic-handle",1uL)
        val call=ServiceOwnerCallBudget(8192uL,1uL,false,false)
        val payload="""{"model":"model","messages":[{"role":"user","content":"hello"}],"n":1,"stream":false,"max_tokens":1024}""".toByteArray(Charsets.UTF_8)
        var sends=0
        fun facts(c:ServiceOwnerCredentialCapability=cap)=ServiceAdmissionAuthority.State(null,ServiceOwnerProvider(p,b.profileRevision,b.policyRevision,b.grantRevision,b.authorizationOwner,true,true,b.budget,true),{binding,bytes->binding==b && bytes.contentEquals(payload)},{binding,bytes,budget->if(binding==b && bytes.contentEquals(payload) && budget==call)"exact-synthetic-proof" else null},chat,c,{bytes->check(bytes.contentEquals(payload));sends++;ServiceOwnerChatResponse("plain reply",1uL,1uL,true)})
        val authority=ServiceAdmissionAuthority(facts())
        val file=File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir,"ordinary-owner-new-${UUID.randomUUID()}.sqlite")
        fun context(request:String)=JSONObject().put("authority",JSONObject().put("workspace","workspace").put("conversation","conversation").put("owner","owner").put("mode","full-allow").put("policy_revision","policy1").put("grant_revision","grant1").put("input_rule","USER-TEXT-v1").put("restriction_revision","source1").put("sensitivity","personal").put("output_rule","MODEL-TEXT-v1").put("synthetic",true)).put("workspace","workspace").put("conversation","conversation").put("input_ref","run:$request").put("task","task1").put("attempt","attempt1").put("input_version","utf8-exact-v1").toString().toByteArray(Charsets.UTF_8)
        DurableServiceHostOwner(file,authority,ordinaryChat=true).use { o->
            val first=checkNotNull(o.reserveBudget(b,"r1",payload,call))
            assertNull("ordinary admission cannot skip context pin",o.commitAdmission(first,b,"r1",payload,p.id,p.credentialRef))
            val ctx=context("r1")
            assertTrue(o.bindChatContext(first,b,"r1",payload,ctx,cap))
            assertFalse("context is immutable",o.bindChatContext(first,b,"r1",payload,context("changed"),cap))
            val admitted=checkNotNull(o.commitAdmission(first,b,"r1",payload,p.id,p.credentialRef))
            for(field in listOf("task","attempt","input_ref","conversation")) {
                val changed=JSONObject(String(ctx,Charsets.UTF_8)).put(field,"changed").toString().toByteArray(Charsets.UTF_8)
                assertNull("changed $field",o.exchangeChat(admitted,b,changed,payload,cap))
            }
            assertNull(o.exchangeChat(admitted,b,ctx,payload+0,cap))
            assertNull(o.exchangeChat(admitted,b,ctx,payload,cap.copy(generation=2uL)))
            assertNotNull(o.exchangeChat(admitted,b,ctx,payload,cap))
            assertNull("one-shot attempt",o.exchangeChat(admitted,b,ctx,payload,cap));assertEquals(1,sends)
            val second=checkNotNull(o.reserveBudget(b,"r2",payload,call));assertTrue(o.bindChatContext(second,b,"r2",payload,context("r2"),cap))
            authority.replace(facts(cap.copy(generation=2uL)))
            assertNull("rotation denies commit",o.commitAdmission(second,b,"r2",payload,p.id,p.credentialRef))
            assertEquals(1,sends)
        }
    }
}
