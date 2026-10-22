package com.mightyoung.muyon.androidlab.agentipc

import android.os.IBinder
import android.os.Parcel

/** Preflights the complete generated-AIDL argument order, token and nullable framing. */
internal class BoundedAgentProxy(private val remote:IAgentRuntime) {
    private inline fun <T> request(write:Parcel.()->Unit,chat:Boolean=false,call:()->T):T {
        val parcel=Parcel.obtain()
        try {parcel.writeInterfaceToken(DESCRIPTOR);parcel.write();if(chat){if(parcel.dataSize()>16384)throw android.os.BadParcelableException("request_unavailable")}else AgentParcelLimits.request(parcel)}finally{parcel.recycle()}
        return call()
    }
    private fun Parcel.client(epoch:String,lease:String){writeString(epoch);writeString(lease)}
    fun connect(token:IBinder)=request({writeStrongBinder(token)}){remote.connect(token)}
    fun start(epoch:String,lease:String,id:String,variant:Int)=request({client(epoch,lease);writeString(id);writeInt(variant)}){remote.start(epoch,lease,id,variant)}
    fun current(epoch:String,lease:String)=request({client(epoch,lease)}){remote.current(epoch,lease)}
    fun status(epoch:String,lease:String,id:String,variant:Int,runId:String?)=request({client(epoch,lease);writeString(id);writeInt(variant);writeString(runId)}){remote.status(epoch,lease,id,variant,runId)}
    fun lookup(epoch:String,lease:String,kind:Int,key:String)=request({client(epoch,lease);writeInt(kind);writeString(key)}){remote.lookup(epoch,lease,kind,key)}
    fun setVisibility(epoch:String,lease:String,generation:Long,visible:Boolean)=request({client(epoch,lease);writeLong(generation);writeInt(if(visible)1 else 0)}){remote.setVisibility(epoch,lease,generation,visible)}
    fun release(epoch:String,lease:String,generation:Long)=request({client(epoch,lease);writeLong(generation)}){remote.release(epoch,lease,generation)}
    fun cancel(epoch:String,lease:String,id:String,variant:Int,runId:String?)=request({client(epoch,lease);writeString(id);writeInt(variant);writeString(runId)}){remote.cancel(epoch,lease,id,variant,runId)}
    fun submitOrdinaryChat(epoch:String,lease:String,id:String,conversation:String,text:String)=request({client(epoch,lease);writeString(id);writeString(conversation);writeString(text)},true){remote.submitOrdinaryChat(epoch,lease,id,conversation,text)}
    fun submitSupplierRead(epoch:String,lease:String,id:String,text:String,key:String,revision:String)=request({client(epoch,lease);writeString(id);writeString(text);writeString(key);writeString(revision)},true){remote.submitSupplierRead(epoch,lease,id,text,key,revision)}
    fun supplierReadEvents(epoch:String,lease:String,id:String,after:Long)=request({client(epoch,lease);writeString(id);writeLong(after)},true){remote.supplierReadEvents(epoch,lease,id,after)}
    fun close(epoch:String,lease:String)=request({client(epoch,lease)}){remote.close(epoch,lease)}
    companion object {private const val DESCRIPTOR="com.mightyoung.muyon.androidlab.agentipc.IAgentRuntime"}
}
