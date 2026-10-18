package com.mightyoung.muyon.androidlab.agentipc

import android.content.*
import android.app.ActivityManager
import android.os.*
import android.os.Process
import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.androidlab.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.FutureTask

/** Exact named fixed-APK acceptance; no installation or fault control through IPC. */
class ServiceLifecycleFailureTest {
    private val context get()=InstrumentationRegistry.getInstrumentation().targetContext
    private val file get()=File(context.filesDir,"failure-evidence.json")
    private fun await(check:(JSONObject)->Boolean):JSONObject {
        val end=SystemClock.elapsedRealtime()+45_000
        while(SystemClock.elapsedRealtime()<end) {
            val value=try{JSONObject(file.readText())}catch(_:Exception){null}
            if(value!=null && value.optString("failure").isNotEmpty())error(value.toString())
            if(value!=null && check(value))return value
            SystemClock.sleep(25)
        }
        error("bounded evidence timeout: ${if(file.exists())file.readText() else "absent"}")
    }
    private class Binding(val context:Context):AutoCloseable {
        private val latch=CountDownLatch(1)
        private var bound=true
        private lateinit var binder:IBinder
        private val connection=object:ServiceConnection {
            override fun onServiceConnected(name:ComponentName,service:IBinder){binder=service;latch.countDown()}
            override fun onServiceDisconnected(name:ComponentName){}
        }
        init { check(context.bindService(Intent(context,AgentRuntimeService::class.java),connection,Context.BIND_AUTO_CREATE));check(latch.await(20,TimeUnit.SECONDS)) }
        val remote get()=IAgentRuntime.Stub.asInterface(binder)
        override fun close(){if(bound){context.unbindService(connection);bound=false}}
    }
    private fun unavailable(binding:Binding) {
        val call=FutureTask {binding.remote.connect(Binder()).decode(BuildConfig.MUYON_BRIDGE_SOURCE_SHA)}
        Thread(call,"bounded-unavailable-assertion").also{it.isDaemon=true;it.start()}
        assertEquals(UiAgentWireReply.Local(UiAgentLocalStatus.UNAVAILABLE),call.get(5,TimeUnit.SECONDS))
    }
    @Test fun fixedActualServiceFailureLifecycle() {
        val scenario=context.packageName.substringAfterLast('.')
        assertTrue(scenario in listOf("failSetup","failSetupOwner","failUnknown","failOwner","failNative","failInflight","failReady","failConstructDestroy"))
        assertFalse("fresh dedicated APK required",file.exists())
        val first=Binding(context)
        try {
            if(scenario=="failConstructDestroy") {
                val held=await{it.optBoolean("constructionHeld")}
                val originalPid=held.getInt("pid")
                first.close()
                await{it.optInt("destroyedReturned")==1}
                unavailable(first)
                Binding(context).use{denied->
                    unavailable(denied)
                    val retained=await{it.optBoolean("replacementDenied")}
                    assertFalse(retained.optBoolean("constructionReleased"))
                    assertEquals(1,retained.getInt("acquired"))
                    assertEquals(0,retained.getInt("nativeClosed"));assertEquals(0,retained.getInt("ownerClosed"))
                    assertEquals(0,retained.getInt("slotReleased"));assertEquals(0,retained.getInt("backendDrained"))
                }
                val drained=await{it.optInt("backendDrained")==1 && it.optInt("slotReleased")==1}
                assertEquals(originalPid,drained.getInt("pid"))
                assertEquals(1,drained.getInt("acquired"));assertEquals(1,drained.getInt("nativeClosed"));assertEquals(1,drained.getInt("ownerClosed"))
                assertEquals(1,drained.getInt("nativeCloseAttempt"));assertEquals(1,drained.getInt("ownerCloseAttempt"))
                assertFalse("destroyed construction cannot publish Ready",drained.optBoolean("ready"))
                for(key in listOf("held","consumed","expired","admissions"))assertEquals(key,0,drained.getInt(key))
                val events=drained.getJSONArray("events").let{a->List(a.length()){a.getString(it)}}
                assertTrue(events.indexOf("destroyedReturned")<events.indexOf("constructionReleased"))
                assertTrue(events.indexOf("constructionReleased")<events.indexOf("nativeClosed"))
                assertTrue(events.indexOf("nativeClosed")<events.indexOf("ownerClosed"))
                assertTrue(events.indexOf("ownerClosed")<events.indexOf("slotReleased"))
                assertTrue(events.indexOf("slotReleased")<events.indexOf("backendDrained"))
                Binding(context).use{replacement->
                    val ready=await{it.optBoolean("ready") && it.optInt("acquired")==2}
                    assertEquals("private process survives original backend drain",originalPid,ready.getInt("pid"))
                    val call=FutureTask {replacement.remote.connect(Binder()).decode(BuildConfig.MUYON_BRIDGE_SOURCE_SHA)}
                    Thread(call,"bounded-replacement-connect").also{it.isDaemon=true;it.start()}
                    assertTrue(call.get(5,TimeUnit.SECONDS) is UiAgentWireReply.Connected)
                }
                val complete=await{it.optInt("backendDrained")==2 && it.optInt("destroyedReturned")==3}
                assertEquals(originalPid,complete.getInt("pid"))
                for(key in listOf("nativeClosed","ownerClosed","slotReleased","nativeCloseAttempt","ownerCloseAttempt"))assertEquals(key,2,complete.getInt(key))
            } else if(scenario=="failInflight") {
                await{it.optBoolean("ready")}
                val deadline=SystemClock.elapsedRealtime()+10_000
                var connected=false
                while(!connected && SystemClock.elapsedRealtime()<deadline){
                    connected=first.remote.connect(Binder()).decode(BuildConfig.MUYON_BRIDGE_SOURCE_SHA) is UiAgentWireReply.Connected
                    if(!connected)SystemClock.sleep(25)
                }
                assertTrue("real Binder client connected before callback",connected)
                await{it.optBoolean("callbackHeld")}
                first.close()
                await{it.optInt("destroyedReturned")>=1}
                unavailable(first)
                Binding(context).use { replacement->
                    unavailable(replacement)
                    val held=await{it.optBoolean("replacementDenied")}
                    assertEquals(1,held.getInt("acquired"));assertEquals(0,held.getInt("ownerClosed"))
                    assertEquals(0,held.getInt("slotReleased"));assertEquals(0,held.getInt("nativeClosed"))
                }
                val done=await{it.optInt("slotReleased")==1}
                assertEquals(1,done.getInt("acquired"));assertEquals(1,done.getInt("nativeClosed"));assertEquals(1,done.getInt("ownerClosed"))
                assertTrue(done.getBoolean("callbackReturned"));assertTrue(done.getBoolean("sealed"))
                assertEquals(1,done.getInt("consumed"));assertEquals(0,done.getInt("held"));assertEquals(1,done.getInt("admissions"))
                val events=done.getJSONArray("events").let{a->List(a.length()){a.getString(it)}}
                assertTrue(events.indexOf("callbackReturned")<events.indexOf("nativeClosed"))
                assertTrue(events.indexOf("nativeClosed")<events.indexOf("ownerClosed"))
                assertTrue(events.indexOf("ownerClosed")<events.indexOf("slotReleased"))
            } else {
                await{it.optBoolean("unavailable") || it.optBoolean("ready")}
                if(scenario=="failOwner" || scenario=="failNative")first.close()
                val retention=scenario in listOf("failSetupOwner","failUnknown","failOwner","failNative")
                val outcome=await{if(retention)it.optBoolean("retainedFailure") else it.optInt("slotReleased")==1}
                if(scenario!="failOwner" && scenario!="failNative")unavailable(first)
                first.close()
                await{it.optInt("destroyedReturned")>=1}
                Binding(context).use{second->
                    if(retention){unavailable(second);await{it.optBoolean("replacementDenied")}}
                    else await{it.optInt("acquired")==2}
                }
                if(scenario=="failSetup" || scenario=="failSetupOwner")assertFalse(outcome.optBoolean("constructed"))
                if(scenario=="failUnknown")assertTrue(outcome.getBoolean("constructed"))
                if(retention){
                    assertEquals(0,outcome.getInt("slotReleased"));assertEquals(0,outcome.getInt("ownerClosed"))
                    assertEquals(if(scenario in listOf("failOwner","failSetupOwner"))1 else 0,outcome.getInt("ownerCloseAttempt"))
                    assertEquals(if(scenario in listOf("failOwner","failNative"))1 else 0,outcome.getInt("nativeCloseAttempt"))
                }
                else assertEquals(1,outcome.getInt("ownerClosed"))
            }
            val final=await{it.optInt("destroyedReturned")>=2 && (if(scenario in listOf("failSetup","failReady"))it.optInt("slotReleased")==2 else true)}
            assertEquals(26,final.getInt("sdk"))
            assertEquals(Process.myUid(),final.getInt("uid"));assertNotEquals(Process.myPid(),final.getInt("pid"))
            val process=(context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).runningAppProcesses.orEmpty().single{it.pid==final.getInt("pid")}
            assertEquals("${context.packageName}:agent",process.processName);assertEquals(Process.myUid(),process.uid)
            println("API26_SERVICE_FAILURE_EVIDENCE $final")
            println("API26_SERVICE_FAILURE_PASS scenario=$scenario synthetic=true model_api_called=false")
        } finally {first.close()}
    }
}
