package com.mightyoung.muyon.androidlab.agentipc

import android.app.ActivityManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.database.sqlite.SQLiteDatabase
import android.os.Binder
import android.os.IBinder
import android.os.Process
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.core.app.ActivityScenario
import com.mightyoung.muyon.androidlab.MainActivity
import com.mightyoung.muyon.androidlab.BuildConfig
import com.mightyoung.muyon.androidlab.UiAgentWireReply
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Only the compile-time lifecycle APK runs this named acceptance. No test installs an owner,
 * selects approval through IPC, sends model traffic, kills a process or touches a legacy DB.
 */
class LifecycleServiceAdmissionTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val root get() = File(context.filesDir, "agent-admission-root")
    private val evidence get() = File(root, "lifecycle-evidence.json")
    private val ledger get() = File(root, "muyon-admission-v1.sqlite")

    private fun awaitEvidence(predicate: (JSONObject) -> Boolean): JSONObject {
        val end = SystemClock.elapsedRealtime() + 60_000
        while (SystemClock.elapsedRealtime() < end) {
            val value = try { JSONObject(evidence.readText()) } catch (_: Exception) { null }
            if (value != null && predicate(value)) return value
            SystemClock.sleep(50)
        }
        fail("Timed out waiting for bounded lifecycle evidence: ${if (evidence.exists()) evidence.readText() else "absent"}")
        error("unreachable")
    }

    private class Binding(private val context: Context) : AutoCloseable {
        val liveness = Binder()
        private val connected = CountDownLatch(1)
        private var bound = false
        private var binder: IBinder? = null
        private val connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName, service: IBinder) {
                binder = service; connected.countDown()
            }
            override fun onServiceDisconnected(name: ComponentName) = Unit
        }
        init {
            bound = context.bindService(Intent(context, AgentRuntimeService::class.java), connection, Context.BIND_AUTO_CREATE)
            check(bound && connected.await(30, TimeUnit.SECONDS)) { "private Service failed to bind" }
        }
        val remote: IAgentRuntime get() = IAgentRuntime.Stub.asInterface(checkNotNull(binder))
        override fun close() { if (bound) { context.unbindService(connection); bound = false } }
    }

    private data class Rows(val expired: Int, val consumed: Int, val held: Int, val admissions: List<String>)
    private fun rows(): Rows = SQLiteDatabase.openDatabase(ledger.path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
        assertEquals("dedicated v1 ledger", 1, db.version)
        val states = mutableMapOf<String, Int>()
        db.rawQuery("SELECT state,count(*) FROM reservations GROUP BY state", null).use { c ->
            while (c.moveToNext()) states[c.getString(0)] = c.getInt(1)
        }
        val ids = db.rawQuery("SELECT id FROM admissions ORDER BY id", null).use { c ->
            buildList { while (c.moveToNext()) add(c.getString(0)) }
        }
        Rows(states["expired"] ?: 0, states["consumed"] ?: 0, states["held"] ?: 0, ids)
    }

    private fun connect(binding: Binding): UiAgentWireReply.Connected {
        val deadline = SystemClock.elapsedRealtime() + 30_000
        while (SystemClock.elapsedRealtime() < deadline) {
            val reply = binding.remote.connect(binding.liveness).decode(BuildConfig.MUYON_BRIDGE_SOURCE_SHA)
            if (reply is UiAgentWireReply.Connected) return reply
            SystemClock.sleep(50)
        }
        error("private Service failed to initialize")
    }

    @Test fun actualPrivateServiceUsesOneDurableOwnerAndRetainsAdmissionAfterNormalRebind() {
        assertEquals("compile-time isolated test APK", "com.mightyoung.muyon.androidlab.lifecycle", context.packageName)
        assertFalse("acceptance requires fresh app data", evidence.exists())
        val first = Binding(context)
        try {
            connect(first)
            val initial = awaitEvidence { it.optBoolean("complete") && it.optInt("bootstrapOrdinal") == 1 }
            val pid = initial.getInt("pid")
            val processes = (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).runningAppProcesses.orEmpty()
            val agent = processes.single { it.processName == "${context.packageName}:agent" }
            assertEquals(pid, agent.pid)
            assertEquals(Process.myUid(), agent.uid)
            assertNotEquals(Process.myPid(), pid)
            assertEquals(1, initial.getInt("protocol"))
            assertTrue(initial.getBoolean("synthetic"))
            val results = initial.getJSONObject("results")
            for (key in listOf("unconfiguredDenied", "cancelReleased", "cancelReplayDenied", "credentialRevokedDenied", "secondaryAdmitted")) {
                assertTrue("fixed native probe must prove $key", results.getBoolean(key))
            }
            assertEquals("provider_config_unavailable", results.getString("unconfiguredDeniedCode"))
            assertEquals("provider_budget_reservation_failed", results.getString("cancelReplayDeniedCode"))
            assertEquals("provider_credential_unavailable", results.getString("credentialRevokedDeniedCode"))
            assertEquals("admitted_metadata_only", results.getString("secondaryAdmittedCode"))
            assertEquals(0, initial.getInt("restartProbeCount"))
            assertEquals(1, initial.getInt("schedulePhase"))
            assertEquals(5, initial.getInt("probeAttempts"))
            assertTrue(initial.getBoolean("phase1Started"))
            assertFalse(initial.getBoolean("phase2Started"))
            val before = rows()
            assertEquals("cancellation leaves one replay tombstone", 1, before.expired)
            assertEquals(1, before.consumed)
            assertEquals(0, before.held)
            assertEquals(1, before.admissions.size)
            assertEquals(before.admissions.single(), initial.getString("admissionIdentity"))
            ActivityScenario.launch(MainActivity::class.java).use { activity ->
                activity.recreate()
                InstrumentationRegistry.getInstrumentation().waitForIdleSync()
                val retained = awaitEvidence { it.optBoolean("complete") }
                assertEquals("Activity recreation must retain the Service owner", 1, retained.getInt("bootstrapOrdinal"))
                assertEquals(0, retained.getInt("nativeCleaned"))
                assertEquals(0, retained.getInt("leaseClosed"))
                assertEquals(before, rows())
            }
            first.close()
            awaitEvidence { it.optInt("nativeCleaned") >= 1 && it.optInt("leaseClosed") >= 1 }
            Binding(context).use { second ->
                connect(second)
                val restarted = awaitEvidence { it.optBoolean("complete") && it.optInt("bootstrapOrdinal") == 2 }
                assertEquals("normal Service restart remains in same private process", pid, restarted.getInt("pid"))
                assertEquals(1, restarted.getInt("restartProbeCount"))
                assertEquals(2, restarted.getInt("schedulePhase"))
                assertEquals(1, restarted.getInt("probeAttempts"))
                assertTrue(restarted.getBoolean("phase1Started"))
                assertTrue(restarted.getBoolean("phase2Started"))
                assertTrue(restarted.getJSONObject("results").getBoolean("restartExhaustedDenied"))
                assertEquals("provider_budget_reservation_failed", restarted.getJSONObject("results").getString("restartExhaustedDeniedCode"))
                assertEquals(before.admissions.single(), restarted.getString("admissionIdentity"))
                assertEquals("reconnect must preserve quota, receipt and tombstones without auto-submit", before, rows())
                println("API26_SERVICE_LIFECYCLE_PASS agent_pid=$pid bootstrap_count=2 admissions=1 consumed=1 held=0 expired=${before.expired} admission_identity=${before.admissions.single()} normal_rebind=true model_api_called=false")
            }
            awaitEvidence { it.optInt("nativeCleaned") >= 2 && it.optInt("leaseClosed") >= 2 }
            // Only this fresh fixture APK's own private child, after native and owner cleanup.
            // No original app state, legacy database, shell script, HTTP or model is involved.
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val target = manager.runningAppProcesses.orEmpty().single { it.processName == "${context.packageName}:agent" }
            check(context.packageName == "com.mightyoung.muyon.androidlab.lifecycle")
            check(target.processName == "com.mightyoung.muyon.androidlab.lifecycle:agent")
            check(target.uid == Process.myUid() && target.pid == pid && target.pid != Process.myPid())
            Process.killProcess(target.pid)
            val goneDeadline = SystemClock.elapsedRealtime() + 30_000
            while (SystemClock.elapsedRealtime() < goneDeadline && manager.runningAppProcesses.orEmpty().any {
                    it.pid == target.pid && it.uid == Process.myUid() && it.processName == "${context.packageName}:agent"
                }) SystemClock.sleep(50)
            assertFalse("fresh fixture child must disappear before reconnect", manager.runningAppProcesses.orEmpty().any {
                it.pid == target.pid && it.uid == Process.myUid() && it.processName == "${context.packageName}:agent"
            })
            Binding(context).use { recreated ->
                connect(recreated)
                val afterDeath = awaitEvidence {
                    it.optBoolean("complete") && it.optInt("schedulePhase") == 3 && it.optInt("pid") != pid
                }
                val newPid = afterDeath.getInt("pid")
                val newAgent = manager.runningAppProcesses.orEmpty().single { it.processName == "${context.packageName}:agent" }
                assertEquals(newPid, newAgent.pid)
                assertEquals(Process.myUid(), newAgent.uid)
                assertNotEquals(Process.myPid(), newPid)
                assertEquals(1, afterDeath.getInt("bootstrapOrdinal"))
                assertEquals("durable schedule must run zero probes after process recreation", 0, afterDeath.getInt("probeAttempts"))
                assertTrue(afterDeath.getBoolean("phase1Started"))
                assertTrue(afterDeath.getBoolean("phase2Started"))
                assertEquals("process-local results must not inherit old proof", 0, afterDeath.getJSONObject("results").length())
                assertEquals(before.admissions.single(), afterDeath.getString("admissionIdentity"))
                assertEquals("process recreation preserves the same admission and tombstones", before, rows())
                println("API26_SERVICE_PROCESS_RECREATION_PASS old_agent_pid=$pid new_agent_pid=$newPid schedule_phase=3 probe_attempts=0 admission_identity=${before.admissions.single()} synthetic=true model_api_called=false")
            }
            awaitEvidence { it.optInt("schedulePhase") == 3 && it.optInt("nativeCleaned") >= 1 && it.optInt("leaseClosed") >= 1 }
        } finally {
            first.close()
        }
    }
}
