package com.mightyoung.muyon.androidlab.agentipc

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.AtomicFile
import com.mightyoung.muyon.androidbridge.*
import com.mightyoung.muyon.androidlab.MuyonLabApplication
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Each subclass and failure is selected ONLY by its compiled manifest. */
@Suppress("EXPOSED_FUNCTION_RETURN_TYPE", "EXPOSED_SUPER_CLASS")
abstract class FailureFixtureApplication(private val scenario:String):MuyonLabApplication(),ServiceLifecycleHooks {
    private val call=ServiceOwnerCallBudget(32uL,4uL,false,false)
    private val authority=ServiceAdmissionAuthority(approved())
    private val processOwner=ServiceAdmissionProcessOwner(authority)
    private val events=mutableListOf<String>()
    private val evidence=JSONObject().put("scenario",scenario).put("synthetic",true)
        .put("pid",android.os.Process.myPid()).put("uid",android.os.Process.myUid()).put("sdk",android.os.Build.VERSION.SDK_INT).also { json->
        for(key in listOf("acquired","destroyed","destroyedReturned","ownerClosed","nativeClosed","slotReleased","ownerCloseAttempt","nativeCloseAttempt"))json.put(key,0)
    }
    private val drain=CountDownLatch(1)
    private val connectedClient=CountDownLatch(1)
    private var controller:GeneratedAgentController?=null
    private var root:File?=null
    private var acquiredCount=0
    @Synchronized private fun record(name:String,increment:Boolean=false) {
        events.add(name)
        if(increment)evidence.put(name,evidence.optInt(name)+1) else evidence.put(name,true)
        evidence.put("events",JSONArray(events))
        root?.let{r->
            SQLiteDatabase.openDatabase(File(r,DurableServiceHostOwner.DATABASE_NAME).path,null,SQLiteDatabase.OPEN_READONLY).use{db->
                for(state in listOf("held","expired","consumed"))db.rawQuery("SELECT count(*) FROM reservations WHERE state=?",arrayOf(state)).use{c->check(c.moveToFirst());evidence.put(state,c.getInt(0))}
                db.rawQuery("SELECT count(*) FROM admissions",null).use{c->check(c.moveToFirst());evidence.put("admissions",c.getInt(0))}
            }
        }
        val file=AtomicFile(File(filesDir,"failure-evidence.json"))
        val output=file.startWrite()
        try{output.write(evidence.toString().toByteArray());file.finishWrite(output)}catch(e:Throwable){file.failWrite(output);throw e}
    }
    private fun fail(error:Throwable){synchronized(this){evidence.put("failure",error.toString());record("failed")}}
    override fun serviceHostBinding(serviceContext:Context):ServiceHostBinding=error("owned_fixture_only")
    override fun acquireServiceHost(serviceContext:Context):ServiceHostLease {
        val lease=processOwner.acquire(serviceContext,call)
        root=privateAdmissionRoot(serviceContext)
        val installed=lease.binding as ServiceHostBinding.Installed
        val callback=object:ServiceHostOwnerSource by installed.owner {
            override fun reviewPayload(binding:ServiceOwnerAdmissionBinding,payload:ByteArray):Boolean {
                if(scenario=="Inflight") {
                    record("callbackHeld")
                    check(drain.await(30,TimeUnit.SECONDS)){"callback_drain_timeout"}
                }
                return installed.owner.reviewPayload(binding,payload)
            }
        }
        return ServiceHostLease(installed.copy(owner=callback),release={
            record("ownerCloseAttempt",true)
            if(scenario=="Owner" || scenario=="SetupOwner"){record("retainedFailure");error("fixed_owner_cleanup_failure")}
            lease.close();record("ownerClosed",true)
        },onReady={value->
            controller=value;record("ready")
            if(scenario=="Ready")error("fixed_on_ready_failure")
            if(scenario=="Inflight")Thread({
                try {
                    check(connectedClient.await(20,TimeUnit.SECONDS)){"client_connect_timeout"}
                    val result=value.serviceAdmissionProbe(ServiceAdmissionProbeOperation.PRIMARY_COMMIT)
                    check(result.admitted && result.recordId.isNotEmpty()){"native_admission_denied:${result.code}"}

                }catch(e:Throwable){fail(e)}
            },"fixed-native-admission").start()
        },hooks=this)
    }
    override fun connected(){connectedClient.countDown()}
    override fun probeReturned(){record("callbackReturned")}
    override fun acquired(){synchronized(this){acquiredCount++;record("acquired",true)};if(scenario=="Setup" || scenario=="SetupOwner")error("fixed_pre_native_setup_failure")}
    override fun constructed(){record("constructed");if(scenario=="Unknown"){record("retainedFailure");error("fixed_post_native_construction_uncertainty")}}
    override fun beforeNativeClose(){record("nativeCloseAttempt",true);if(scenario=="Native"){record("retainedFailure");error("fixed_native_cleanup_uncertainty")}}
    override fun nativeClosed(){record("nativeClosed",true)}
    override fun unavailable(){record("unavailable")}
    override fun replacementDenied(){record("replacementDenied")}
    override fun destroyed(){record("destroyed",true)}
    override fun destroyedReturned(){
        record("destroyedReturned",true)
        // Actual replacement's destruction follows assertions while the original callback is held.
        // No file/IPC/Intent controls this fixed schedule; both platform callbacks must return.
        if(scenario=="Inflight" && synchronized(this){evidence.optInt("destroyedReturned")>=2})drain.countDown()
    }
    override fun slotReleased(){
        controller?.let { value->
            val sealed=try{value.serviceAdmissionProbe(ServiceAdmissionProbeOperation.SECONDARY_COMMIT);false}catch(_:IllegalStateException){true}
            check(sealed){"native_admission_not_sealed"};record("sealed")
        }
        record("slotReleased",true)
    }
    private fun denied()=ServiceAdmissionAuthority.State(null,null,{_,_->false},{_,_,_->null})
    private fun approved(exists:Boolean=true):ServiceAdmissionAuthority.State {
        val profile=ServiceOwnerProfile("service-lifecycle-fixture-profile","https://service-lifecycle-fixture.invalid/v1",
            "service-lifecycle-fixture-endpoint","synthetic","service-lifecycle-fixture-model",ServiceOwnerLocation.OWN_DEVICE,
            ServiceOwnerPurpose.CHAT,"existence-only-fixture-ref",ServiceOwnerCapabilities(false,false),ServiceOwnerCapabilities(false,false))
        val quota=ServiceOwnerBudget("fixture-epoch-v1","fixture-ceiling-v1",1uL,32uL,4uL)
        val binding=ServiceOwnerAdmissionBinding(profile,"fixture-v1","fixture-v1","fixture-v1","service-lifecycle-fixture-owner",true,true,quota)
        val scope=ServiceOwnerScope("service-lifecycle-fixture-source","fixture", "/synthetic-metadata-only","new-admission-ledger",
            ServiceOwnerDecision("service-lifecycle-fixture-source","fixture",true,true,true,listOf("fixture"),"fixture-v1","fixture-v1","fixture-v1","fixture-v1","fixture",listOf(ServiceOwnerSelection("fixture","fixture-v1"))))
        val payload="""{"model":"service-lifecycle-fixture-model","messages":[{"role":"user","content":"synthetic admission metadata probe"}],"max_tokens":8,"n":1}""".toByteArray(Charsets.UTF_8)
        return ServiceAdmissionAuthority.State(scope,ServiceOwnerProvider(profile,binding.profileRevision,binding.policyRevision,
            binding.grantRevision,binding.authorizationOwner,true,true,quota,exists),
            {b,bytes->b==binding && bytes.contentEquals(payload)},
            {b,bytes,budget->if(b==binding && bytes.contentEquals(payload) && budget==call)"exact-fixture-full-call-proof-v1" else null})
    }
}
class SetupFailureApplication:FailureFixtureApplication("Setup")
class UnknownFailureApplication:FailureFixtureApplication("Unknown")
class OwnerFailureApplication:FailureFixtureApplication("Owner")
class NativeFailureApplication:FailureFixtureApplication("Native")
class InflightFailureApplication:FailureFixtureApplication("Inflight")
class ReadyFailureApplication:FailureFixtureApplication("Ready")

class SetupOwnerFailureApplication:FailureFixtureApplication("SetupOwner")
