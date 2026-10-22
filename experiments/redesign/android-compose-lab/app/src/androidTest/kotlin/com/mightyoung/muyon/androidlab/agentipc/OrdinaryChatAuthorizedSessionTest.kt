package com.mightyoung.muyon.androidlab.agentipc

import android.system.Os
import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.androidlab.MuyonLabApplication
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.file.Files

/** Metadata/proof gates only; no socket, credential, native initialization or real app data. */
class OrdinaryChatAuthorizedSessionTest {
    private fun refused(action:()->Unit){try{action();fail("missing/invalid authorized state accepted")}catch(_:Exception){}}
    @Test fun defaultApplicationKeepsOriginalSessionAndAttemptedSessionCannotBeRecreated() {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        assertFalse(MuyonLabApplication().useAuthorizedChatFollowup(context))
        val parent=Files.createTempDirectory(context.cacheDir.toPath(),"authorized-session-metadata-").toFile()
        try {
            val root=File(parent,OrdinaryChatAuthorizedSession.ROOT_NAME)
            OrdinaryChatAuthorizedSession.validateExisting(parent,false)
            assertFalse(root.exists())
            refused{OrdinaryChatAuthorizedSession.validateExisting(parent,true)} // missing outer
            assertTrue(root.mkdir());Os.chmod(root.path,448)
            refused{OrdinaryChatAuthorizedSession.validateExisting(parent,true)} // missing namespace
            val namespace=File(root,"native-agent-service-v1");assertTrue(namespace.mkdir());Os.chmod(namespace.path,448)
            refused{OrdinaryChatAuthorizedSession.validateExisting(parent,true)} // missing index
            val index=File(namespace,"index.db");index.writeText("synthetic-metadata-only");Os.chmod(index.path,384)
            OrdinaryChatAuthorizedSession.validateExisting(parent,true)
            Os.chmod(index.path,420);refused{OrdinaryChatAuthorizedSession.validateExisting(parent,true)}
            Os.chmod(index.path,384);Os.chmod(namespace.path,493);refused{OrdinaryChatAuthorizedSession.validateExisting(parent,true)}
            Os.chmod(namespace.path,448);assertTrue(index.delete());assertTrue(index.mkdir())
            refused{OrdinaryChatAuthorizedSession.validateExisting(parent,true)}
            assertTrue(index.delete());val other=File(namespace,"other");other.writeText("synthetic");Os.chmod(other.path,384)
            Os.symlink(other.path,index.path);refused{OrdinaryChatAuthorizedSession.validateExisting(parent,true)}
        } finally {parent.deleteRecursively()}
    }
    @Test fun authorizedProofAndRemainingCeilingDoNotReopenOriginalUnknown() {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val parent=Files.createTempDirectory(context.cacheDir.toPath(),"authorized-session-budget-").toFile()
        try {
            val root=File(parent,"agent-admission-root");assertTrue(root.mkdir());Os.chmod(root.path,448)
            val wire="""{"max_tokens":128,"messages":[{"content":"For this synthetic test, the code is CANARY-4827. Answer with that code only.","role":"user"}],"model":"deepseek-flash","n":1,"stream":false,"thinking":{"type":"disabled"}}""".toByteArray()
            val prior=OrdinaryChatCanaryBudget.provisionNewBatch(root.toPath())
            val held=prior.reserve("chat_eb1eeb36ef9748c7900f5eb810622d00",wire,OrdinaryChatProductionConfig.prove(wire),"CNY",OrdinaryChatProductionConfig.verifier)
            prior.handoff(held);prior.stop(held)
            val original=File(root,"ordinary-chat-canary-20261019.ledger").readBytes()
            val credentials=OrdinaryChatTemporaryCredential();credentials.install("public-offline-followup-key".toCharArray())
            val live=OrdinaryChatLiveInstallation(root,credentials,authorizedFollowup=true)
            val newWire=String(wire).replace("CANARY-4827","CANARY-7391").toByteArray()
            refused{live.prove(wire)};assertTrue(live.verifier.verify(newWire,live.prove(newWire)))
            val provider=checkNotNull(live.facts().provider);assertEquals("muyon-ordinary-chat-20261020-authorized-followup",provider.budget.revision)
            assertEquals(998690uL,provider.budget.remainingMicros)
            assertEquals("ordinary-live-owner",provider.authorizationOwner)
            val permit=live.budget.reserve("new-followup",newWire,live.prove(newWire),"CNY",live.verifier)
            assertEquals(1000000L,live.budget.ceilingMicroCny+prior.snapshot().reservedMicroCny)
            assertTrue(prior.snapshot().stopped);assertArrayEquals(original,File(root,"ordinary-chat-canary-20261019.ledger").readBytes())
            // An already admitted round cannot initialize a fresh native namespace/index.
            val isolated=object:android.content.ContextWrapper(context){override fun getFilesDir()=parent}
            refused{OrdinaryChatAuthorizedSession.allowed(isolated,live)}
            live.budget.handoff(permit);live.budget.stop(permit)
            refused{OrdinaryChatAuthorizedSession.allowed(isolated,live)}
            assertArrayEquals(original,File(root,"ordinary-chat-canary-20261019.ledger").readBytes())
            credentials.clear()
        } finally {parent.deleteRecursively()}
    }
}
