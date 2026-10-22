package com.mightyoung.muyon.androidlab.agentipc

import android.os.BadParcelableException
import android.os.Parcel
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.mightyoung.muyon.androidlab.UiAgentLocalStatus
import com.mightyoung.muyon.androidlab.UiAgentWireReply
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Device-only evidence: these tests are compiled by CI, not claimed executed on host JVM. */
@RunWith(AndroidJUnit4::class)
class AgentParcelTest {
    @Test fun requestCapIncludesInterfaceTokenAndByteArrayFraming() {
        val p=Parcel.obtain()
        try {
            p.writeInterfaceToken("com.mightyoung.muyon.androidlab.agentipc.IAgentRuntime")
            p.writeByteArray(ByteArray(AgentParcelLimits.REQUEST_BYTES))
            assertTrue(p.dataSize()>AgentParcelLimits.REQUEST_BYTES)
            assertThrows(BadParcelableException::class.java){AgentParcelLimits.request(p)}
        } finally { p.recycle() }
    }
    @Test fun validLocalReplyRoundTripsWithExceptionAndPresenceFraming() {
        val p=Parcel.obtain()
        try {
            val expected=UiAgentWireReply.Local(UiAgentLocalStatus.INITIALIZING)
            p.writeNoException();p.writeInt(1);AgentReplyParcel.from(expected,"").writeToParcel(p,0)
            AgentParcelLimits.reply(p);p.setDataPosition(0);p.readException();assertEquals(1,p.readInt())
            assertEquals(expected,AgentReplyParcel.CREATOR.createFromParcel(p).decode(""))
        } finally { p.recycle() }
    }
    @Test fun replyCapIncludesExistingExceptionAndArrayFraming() {
        val p=Parcel.obtain()
        try {
            p.writeNoException();p.writeInt(1);p.writeByteArray(ByteArray(AgentParcelLimits.REPLY_BYTES))
            assertThrows(BadParcelableException::class.java){AgentParcelLimits.reply(p)}
            p.setDataPosition(8)
            assertThrows(BadParcelableException::class.java){AgentReplyParcel.CREATOR.createFromParcel(p)}
        } finally { p.recycle() }
    }
}
