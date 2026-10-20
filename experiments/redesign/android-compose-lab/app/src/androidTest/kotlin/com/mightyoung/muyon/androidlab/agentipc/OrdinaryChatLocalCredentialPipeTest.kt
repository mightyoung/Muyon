package com.mightyoung.muyon.androidlab.agentipc

import android.system.Os
import android.system.OsConstants
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/** Dummy bytes only. No liveChat Application, credential installation or network. */
class OrdinaryChatLocalCredentialPipeTest {
    private val dummy="offline-pipe-dummy-credential"
    private fun root():File {
        val root=File(InstrumentationRegistry.getInstrumentation().targetContext.noBackupFilesDir,"dummy-credential-pipe-"+UUID.randomUUID())
        Os.mkdir(root.absolutePath,448);return root
    }
    private fun writer(path:File,parts:List<ByteArray>,between:()->Unit={}) {
        val fd=Os.open(path.absolutePath,OsConstants.O_WRONLY or OsConstants.O_NONBLOCK or OsConstants.O_NOFOLLOW,0)
        try{parts.forEachIndexed{index,bytes->
            var offset=0;while(offset<bytes.size){val count=Os.write(fd,bytes,offset,bytes.size-offset);check(count>0);offset+=count}
            if(index<parts.lastIndex)between()
        }}finally{Os.close(fd)}
    }
    private fun waitRemoved(file:File) {
        val deadline=android.os.SystemClock.elapsedRealtime()+3000
        while(file.exists() && android.os.SystemClock.elapsedRealtime()<deadline)Thread.sleep(10)
        assertFalse("first read must unlink the FIFO",file.exists())
    }
    private fun stop(pipe:OrdinaryChatLocalCredentialPipe){pipe.close();assertTrue(pipe.awaitStopped(3000))}

    @Test fun platformNoBackupParent0771IsAcceptedWithoutChangingMode() {
        val root=root();Os.chmod(root.absolutePath,505)
        val ready=CountDownLatch(1);val done=CountDownLatch(1);val installed=AtomicInteger()
        val pipe=OrdinaryChatLocalCredentialPipe(root,{installed.incrementAndGet()},{assertTrue(it);done.countDown()},{ready.countDown()},3000)
        try{
            pipe.start();assertTrue(ready.await(3,TimeUnit.SECONDS))
            assertEquals(505,Os.lstat(root.absolutePath).st_mode and 4095)
            assertEquals(448,Os.lstat(pipe.fifo.parentFile!!.absolutePath).st_mode and 4095)
            writer(pipe.fifo,listOf((dummy+"\n").toByteArray()));assertTrue(done.await(3,TimeUnit.SECONDS));assertEquals(1,installed.get())
            assertEquals(505,Os.lstat(root.absolutePath).st_mode and 4095)
        }finally{stop(pipe);root.deleteRecursively()}
    }

    @Test fun initialEofWaitsAndSegmentedFrameNeedsWriterEof() {
        val root=root();val ready=CountDownLatch(1);val done=CountDownLatch(1);val installed=AtomicInteger();val ok=AtomicBoolean()
        val retained=AtomicReference<CharArray?>()
        val pipe=OrdinaryChatLocalCredentialPipe(root,{value->assertArrayEquals(dummy.toCharArray(),value);retained.set(value);installed.incrementAndGet()},{ok.set(it);done.countDown()},{ready.countDown()},3000)
        try{
            pipe.start();assertTrue(ready.await(3,TimeUnit.SECONDS))
            assertFalse("initial zero read must remain waiting",done.await(100,TimeUnit.MILLISECONDS));assertEquals(0,installed.get())
            writer(pipe.fifo,listOf(dummy.substring(0,10).toByteArray(),(dummy.substring(10)+"\n").toByteArray())){waitRemoved(pipe.fifo);assertEquals(0,installed.get());assertFalse(done.await(60,TimeUnit.MILLISECONDS))}
            assertTrue(done.await(3,TimeUnit.SECONDS));assertTrue(ok.get());assertEquals(1,installed.get())
            assertTrue(checkNotNull(retained.get()).all{it=='\u0000'})
        }finally{stop(pipe);root.deleteRecursively()}
    }

    @Test fun malformedMissingLfTrailingAndOversizeNeverInstall() {
        for(frame in listOf(dummy.toByteArray(),(dummy+"\nextra").toByteArray(),(dummy+"\n\n").toByteArray(),("x".repeat(513)+"\n").toByteArray(),byteArrayOf(-1,10))){
            val root=root();val ready=CountDownLatch(1);val done=CountDownLatch(1);val installed=AtomicInteger();val ok=AtomicBoolean(true)
            val pipe=OrdinaryChatLocalCredentialPipe(root,{installed.incrementAndGet()},{ok.set(it);done.countDown()},{ready.countDown()},1500)
            try{pipe.start();assertTrue(ready.await(3,TimeUnit.SECONDS));writer(pipe.fifo,listOf(frame));assertTrue(done.await(3,TimeUnit.SECONDS));assertFalse(ok.get());assertEquals(0,installed.get())}
            finally{frame.fill(0);stop(pipe);root.deleteRecursively()}
        }
    }

