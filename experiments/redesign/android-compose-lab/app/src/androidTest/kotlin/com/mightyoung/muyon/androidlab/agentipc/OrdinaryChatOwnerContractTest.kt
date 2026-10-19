package com.mightyoung.muyon.androidlab.agentipc

import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.androidbridge.*
import org.json.JSONObject
import org.json.JSONArray
import android.database.sqlite.SQLiteDatabase
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
        verifyHistoryGuard()
    }

    /** Three proven turns, then corrupt an ancestor after pinning: final guard must deny. */
    private fun verifyHistoryGuard() {
        val p=ServiceOwnerProfile("history-p","https://ordinary.invalid/v1/chat/completions","endpoint","synthetic","model",ServiceOwnerLocation.OWN_DEVICE,ServiceOwnerPurpose.CHAT,"ref",ServiceOwnerCapabilities(false,false),ServiceOwnerCapabilities(false,false))
        val budget=ServiceOwnerBudget("history-epoch","synthetic-proof",4uL,32768uL,4uL)
        val b=ServiceOwnerAdmissionBinding(p,"profile1","policy1","grant1","owner",true,true,budget)
        val chat=ServiceOwnerChatAuthority("workspace","*","owner","full-allow","policy1","grant1","USER-TEXT-v1","source1","personal",true,true,true,true,true)
        val cap=ServiceOwnerCredentialCapability("synthetic-history-handle",1uL);val call=ServiceOwnerCallBudget(8192uL,1uL,false,false)
        var sends=0
        val facts=ServiceAdmissionAuthority.State(null,ServiceOwnerProvider(p,b.profileRevision,b.policyRevision,b.grantRevision,b.authorizationOwner,true,true,budget,true),
            {_,bytes->bytes.size in 1..8192},{_,bytes,cost->if(cost==call && bytes.size+1024<=8192)"synthetic-full-body-proof" else null},chat,cap,
            {bytes->sends++;ServiceOwnerChatResponse("plain reply",bytes.size.toULong(),11uL,true)})
        val authority=ServiceAdmissionAuthority(facts)
        val file=File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir,"ordinary-history-owner-new-${UUID.randomUUID()}.sqlite")
        fun auth()=JSONObject().put("workspace","workspace").put("conversation","conversation").put("owner","owner").put("mode","full-allow").put("policy_revision","policy1").put("grant_revision","grant1").put("input_rule","USER-TEXT-v1").put("restriction_revision","source1").put("sensitivity","personal").put("output_rule","MODEL-TEXT-v1").put("synthetic",true)
        fun context(request:String,run:String,history:JSONArray)=JSONObject().put("authority",auth()).put("workspace","workspace").put("conversation","conversation").put("input_ref","$run:$request").put("task","task-$request").put("attempt","attempt-$request").put("input_version","utf8-exact-v1").put("history_version","ordinary-context-v1").put("history",history)
        fun bytes(o:JSONObject)=o.toString().toByteArray(Charsets.UTF_8)
        fun message(role:String,text:String)=JSONObject().put("role",role).put("content",text)
        fun wire(history:JSONArray,current:String):ByteArray {
            val messages=JSONArray()
            for(i in 0 until history.length()){val u=history.getJSONObject(i);messages.put(message("user",u.getString("user")));messages.put(message("assistant",u.getString("answer")))}
            messages.put(message("user",current))
            return bytes(JSONObject().put("model","model").put("messages",messages).put("n",1).put("stream",false).put("max_tokens",1024))
        }
        fun unit(request:String,run:String,receipt:String,user:String,ancestors:JSONArray)=JSONObject().put("request",request).put("run",run).put("epoch","e".repeat(32)).put("build","c".repeat(40)).put("task","task-$request").put("attempt","attempt-$request").put("input_ref","$run:$request").put("receipt",receipt).put("authority",auth()).put("user",user).put("answer","plain reply").put("ancestors",ancestors)
        DurableServiceHostOwner(file,authority,ordinaryChat=true).use { o->
            val runA="a".repeat(32);val empty=JSONArray();val firstBody=wire(empty,"first")
            val firstContext=context("h1",runA,empty)
            val first=checkNotNull(o.reserveBudget(b,"h1",firstBody,call));assertTrue(o.bindChatContext(first,b,"h1",firstBody,bytes(firstContext),cap))
            val admissionA=checkNotNull(o.commitAdmission(first,b,"h1",firstBody,p.id,p.credentialRef));assertNotNull(o.exchangeChat(admissionA,b,bytes(firstContext),firstBody,cap))
            val unitA=unit("h1",runA,admissionA,"first",JSONArray());val historyA=JSONArray().put(unitA)
            val runB="b".repeat(32);val secondBody=wire(historyA,"second");val secondContext=context("h2",runB,historyA)
            val second=checkNotNull(o.reserveBudget(b,"h2",secondBody,call));assertTrue(o.bindChatContext(second,b,"h2",secondBody,bytes(secondContext),cap))
            val admissionB=checkNotNull(o.commitAdmission(second,b,"h2",secondBody,p.id,p.credentialRef));assertNotNull(o.exchangeChat(admissionB,b,bytes(secondContext),secondBody,cap));assertEquals(2,sends)
            val unitB=unit("h2",runB,admissionB,"second",JSONArray().put(runA));val both=JSONArray().put(unitA).put(unitB)
            val thirdContext=context("h3","d".repeat(32),both);val thirdBody=wire(both,"third")
            val wrongWire=JSONObject(String(thirdBody,Charsets.UTF_8));wrongWire.getJSONArray("messages").getJSONObject(1).put("content","unbound history answer")
            val wrong=checkNotNull(o.reserveBudget(b,"wrong",bytes(wrongWire),call))
            val wrongContext=context("wrong","f".repeat(32),both)
            assertFalse("wire history must equal every frozen unit",o.bindChatContext(wrong,b,"wrong",bytes(wrongWire),bytes(wrongContext),cap))
            val third=checkNotNull(o.reserveBudget(b,"h3",thirdBody,call))
            for(change in listOf("missing_ancestor","user","answer_credential","task","receipt","authority","partial_version","legacy_downgrade")) {
                val bad=JSONObject(thirdContext.toString());val source=bad.getJSONArray("history").getJSONObject(0)
                when(change) {
                    "missing_ancestor"->bad.put("history",JSONArray().put(unitB))
                    "user"->source.put("user","changed user")
                    "answer_credential"->source.put("answer","Bearer synthetic-history-canary")
                    "task"->source.put("task","changed-task")
                    "receipt"->source.put("receipt","not-an-admission")
                    "authority"->source.getJSONObject("authority").put("sensitivity","commercial")
                    "partial_version"->bad.remove("history_version")
                    "legacy_downgrade"->{bad.remove("history_version");bad.remove("history")}
                }
                assertFalse(change,o.bindChatContext(third,b,"h3",thirdBody,bytes(bad),cap))
            }
            assertTrue(o.bindChatContext(third,b,"h3",thirdBody,bytes(thirdContext),cap))
            val admissionC=checkNotNull(o.commitAdmission(third,b,"h3",thirdBody,p.id,p.credentialRef))
            // Only this newly-created synthetic owner file is corrupted. No old task/HTTP/reopen.
            SQLiteDatabase.openDatabase(file.path,null,SQLiteDatabase.OPEN_READWRITE).use { db->
                db.execSQL("UPDATE chat_attempts SET context=? WHERE id=?",arrayOf(bytes(JSONObject(firstContext.toString()).put("task","changed-after-pin")),admissionA))
            }
            assertNull("ancestor changed after pin must fail at guarded handoff",o.exchangeChat(admissionC,b,bytes(thirdContext),thirdBody,cap));assertEquals(2,sends)
            SQLiteDatabase.openDatabase(file.path,null,SQLiteDatabase.OPEN_READONLY).use { db->db.rawQuery("SELECT COUNT(*) FROM chat_attempts",null).use { rows->check(rows.moveToFirst());assertEquals(2,rows.getInt(0))} }
        }
    }
}
