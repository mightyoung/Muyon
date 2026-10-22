package com.mightyoung.muyon.androidlab.agentipc

import android.os.BadParcelableException
import android.os.Parcel
import android.os.Parcelable
import com.mightyoung.muyon.androidlab.AgentServiceWire
import com.mightyoung.muyon.androidlab.UiAgentLocalStatus
import com.mightyoung.muyon.androidlab.UiAgentWireReply

/** The payload is a closed versioned metadata schema, not Java serialization or JSON. */
class AgentReplyParcel private constructor(private val payload:ByteArray):Parcelable {
    fun decode(expectedBuild:String):UiAgentWireReply?=AgentServiceWire.decode(payload,expectedBuild)
    override fun describeContents()=0
    override fun writeToParcel(dest:Parcel,flags:Int) {
        dest.writeByteArray(payload)
        AgentParcelLimits.reply(dest)
    }
    companion object {
        fun from(reply:UiAgentWireReply,build:String):AgentReplyParcel {
            // Validation/encoding failure is transport uncertainty, never NoAdmission or success.
            val payload=AgentServiceWire.encode(reply,build) ?: AgentServiceWire.encode(UiAgentWireReply.Local(UiAgentLocalStatus.UNAVAILABLE),build)!!
            return AgentReplyParcel(payload)
        }
        @JvmField val CREATOR:Parcelable.Creator<AgentReplyParcel> = object:Parcelable.Creator<AgentReplyParcel> {
            override fun createFromParcel(source:Parcel):AgentReplyParcel {
                AgentParcelLimits.reply(source)
                val bytes=source.createByteArray() ?: throw BadParcelableException("invalid_reply")
                if(bytes.size>AgentServiceWire.MAX_PAYLOAD_BYTES) throw BadParcelableException("invalid_reply")
                return AgentReplyParcel(bytes)
            }
            override fun newArray(size:Int):Array<AgentReplyParcel?> = arrayOfNulls(size)
        }
    }
}
object AgentParcelLimits {
    const val REQUEST_BYTES=4096
    const val REPLY_BYTES=8192
    fun request(parcel:Parcel) { if(parcel.dataSize()>REQUEST_BYTES) throw BadParcelableException("request_unavailable") }
    fun reply(parcel:Parcel) { if(parcel.dataSize()>REPLY_BYTES) throw BadParcelableException("reply_unavailable") }
}