    @Test fun timeoutOverlapAndCancelBeforeDeliveryHaveNoLateInstall() {
        val root=root();val ready=CountDownLatch(1);val done=CountDownLatch(1);val installed=AtomicInteger()
        val timeout=OrdinaryChatLocalCredentialPipe(root,{installed.incrementAndGet()},{assertFalse(it);done.countDown()},{ready.countDown()},150)
        try{timeout.start();assertTrue(ready.await(3,TimeUnit.SECONDS));assertTrue(done.await(3,TimeUnit.SECONDS));assertEquals(0,installed.get())}finally{stop(timeout)}
        val entered=CountDownLatch(1);val release=CountDownLatch(1);val waiting=CountDownLatch(1);val callbackCalled=AtomicBoolean()
        val pipe=OrdinaryChatLocalCredentialPipe(root,{installed.incrementAndGet()},{callbackCalled.set(true)},{waiting.countDown()},3000,{entered.countDown();release.await(3,TimeUnit.SECONDS)})
        val overlap=OrdinaryChatLocalCredentialPipe(root,{fail("overlap installed")},{})
        try{
            pipe.start();assertTrue(waiting.await(3,TimeUnit.SECONDS))
            try{overlap.start();fail("overlap accepted")}catch(_:OrdinaryChatLocalCredentialPipe.Refused){}
            writer(pipe.fifo,listOf((dummy+"\n").toByteArray()));assertTrue(entered.await(3,TimeUnit.SECONDS))
            pipe.close();release.countDown();assertTrue(pipe.awaitStopped(3000));assertEquals(0,installed.get());assertFalse(callbackCalled.get())
        }finally{release.countDown();stop(pipe);overlap.close();root.deleteRecursively()}
    }

    @Test fun lateOldCleanupCannotDeleteReplacementFifo() {
        val root=root();val entered=CountDownLatch(1);val release=CountDownLatch(1);val firstReady=CountDownLatch(1);val oldInstalled=AtomicInteger()
        val old=OrdinaryChatLocalCredentialPipe(root,{oldInstalled.incrementAndGet()},{},{firstReady.countDown()},5000,{
            entered.countDown();while(release.count>0){try{release.await(3,TimeUnit.SECONDS)}catch(_:InterruptedException){}}
        })
        val newReady=CountDownLatch(1);val done=CountDownLatch(1);val newInstalled=AtomicInteger()
        val replacement=OrdinaryChatLocalCredentialPipe(root,{newInstalled.incrementAndGet()},{assertTrue(it);done.countDown()},{newReady.countDown()},5000)
        try{
            old.start();assertTrue(firstReady.await(3,TimeUnit.SECONDS));writer(old.fifo,listOf((dummy+"\n").toByteArray()));assertTrue(entered.await(3,TimeUnit.SECONDS))
            old.close();replacement.start();assertTrue(newReady.await(3,TimeUnit.SECONDS));val inode=Os.lstat(replacement.fifo.absolutePath).st_ino
            release.countDown();assertTrue(old.awaitStopped(3000));assertEquals(inode,Os.lstat(replacement.fifo.absolutePath).st_ino)
            writer(replacement.fifo,listOf((dummy+"\n").toByteArray()));assertTrue(done.await(3,TimeUnit.SECONDS));assertEquals(0,oldInstalled.get());assertEquals(1,newInstalled.get())
        }finally{release.countDown();stop(old);stop(replacement);root.deleteRecursively()}
    }

    private fun fdGuard(path:File,identity:String):String {
        check(path.absolutePath.matches(Regex("[A-Za-z0-9_./-]+")))
        return "exec 3> ${path.absolutePath}; test -p /proc/self/fd/3 || exit 71; test \"\$(stat -Lc %d:%i:%u:%a /proc/self/fd/3)\" = $identity || exit 72; cat >&3"
    }
    private fun sendGuarded(script:String):Int {
        val process=ProcessBuilder("/system/bin/toybox","timeout","5","/system/bin/sh","-c",script).start()
        try{
            try{process.outputStream.use{it.write((dummy+"\n").toByteArray())}}catch(_:java.io.IOException){}
            assertTrue(process.waitFor(8,TimeUnit.SECONDS));return process.exitValue()
        }finally{process.destroyForcibly()}
    }
    @Test fun actualAndroidShellFdGuardAcceptsFifoAndRefusesReplacedRegularFile() {
        for(replace in listOf(false,true)){
            val root=root();val ready=CountDownLatch(1);val done=CountDownLatch(1);val installed=AtomicInteger()
            val pipe=OrdinaryChatLocalCredentialPipe(root,{assertArrayEquals(dummy.toCharArray(),it);installed.incrementAndGet()},{assertTrue(it);done.countDown()},{ready.countDown()},5000)
            try{
                pipe.start();assertTrue(ready.await(3,TimeUnit.SECONDS));val stat=Os.lstat(pipe.fifo.absolutePath)
                val identity="${stat.st_dev}:${stat.st_ino}:${stat.st_uid}:600"
                if(replace)Os.remove(pipe.fifo.absolutePath)
                val exit=sendGuarded(fdGuard(pipe.fifo,identity))
                if(replace){assertEquals(71,exit);assertTrue(pipe.fifo.isFile);assertEquals(0L,pipe.fifo.length());assertEquals(0,installed.get())}
                else{assertEquals(0,exit);assertTrue(done.await(3,TimeUnit.SECONDS));assertEquals(1,installed.get())}
            }finally{stop(pipe);root.deleteRecursively()}
        }
    }
}
