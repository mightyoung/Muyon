package com.mightyoung.muyon.androidlab.agentipc

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.os.Process
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
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
    private var schedulePhase=0
    private var probeAttempts=0
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
        probeAttempts=0
        val root=privateAdmissionRoot(checkNotNull(serviceContext))
        val primaryStarted=started(root,PRIMARY_STARTED)
        val exhaustionStarted=started(root,EXHAUSTION_STARTED)
        check(!exhaustionStarted || primaryStarted){"fixture_schedule_invalid"}
        schedulePhase=when {
            !primaryStarted -> { markStarted(root,PRIMARY_STARTED);1 }
            !exhaustionStarted -> { markStarted(root,EXHAUSTION_STARTED);2 }
            else -> 3
        }
        if(schedulePhase==1) {
            // Same actual installed callback owner begins with no approval facts.
            record("unconfiguredDenied",probe(controller,ServiceAdmissionProbeOperation.PRIMARY_COMMIT),false)
            authority.replace(approved())
            val cancelled=probe(controller,ServiceAdmissionProbeOperation.PRIMARY_CANCEL)
            results.put("cancelReleased",!cancelled.admitted && cancelled.code=="release_requested")
            record("cancelReplayDenied",probe(controller,ServiceAdmissionProbeOperation.PRIMARY_COMMIT),false)
            authority.replace(approved(exists=false))
            record("credentialRevokedDenied",probe(controller,ServiceAdmissionProbeOperation.SECONDARY_COMMIT),false)
            authority.replace(approved())
            val committed=probe(controller,ServiceAdmissionProbeOperation.SECONDARY_COMMIT)
            record("secondaryAdmitted",committed,true)
            admissionIdentity=committed.recordId
        } else if(schedulePhase==2) {
            // Fixed fixture authority comes from this compile-time installer, never from markers.
            authority.replace(approved())
            // Explicit fixed test-only NEW request after restart; primary/secondary are never replayed.
            record("restartExhaustedDenied",probe(controller,ServiceAdmissionProbeOperation.TERTIARY_COMMIT),false)
        }
        // Both durable started markers mean no probes, including after fresh process startup.
        // A crash anywhere after a marker is created permanently skips its original schedule.
        writeEvidence()
    }
    private fun probe(controller:GeneratedAgentController,operation:ServiceAdmissionProbeOperation):ServiceAdmissionProbeReply {
        probeAttempts++
        return controller.serviceAdmissionProbe(operation)
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
            check(admissions<=1){"fixture_admission_count_invalid"}
            // Opaque receipt comes from the durable ledger; prior evidence never grants authority.
            db.rawQuery("SELECT a.id FROM admissions a JOIN reservations r ON r.token=a.token WHERE r.state='consumed'",null).use { c->
                admissionIdentity=if(c.moveToFirst())c.getString(0) else ""
                check(!c.moveToNext()){"fixture_admission_count_invalid"}
            }
        }
        val json=JSONObject().put("protocol",1).put("synthetic",true).put("complete",true)
            .put("pid",Process.myPid()).put("bootstrapOrdinal",ordinal).put("nativeCleaned",cleaned)
            .put("leaseClosed",cleaned).put("admissionIdentity",admissionIdentity).put("results",results)
            .put("held",counts["held"]).put("consumed",counts["consumed"]).put("expired",counts["expired"])
            .put("admissions",admissions).put("restartProbeCount",if(schedulePhase==2)1 else 0)
            .put("schedulePhase",schedulePhase).put("probeAttempts",probeAttempts)
            .put("phase1Started",started(root,PRIMARY_STARTED)).put("phase2Started",started(root,EXHAUSTION_STARTED))
        val file=AtomicFile(File(root,"lifecycle-evidence.json"))
        val stream=file.startWrite()
        try{stream.write(json.toString().toByteArray(Charsets.UTF_8));file.finishWrite(stream)}catch(error:Throwable){file.failWrite(stream);throw error}
    }
    /** Fixed private scheduling receipts only. They cannot provide approval or reset quota.
     * Persist the started receipt BEFORE invoking native; interrupted schedules are never retried.
     */
    private fun markStarted(root:File,name:String) {
        val fd=Os.open(File(root,name).absolutePath,
            OsConstants.O_WRONLY or OsConstants.O_CREAT or OsConstants.O_EXCL or OsConstants.O_NOFOLLOW,384)
        try {
            var offset=0
            while(offset<MARKER_BYTES.size) {
                val written=Os.write(fd,MARKER_BYTES,offset,MARKER_BYTES.size-offset)
                check(written>0){"fixture_schedule_unavailable"};offset+=written
            }
            Os.fsync(fd)
        } finally { Os.close(fd) }
        val directory=Os.open(root.absolutePath,OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW,0)
        try {
            // O_DIRECTORY is not an Android public SDK constant. Verify the opened descriptor
            // itself before syncing, using only API21+ public APIs on the API26 fixture.
            val stat=Os.fstat(directory)
            check((stat.st_mode and OsConstants.S_IFMT)==OsConstants.S_IFDIR &&
                stat.st_uid==Process.myUid() && (stat.st_mode and 4095)==448){"fixture_schedule_root_invalid"}
            Os.fsync(directory)
        } finally { Os.close(directory) }
    }
    private fun started(root:File,name:String):Boolean {
        val fd=try { Os.open(File(root,name).absolutePath,OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW,0) }
        catch(error:ErrnoException){if(error.errno==OsConstants.ENOENT)return false else throw error}
        try {
            val stat=Os.fstat(fd)
            check((stat.st_mode and OsConstants.S_IFMT)==OsConstants.S_IFREG && stat.st_uid==Process.myUid() &&
                (stat.st_mode and 4095)==384 && stat.st_size==MARKER_BYTES.size.toLong()){"fixture_schedule_invalid"}
            val bytes=ByteArray(MARKER_BYTES.size)
            var offset=0
            while(offset<bytes.size) {
                val count=Os.read(fd,bytes,offset,bytes.size-offset)
                check(count>0){"fixture_schedule_invalid"};offset+=count
            }
            check(bytes.contentEquals(MARKER_BYTES)){"fixture_schedule_invalid"}
            return true
        } finally { Os.close(fd) }
    }
    private companion object {
        const val PRIMARY_STARTED="lifecycle-primary-started-v1"
        const val EXHAUSTION_STARTED="lifecycle-exhaustion-started-v1"
        val MARKER_BYTES="synthetic-schedule-started-v1\n".toByteArray(Charsets.UTF_8)
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
