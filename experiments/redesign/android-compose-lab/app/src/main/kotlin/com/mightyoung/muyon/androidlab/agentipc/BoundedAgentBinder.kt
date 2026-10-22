package com.mightyoung.muyon.androidlab.agentipc

import android.os.Binder
import android.os.IBinder
import android.os.Parcel
import android.os.Process
import android.os.RemoteException

/** Checks the complete request before generated decoding and the complete encoded reply. */
abstract class BoundedAgentBinder:IAgentRuntime.Stub() {
    private fun isChat(code:Int)=code==IAgentRuntime.Stub.TRANSACTION_submitOrdinaryChat || code==IAgentRuntime.Stub.TRANSACTION_submitSupplierRead || code==IAgentRuntime.Stub.TRANSACTION_supplierReadEvents
    override fun onTransact(code:Int,data:Parcel,reply:Parcel?,flags:Int):Boolean {
        if(code in IBinder.FIRST_CALL_TRANSACTION..IBinder.LAST_CALL_TRANSACTION) {
            if(isChat(code)){if(data.dataSize()>16384)throw android.os.BadParcelableException("request_unavailable")}else AgentParcelLimits.request(data)
            if(Binder.getCallingUid()!=Process.myUid()) throw SecurityException("caller_unavailable")
            if(flags and IBinder.FLAG_ONEWAY!=0) throw RemoteException("delivery_unavailable")
        }
        if(reply==null) return false
        val encoded=Parcel.obtain()
        try {
            val handled=super.onTransact(code,data,encoded,flags)
            // The generated Stub has already written exception framing, typed-object and
            // byte-array overhead. Payload byte count alone is not this envelope limit.
            if(isChat(code)){if(encoded.dataSize()>131200)throw android.os.BadParcelableException("reply_unavailable")}else AgentParcelLimits.reply(encoded)
            reply.appendFrom(encoded,0,encoded.dataSize())
            if(isChat(code)){if(reply.dataSize()>131200)throw android.os.BadParcelableException("reply_unavailable")}else AgentParcelLimits.reply(reply)
            return handled
        } finally { encoded.recycle() }
    }
}
