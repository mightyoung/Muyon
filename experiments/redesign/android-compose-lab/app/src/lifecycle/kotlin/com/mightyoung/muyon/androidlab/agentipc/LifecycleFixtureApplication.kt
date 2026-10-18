package com.mightyoung.muyon.androidlab.agentipc

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.os.Process
import android.util.AtomicFile
import com.mightyoung.muyon.androidbridge.*
import com.mightyoung.muyon.androidlab.MuyonLabApplication
import org.json.JSONObject
import java.io.File

/** Compile-time instrumentation composition. This class is absent from ordinary builds.
 * No Intent, Binder, environment, arbitrary file or runtime flag chooses these approval facts.
 */
@Suppress("EXPOSED_FUNCTION_RETURN_TYPE")
class LifecycleFixtureApplication:MuyonLabApplication() {
    private val call=ServiceOwnerCallBudget(32uL,4uL,false,false)
    private val authority=ServiceAdmissionAuthority(denied())
    private val owner=ServiceAdmissionProcessOwner(authority)
    private var ordinal=0
    private var cleaned=0
    private var admissionIdentity=""
    private val results=JSONObject()
    private var serviceContext:Context?=null
    override fun serviceHostBinding(serviceContext:Context):ServiceHostBinding =
        error("lifecycle_requires_owned_lease")
    override fun acquireServiceHost(serviceContext:Context):ServiceHostLease {
        this.serviceContext=serviceContext.applicationContext
        return owner.acquire(serviceContext,call,onReady={controller->ready(controller)},onCleaned={
            synchronized(this){cleaned++;writeEvidence()}
        })
    }
    @Synchronized private fun ready(controller:GeneratedAgentController) {
        ordinal++
        if(ordinal==1) {
            // Same actual installed callback owner begins with no approval facts.
            record("unconfiguredDenied",controller.serviceAdmissionProbe(ServiceAdmissionProbeOperation.PRIMARY_COMMIT),false)
            authority.replace(approved())
            val cancelled=controller.serviceAdmissionProbe(ServiceAdmissionProbeOperation.PRIMARY_CANCEL)
            results.put("cancelReleased",!cancelled.admitted && cancelled.code=="release_requested")
            record("cancelReplayDenied",controller.serviceAdmissionProbe(ServiceAdmissionProbeOperation.PRIMARY_COMMIT),false)
            authority.replace(approved(exists=false))
            record("credentialRevokedDenied",controller.serviceAdmissionProbe(ServiceAdmissionProbeOperation.SECONDARY_COMMIT),false)
            authority.replace(approved())
            val committed=controller.serviceAdmissionProbe(ServiceAdmissionProbeOperation.SECONDARY_COMMIT)
            record("secondaryAdmitted",committed,true)
            admissionIdentity=committed.recordId
        } else if(ordinal==2) {
            // Explicit fixed test-only NEW request after restart; primary/secondary are never replayed.
            record("restartExhaustedDenied",controller.serviceAdmissionProbe(ServiceAdmissionProbeOperation.TERTIARY_COMMIT),false)
        }
        // Recreated Service never re-submits primary/secondary; only this fixed quota check runs.
        writeEvidence()
    }
    private fun record(key:String,reply:ServiceAdmissionProbeReply,expected:Boolean) {
        results.put(key,reply.admitted==expected && if(expected)reply.recordId.isNotEmpty() else reply.recordId.isEmpty())
        results.put(key+"Code",reply.code)
    }
    private fun writeEvidence() {
        val context=checkNotNull(serviceContext)
        val root=privateAdmissionRoot(context)
        val counts=mutableMapOf("held" to 0,"consumed" to 0,"expired" to 0)
        var admissions=0
        SQLiteDatabase.openDatabase(File(root,DurableServiceHostOwner.DATABASE_NAME).path,null,SQLiteDatabase.OPEN_READONLY).use { db->
            db.rawQuery("SELECT state,COUNT(*) FROM reservations GROUP BY state",null).use { c->while(c.moveToNext())counts[c.getString(0)]=c.getInt(1)}
            db.rawQuery("SELECT COUNT(*) FROM admissions",null).use { c->check(c.moveToFirst());admissions=c.getInt(0)}
        }
        val json=JSONObject().put("protocol",1).put("synthetic",true).put("complete",true)
            .put("pid",Process.myPid()).put("bootstrapOrdinal",ordinal).put("nativeCleaned",cleaned)
            .put("leaseClosed",cleaned).put("admissionIdentity",admissionIdentity).put("results",results)
            .put("held",counts["held"]).put("consumed",counts["consumed"]).put("expired",counts["expired"])
            .put("admissions",admissions).put("restartProbeCount",if(ordinal>=2)1 else 0)
        val file=AtomicFile(File(root,"lifecycle-evidence.json"))
        val stream=file.startWrite()
        try{stream.write(json.toString().toByteArray(Charsets.UTF_8));file.finishWrite(stream)}catch(error:Throwable){file.failWrite(stream);throw error}
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
