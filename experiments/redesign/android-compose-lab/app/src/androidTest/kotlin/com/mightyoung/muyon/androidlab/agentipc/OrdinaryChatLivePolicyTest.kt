package com.mightyoung.muyon.androidlab.agentipc

import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.nio.file.Files

class OrdinaryChatLivePolicyTest {
    private fun wire(second:Boolean=false)=JSONObject().put("max_tokens",128).put("messages",JSONArray().apply {
        put(JSONObject().put("content",OrdinaryChatProductionConfig.FIRST).put("role","user"))
        if(second){put(JSONObject().put("content","CANARY-4827").put("role","assistant"));put(JSONObject().put("content",OrdinaryChatProductionConfig.SECOND).put("role","user"))}
    }).put("model","deepseek-flash").put("n",1).put("stream",false).put("thinking",JSONObject().put("type","disabled")).toString().toByteArray()
    private fun denied(action:()->Unit){try{action();fail("expected refusal")}catch(_:IllegalArgumentException){}}
    @Test fun fullHistoryAndClosedLiveProof() {
        val first=OrdinaryChatProductionConfig.prove(wire());val second=OrdinaryChatProductionConfig.prove(wire(true))
        assertTrue(second.fullInputTokenUpperBound>first.fullInputTokenUpperBound)
        assertNotEquals(first.payloadSha256,second.payloadSha256)
        assertFalse(OrdinaryChatProductionConfig.verifier.verify(wire(true),first))
        for(change in listOf("extra","thinking","output","model")) {
            val invalid=JSONObject(String(wire()))
            when(change){"extra"->invalid.put("tools",JSONArray());"thinking"->invalid.remove("thinking");"output"->invalid.put("max_tokens",129);else->invalid.put("model","deepseek-chat")}
            denied{OrdinaryChatProductionConfig.prove(invalid.toString().toByteArray())}
        }
    }
    @Test fun credentialsAreOpaqueGenerationBoundAndTemporary() {
        val store=OrdinaryChatTemporaryCredential();val first=store.install("offline-credential-fixture".toCharArray())
        var observed:CharArray?=null
        store.withCopy(first){observed=it;assertTrue(it.any{char->char!='\u0000'})}
        assertTrue(checkNotNull(observed).all{it=='\u0000'})
        val second=store.install("another-offline-credential-fixture".toCharArray())
        assertNotEquals(first.identity,second.identity);assertTrue(second.generation>first.generation)
        try{store.withCopy(first){};fail("old generation accepted")}catch(_:IllegalStateException){}
        store.clear();assertNull(store.current())
    }
    @Test fun androidFilesystemDurabilityAndCandidateSettlement() {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val root=Files.createTempDirectory(context.cacheDir.toPath(),"live-policy-new-root-").toFile()
        try {
            val live=OrdinaryChatLiveInstallation(root,OrdinaryChatTemporaryCredential())
            val bytes=wire();val proof=OrdinaryChatProductionConfig.prove(bytes)
            val permit=live.budget.reserve("offline-first",bytes,proof,"CNY",OrdinaryChatProductionConfig.verifier)
            live.budget.handoff(permit)
            val response=JSONObject().put("id","offline-policy-fixture").put("model","deepseek-flash")
                .put("choices",JSONArray().put(JSONObject().put("index",0).put("finish_reason","stop").put("message",JSONObject().put("role","assistant").put("content","CANARY-4827"))))
                .put("usage",JSONObject().put("prompt_tokens",10).put("completion_tokens",8).put("total_tokens",18)).toString().toByteArray()
            val candidate=live.decode(response,proof,permit);live.writeCandidate("offline-admission",byteArrayOf(1),bytes,candidate)
            assertEquals("pending",live.lookup("offline-admission"))
            live.budget.success(permit,candidate.usage)
            assertEquals("success",live.lookup("offline-admission"))
            assertEquals(permit.reservedMicroCny,live.budget.snapshot().reservedMicroCny)
        } finally {root.deleteRecursively()}
    }
    @Test fun credentialRotationAndPostWriteAuthorityHaveOneLinearizationPoint() {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val root=Files.createTempDirectory(context.cacheDir.toPath(),"live-rotation-new-root-").toFile()
        try {
            val store=OrdinaryChatTemporaryCredential();val live=OrdinaryChatLiveInstallation(root,store)
            val authority=ServiceAdmissionAuthority(ServiceAdmissionAuthority.State(null,null,{_,_->false},{_,_,_->null}))
            authority.installLiveCredential(live,"old-offline-fixture-key".toCharArray())
            val old=checkNotNull(store.current())
            val entered=java.util.concurrent.CountDownLatch(1);val release=java.util.concurrent.CountDownLatch(1);val changed=java.util.concurrent.CountDownLatch(1)
            val failure=java.util.concurrent.atomic.AtomicReference<Throwable?>(null)
            val attempted=java.util.concurrent.CountDownLatch(1)
            val writer=Thread{try{authority.guarded{state->assertEquals(old,state.credential);entered.countDown();check(release.await(5,java.util.concurrent.TimeUnit.SECONDS));assertEquals(old,store.current())}}catch(error:Throwable){failure.compareAndSet(null,error)}}
            writer.start();assertTrue(entered.await(5,java.util.concurrent.TimeUnit.SECONDS))
            val rotate=Thread{try{attempted.countDown();authority.installLiveCredential(live,"new-offline-fixture-key".toCharArray())}catch(error:Throwable){failure.compareAndSet(null,error)}finally{changed.countDown()}}
            rotate.start();assertTrue(attempted.await(5,java.util.concurrent.TimeUnit.SECONDS));assertFalse(changed.await(100,java.util.concurrent.TimeUnit.MILLISECONDS));assertEquals(old,store.current())
            release.countDown();writer.join(5000);rotate.join(5000);assertFalse(writer.isAlive);assertFalse(rotate.isAlive);assertEquals(0L,changed.count);assertNull(failure.get())
            authority.guarded{state->assertEquals(store.current(),state.credential);assertNotEquals(old,state.credential)}
            val current=store.current()
            denied{authority.installLiveCredential(live,charArrayOf('x'))}
            assertEquals(current,store.current());authority.guarded{assertEquals(current,it.credential)}
        } finally {root.deleteRecursively()}
    }
    @Test fun failureDiagnosticsArePrivateBoundedImmutableAndCannotReleaseStoppedBudget() {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val root=Files.createTempDirectory(context.cacheDir.toPath(),"live-diagnostic-new-root-").toFile()
        val hidden=root.toPath().resolveSibling(root.name+"-unavailable")
        try {
            val live=OrdinaryChatLiveInstallation(root,OrdinaryChatTemporaryCredential())
            val bytes=wire();val proof=OrdinaryChatProductionConfig.prove(bytes)
            val permit=live.budget.reserve("diagnostic-offline",bytes,proof,"CNY",OrdinaryChatProductionConfig.verifier)
            live.budget.handoff(permit);live.budget.stop(permit)
            // Root unavailable after durable stop: diagnostic creation fails without changing outcome.
            Files.move(root.toPath(),hidden)
            try {live.recordFailure("admission",OrdinaryChatFailureStage.HTTP_STATUS,401);assertFalse(root.exists())}
            finally {Files.move(hidden,root.toPath())}
            val stopped=live.budget.snapshot();assertTrue(stopped.stopped);assertEquals(1,stopped.attempts)
            assertEquals(permit.reservedMicroCny,stopped.reservedMicroCny)
            assertEquals(listOf("unknown"),stopped.states)
            live.recordFailure("admission",OrdinaryChatFailureStage.HTTP_STATUS,401)
            val file=live.failureFile("admission");val first=file.readText();val value=JSONObject(first)
            assertTrue(file.length() in 1..1024)
            assertEquals(0x180,android.system.Os.stat(file.path).st_mode and 0x1ff)
            assertEquals(setOf("version","admission_sha256","stage","outcome","http_status"),value.keys().asSequence().toSet())
            live.recordFailure("admission",OrdinaryChatFailureStage.HTTP_BODY,200)
            assertEquals(first,file.readText())
            live.recordFailure("invalid-status",OrdinaryChatFailureStage.HTTP_STATUS,999)
            assertFalse(JSONObject(live.failureFile("invalid-status").readText()).has("http_status"))
            assertEquals(stopped,live.budget.snapshot())
            try {live.budget.reserve("no-retry",bytes,proof,"CNY",OrdinaryChatProductionConfig.verifier);fail("stopped budget admitted retry")}
            catch(_:OrdinaryChatCanaryBudget.Refused){}
        } finally {root.deleteRecursively();hidden.toFile().deleteRecursively()}
    }
}
