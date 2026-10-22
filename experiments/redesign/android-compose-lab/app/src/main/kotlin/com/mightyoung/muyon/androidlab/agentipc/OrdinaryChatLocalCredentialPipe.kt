package com.mightyoung.muyon.androidlab.agentipc

import android.os.Process
import android.os.Build
import android.os.SystemClock
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.system.StructStat
import java.io.File
import java.io.FileDescriptor
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** One local, expiring, kernel-buffer-only handover; never sends a model request. */
internal class OrdinaryChatLocalCredentialPipe(
    private val noBackupRoot:File,
    private val install:(CharArray)->Unit,
    private val finished:(Boolean)->Unit,
    private val ready:()->Unit={},
    private val timeoutMillis:Long=120_000,
    private val beforeDeliver:(()->Unit)?=null,
):AutoCloseable {
    private data class Identity(val device:Long,val inode:Long)
    private val lock=Any()
    private val executor=Executors.newSingleThreadExecutor()
    private var started=false
    private var cancelled=false
    private var descriptor:FileDescriptor?=null
    private var identity:Identity?=null
    private var ownsSlot=false
    private val trustedRoot=noBackupRoot.canonicalFile
    private val directory=File(trustedRoot,DIRECTORY)
    internal val fifo=File(directory,FIFO)
    class Refused:IllegalStateException("local_credential_handoff_refused")

    fun start() {
        if(Build.VERSION.SDK_INT<27)throw Refused()
        synchronized(lock){
            check(!started && !cancelled)
            if(!active.compareAndSet(false,true))throw Refused()
            ownsSlot=true;started=true
        }
        try{executor.execute{receive()}}catch(_:Exception){close();throw Refused()}
    }

    private fun privateStat(stat:StructStat,type:Int,mode:Int) {
        require((stat.st_mode and OsConstants.S_IFMT)==type && stat.st_uid==Process.myUid() && (stat.st_mode and 4095)==mode)
    }
    private fun id(stat:StructStat)=Identity(stat.st_dev,stat.st_ino)
    private fun open() {
        if(Build.VERSION.SDK_INT<27)throw Refused()
        val parent=Os.lstat(noBackupRoot.absolutePath)
        require((parent.st_mode and OsConstants.S_IFMT)==OsConstants.S_IFDIR && parent.st_uid==Process.myUid())
        require(noBackupRoot.canonicalFile==trustedRoot && id(Os.lstat(trustedRoot.absolutePath))==id(parent))
        try{Os.mkdir(directory.absolutePath,448)}catch(e:ErrnoException){if(e.errno!=OsConstants.EEXIST)throw e}
        privateStat(Os.lstat(directory.absolutePath),OsConstants.S_IFDIR,448)
        require(directory.canonicalFile.parentFile==trustedRoot && directory.canonicalFile==directory.absoluteFile)
        val old=try{Os.lstat(fifo.absolutePath)}catch(e:ErrnoException){if(e.errno==OsConstants.ENOENT)null else throw e}
        if(old!=null){
            privateStat(old,OsConstants.S_IFIFO,384)
            require(id(Os.lstat(fifo.absolutePath))==id(old))
            Os.remove(fifo.absolutePath)
        }
        Os.mkfifo(fifo.absolutePath,384)
        val created=Os.lstat(fifo.absolutePath)
        privateStat(created,OsConstants.S_IFIFO,384);identity=id(created)
        val fd=if(Build.VERSION.SDK_INT>=27){
            Os.open(fifo.absolutePath,OsConstants.O_RDONLY or OsConstants.O_NONBLOCK or OsConstants.O_NOFOLLOW or OsConstants.O_CLOEXEC,0)
        }else{throw Refused()}
        descriptor=fd
        privateStat(Os.fstat(fd),OsConstants.S_IFIFO,384)
        require(id(Os.fstat(fd))==identity && id(Os.lstat(fifo.absolutePath))==identity)
    }

    private fun unlinkOwned() {
        val expected=identity ?: return
        val current=try{Os.lstat(fifo.absolutePath)}catch(e:ErrnoException){if(e.errno==OsConstants.ENOENT)return else throw e}
        if(id(current)==expected){privateStat(current,OsConstants.S_IFIFO,384);Os.remove(fifo.absolutePath)}
    }
    private fun cleanupLocked() {
        descriptor?.let{try{Os.close(it)}catch(_:Exception){}};descriptor=null
        try{unlinkOwned()}catch(_:Exception){}
        identity=null
        if(ownsSlot){ownsSlot=false;active.set(false)}
    }
    override fun close() {
        // Nonblocking read, descriptor close, and acceptance use the same lock. No fd reuse race.
        synchronized(lock){cancelled=true;cleanupLocked()}
        executor.shutdownNow()
    }
    internal fun awaitStopped(timeoutMillis:Long)=executor.awaitTermination(timeoutMillis,java.util.concurrent.TimeUnit.MILLISECONDS)
    private fun receive() {
        val bytes=ByteArray(514)
        val chars=CharArray(512)
        var length=0;var newline=false;var firstData=false;var success=false
        try{
            require(timeoutMillis in 1..120_000)
            val deadline=SystemClock.elapsedRealtime()+timeoutMillis
            synchronized(lock){check(!cancelled);open()}
            ready()
            while(SystemClock.elapsedRealtime()<deadline){
                val count=synchronized(lock){
                    check(!cancelled)
                    val n=try{Os.read(checkNotNull(descriptor),bytes,0,bytes.size)}catch(e:ErrnoException){if(e.errno==OsConstants.EAGAIN)-1 else throw e}
                    if(n>0 && !firstData){firstData=true;unlinkOwned()}
                    n
                }
                if(count>0){
                    for(index in 0 until count){
                        val value=bytes[index].toInt() and 255
                        require(!newline)
                        if(value==10){require(length in 16..512);newline=true}
                        else{require(value in 33..126 && length<512);chars[length++]=value.toChar()}
                    }
                    bytes.fill(0)
                }else if(count==0 && firstData){
                    // LF alone is not completion: the same writer must close with no trailing bytes.
                    require(newline)
                    beforeDeliver?.invoke()
                    val value=chars.copyOf(length)
                    try{synchronized(lock){check(!cancelled && SystemClock.elapsedRealtime()<deadline);install(value);success=true}}finally{value.fill('\u0000')}
                    break
                }
                // Initial FIFO EOF means no writer yet, not an empty credential.
                Thread.sleep(20)
            }
        }catch(_:Exception){success=false}
        finally{
            chars.fill('\u0000');bytes.fill(0)
            val notify=synchronized(lock){val value=!cancelled;cleanupLocked();value}
            executor.shutdown()
            if(notify){try{finished(success)}catch(_:Exception){}}
        }
    }
    companion object {
        const val DIRECTORY="ordinary-chat-credential"
        const val FIFO="credential.fifo"
        private val active=AtomicBoolean(false)
    }
}
