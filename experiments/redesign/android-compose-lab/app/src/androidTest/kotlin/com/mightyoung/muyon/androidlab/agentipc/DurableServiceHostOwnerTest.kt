package com.mightyoung.muyon.androidlab.agentipc

import android.database.sqlite.SQLiteDatabase
import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.androidbridge.*
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Fresh synthetic SQLite files only. No native library, HTTP, credentials or old state. */
class DurableServiceHostOwnerTest {
    private val payload = byteArrayOf(0, -1, 127, 10)
    private val call = ServiceOwnerCallBudget(7uL, 11uL, true, true)
    private fun binding() = ServiceOwnerAdmissionBinding(
        ServiceOwnerProfile("p", "https://synthetic.invalid/v1", "e", "synthetic", "m",
            ServiceOwnerLocation.OWN_DEVICE, ServiceOwnerPurpose.CHAT, "opaque-ref",
            ServiceOwnerCapabilities(true, true), ServiceOwnerCapabilities(true, true)),
        "pr", "policy", "grant", "owner", true, true,
        ServiceOwnerBudget("epoch", "quota", 2uL, 14uL, 22uL))
    private fun scope() = ServiceOwnerScope("source", "ns", "/synthetic", "new-ledger",
        ServiceOwnerDecision("source", "ns", true, true, true, listOf("x"), "r", "b", "s", "rule", "scope", listOf(ServiceOwnerSelection("x", "r"))))
    private fun state(b: ServiceOwnerAdmissionBinding = binding(), exists: Boolean = true,
                      proof: String? = "full-call-proof") = ServiceAdmissionAuthority.State(scope(),
        ServiceOwnerProvider(b.profile, b.profileRevision, b.policyRevision, b.grantRevision,
            b.authorizationOwner, b.modelAllowed, b.outboundAllowed, b.budget, exists),
        payloadReview = { binding, bytes -> binding == b && bytes.contentEquals(payload) }) { binding, bytes, budget ->
        if (binding == b && bytes.contentEquals(payload) && budget == call) proof else null
    }
    private fun file(): File = File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir,
        "synthetic-admission-${UUID.randomUUID()}.sqlite")
    private fun commit(o: DurableServiceHostOwner, token: String, b: ServiceOwnerAdmissionBinding = binding(),
                       request: String = "r", bytes: ByteArray = payload) =
        o.commitAdmission(token, b, request, bytes, b.profile.id, b.profile.credentialRef)
    private fun owner(f: File, a: ServiceAdmissionAuthority?, clock: () -> Long = { 100L }) =
        DurableServiceHostOwner(f, a, clock, holdMillis = 10L)

    @Test fun exact_full_budget_survives_close_and_commit_is_one_shot() {
        val f = file(); val a = ServiceAdmissionAuthority(state()); val b = binding()
        val first = owner(f, a)
        assertEquals(b.budget, first.currentProviderMetadata()!!.budget)
        val token = first.reserveBudget(b, "r", payload, call)!!
        first.close()
        owner(f, a).use { second ->
            assertNotNull(commit(second, token))
            assertNull(commit(second, token))
            assertNull(second.reserveBudget(b, "r", payload, call))
            val other = second.reserveBudget(b, "r2", payload, call)!!
            assertNotNull(commit(second, other, request = "r2"))
            assertNull(second.reserveBudget(b, "r3", payload, call))
        }
    }

    @Test fun exact_tuple_and_original_bytes_are_required_without_consuming_hold() {
        val f = file(); val a = ServiceAdmissionAuthority(state()); val b = binding()
        owner(f, a).use { o ->
            val token = o.reserveBudget(b, "r", payload, call)!!
            assertNull(commit(o, token, bytes = payload + 0))
            assertNull(commit(o, token, request = "different"))
            assertNull(o.commitAdmission(token, b, "r", payload, "wrong", b.profile.credentialRef))
            assertNull(o.commitAdmission(token, b, "r", payload, b.profile.id, "wrong"))
            assertNull(commit(o, token, b.copy(profile = b.profile.copy(endpointIdentity = "different"))))
            assertNull(commit(o, token, b.copy(budget = b.budget.copy(remainingMicros = 23uL))))
            assertNotNull(commit(o, token))
        }
    }

    @Test fun stale_authority_and_credential_revocation_deny() {
        val a = ServiceAdmissionAuthority(state()); val b = binding()
        owner(file(), a).use { o ->
            val token = o.reserveBudget(b, "r", payload, call)!!
            a.replace(state(b.copy(policyRevision = "revoked")))
            assertNull(commit(o, token))
            a.replace(state(exists = false))
            assertFalse(o.credentialHandleExists("p", "opaque-ref"))
            assertNull(commit(o, token))
            a.replace(state(proof = null))
            assertNull(commit(o, token))
        }
    }

    @Test fun complete_call_budget_requires_exact_trusted_proof() {
        owner(file(), ServiceAdmissionAuthority(state())).use { o ->
            assertTrue(o.reviewPayload(binding(), payload))
            assertFalse(o.reviewPayload(binding(), payload + 0))
            for (bad in listOf(call.copy(maxTokens = 6uL), call.copy(maxMicros = 10uL),
                call.copy(requiresTools = false), call.copy(requiresStreaming = false))) {
                assertNull(o.reserveBudget(binding(), UUID.randomUUID().toString(), payload, bad))
            }
        }
    }

    @Test fun two_connections_share_holds_consumed_quota_and_immutable_ceiling() {
        val f = file(); val a = ServiceAdmissionAuthority(state()); val b = binding()
        owner(f, a).use { one -> owner(f, a).use { two ->
            val pool = Executors.newFixedThreadPool(2)
            try {
                val tokens = pool.invokeAll((1..4).map { n -> java.util.concurrent.Callable {
                    (if (n % 2 == 0) one else two).reserveBudget(b, "r$n", payload, call)
                }}).map { it.get(5, TimeUnit.SECONDS) }
                assertEquals(2, tokens.count { it != null })
                val enlarged = b.copy(budget = b.budget.copy(remainingCalls = 100uL, remainingTokens = 700uL, remainingMicros = 1100uL))
                a.replace(state(enlarged))
                assertNull(two.reserveBudget(enlarged, "ceiling-reset", payload, call))
            } finally { pool.shutdownNow() }
        }}
    }

    @Test fun expiry_and_clock_rollback_never_resurrect_and_requests_stay_unique() {
        var now = 100L; val f = file(); val a = ServiceAdmissionAuthority(state())
        val first = owner(f, a) { now }
        val token = first.reserveBudget(binding(), "r", payload, call)!!
        now = 111L
        assertNull(commit(first, token))
        first.close(); now = 99L
        owner(f, a) { now }.use { o ->
            assertNull(commit(o, token))
            assertNull(o.reserveBudget(binding(), "new", payload, call))
            now = 112L
            assertNull(o.reserveBudget(binding(), "r", payload, call))
            assertNotNull(o.reserveBudget(binding(), "fresh", payload, call))
        }
    }

    @Test fun transaction_failure_rolls_back_consumption_and_admission() {
        val f = file(); val a = ServiceAdmissionAuthority(state())
        owner(f, a).use { o ->
            val token = o.reserveBudget(binding(), "r", payload, call)!!
            SQLiteDatabase.openDatabase(f.path, null, SQLiteDatabase.OPEN_READWRITE).use { db ->
                db.execSQL("CREATE TRIGGER synthetic_failure BEFORE INSERT ON admissions BEGIN SELECT RAISE(ABORT, 'synthetic'); END")
            }
            assertNull(commit(o, token))
            SQLiteDatabase.openDatabase(f.path, null, SQLiteDatabase.OPEN_READWRITE).use { db ->
                db.rawQuery("SELECT state FROM reservations", null).use { c ->
                    assertTrue(c.moveToFirst()); assertEquals("held", c.getString(0))
                }
                db.rawQuery("SELECT count(*) FROM admissions", null).use { c -> c.moveToFirst(); assertEquals(0, c.getInt(0)) }
                db.execSQL("DROP TRIGGER synthetic_failure")
            }
            assertNotNull(commit(o, token))
        }
    }

    @Test fun missing_authority_bad_schema_corruption_and_unsigned_overflow_fail_closed() {
        owner(file(), null).use { assertNull(it.reserveBudget(binding(), "r", payload, call)) }
        val f = file()
        SQLiteDatabase.openOrCreateDatabase(f, null).use { it.version = 77 }
        owner(f, ServiceAdmissionAuthority(state())).use { assertNull(it.currentProviderMetadata()) }
        assertEquals(77, SQLiteDatabase.openDatabase(f.path, null, SQLiteDatabase.OPEN_READONLY).use { it.version })
        val corrupt = file(); corrupt.writeBytes(byteArrayOf(1, 2, 3, 4))
        owner(corrupt, ServiceAdmissionAuthority(state())).use { assertNull(it.currentScope()) }
        assertArrayEquals(byteArrayOf(1, 2, 3, 4), corrupt.readBytes())
        val huge = binding().copy(budget = binding().budget.copy(remainingTokens = ULong.MAX_VALUE))
        owner(file(), ServiceAdmissionAuthority(state(huge))).use { assertNull(it.reserveBudget(huge, "r", payload, call)) }
    }
    @Test fun mutation_waits_until_guarded_commit_finishes() {
        val entered = java.util.concurrent.CountDownLatch(1)
        val release = java.util.concurrent.CountDownLatch(1)
        val mutationStarted = java.util.concurrent.CountDownLatch(1)
        val mutationDone = java.util.concurrent.CountDownLatch(1)
        val a = ServiceAdmissionAuthority(state())
        owner(file(), a).use { o ->
            val token = o.reserveBudget(binding(), "r", payload, call)!!
            a.replace(ServiceAdmissionAuthority.State(scope(), state().provider,
                payloadReview = { _, _ -> true }) { b, bytes, budget ->
                assertEquals(binding(), b); assertArrayEquals(payload, bytes); assertEquals(call, budget)
                entered.countDown(); check(release.await(5, TimeUnit.SECONDS)); "full-call-proof"
            })
            val pool = Executors.newFixedThreadPool(2)
            try {
                val admission = pool.submit<String?> { commit(o, token) }
                assertTrue(entered.await(5, TimeUnit.SECONDS))
                val mutation = pool.submit {
                    mutationStarted.countDown(); a.replace(state(exists = false)); mutationDone.countDown()
                }
                assertTrue(mutationStarted.await(5, TimeUnit.SECONDS))
                assertFalse(mutationDone.await(150, TimeUnit.MILLISECONDS))
                release.countDown()
                assertNotNull(admission.get(5, TimeUnit.SECONDS))
                mutation.get(5, TimeUnit.SECONDS)
                assertFalse(o.credentialHandleExists("p", "opaque-ref"))
            } finally { release.countDown(); pool.shutdownNow() }
        }
    }

    @Test fun independent_authority_is_denied_while_database_is_owned() {
        val f = file(); val a = ServiceAdmissionAuthority(state())
        owner(f, a).use { first ->
            owner(f, ServiceAdmissionAuthority(state())).use { other -> assertNull(other.currentScope()) }
            assertNotNull(first.reserveBudget(binding(), "r", payload, call))
        }
    }

    @Test fun scope_and_proof_changes_invalidate_a_stored_hold() {
        val a = ServiceAdmissionAuthority(state())
        owner(file(), a).use { o ->
            val token = o.reserveBudget(binding(), "r", payload, call)!!
            a.replace(ServiceAdmissionAuthority.State(scope().copy(namespace = "changed"), state().provider,
                payloadReview = { _, _ -> true }) { _, _, _ -> "full-call-proof" })
            assertNull(commit(o, token))
            a.replace(state(proof = "different-proof"))
            assertNull(commit(o, token))
        }
    }

    @Test fun duplicate_failure_after_expiry_cannot_resurrect_on_rollback_and_reconstruction() {
        var now = 100L
        val f = file(); val a = ServiceAdmissionAuthority(state())
        val first = owner(f, a) { now }
        val token = first.reserveBudget(binding(), "r", payload, call)!!
        now = 111L
        assertNull(first.reserveBudget(binding(), "r", payload, call))
        first.close()
        now = 105L
        owner(f, a) { now }.use { reopened ->
            assertNull(commit(reopened, token))
            assertNull(reopened.reserveBudget(binding(), "rollback", payload, call))
        }
        SQLiteDatabase.openDatabase(f.path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
            db.rawQuery("SELECT high_water FROM clock_guard WHERE id=1", null).use { c ->
                assertTrue(c.moveToFirst()); assertEquals(111L, c.getLong(0))
            }
            db.rawQuery("SELECT state FROM reservations", null).use { c ->
                assertTrue(c.moveToFirst()); assertEquals("expired", c.getString(0))
            }
        }
    }

    @Test fun missing_request_unique_in_otherwise_v1_schema_is_rejected_without_repair() {
        val a = ServiceAdmissionAuthority(state()); val seed = file()
        owner(seed, a).close()
        val ddl = SQLiteDatabase.openDatabase(seed.path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
            db.rawQuery("SELECT sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name", null).use { c ->
                buildList { while (c.moveToNext()) add(c.getString(0)) }
            }
        }
        val malformed = file()
        SQLiteDatabase.openOrCreateDatabase(malformed, null).use { db ->
            ddl.forEach { sql -> db.execSQL(sql.replace("request_id BLOB NOT NULL UNIQUE", "request_id BLOB NOT NULL")) }
            db.execSQL("INSERT INTO clock_guard VALUES (1,0)")
            db.version = 1
        }
        val originalBytes = malformed.readBytes()
        owner(malformed, a).use { o ->
            assertNull(o.currentProviderMetadata())
            assertNull(o.reserveBudget(binding(), "r", payload, call))
        }
        assertArrayEquals(originalBytes, malformed.readBytes())
        SQLiteDatabase.openDatabase(malformed.path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
            assertEquals(1, db.version)
            db.rawQuery("SELECT sql FROM sqlite_master WHERE name='reservations'", null).use { c ->
                assertTrue(c.moveToFirst()); assertFalse(c.getString(0).contains("request_id BLOB NOT NULL UNIQUE"))
            }
        }
    }

    @Test fun exact_expiry_boundary_denies_and_releases_only_the_hold() {
        var now = 100L; val a = ServiceAdmissionAuthority(state())
        owner(file(), a) { now }.use { o ->
            val token = o.reserveBudget(binding(), "r", payload, call)!!
            now = 110L
            assertNull(commit(o, token))
            assertNull(o.reserveBudget(binding(), "r", payload, call))
            assertNotNull(o.reserveBudget(binding(), "fresh", payload, call))
        }
    }

    @Test fun each_quota_dimension_independently_limits_consumed_calls_after_reopen_and_refresh() {
        val ceilings = listOf(
            ServiceOwnerBudget("epoch", "quota", 1uL, 700uL, 1100uL),
            ServiceOwnerBudget("epoch", "quota", 100uL, 7uL, 1100uL),
            ServiceOwnerBudget("epoch", "quota", 100uL, 700uL, 11uL))
        for (ceiling in ceilings) {
            val b = binding().copy(budget = ceiling); val a = ServiceAdmissionAuthority(state(b)); val f = file()
            owner(f, a).use { first ->
                val token = first.reserveBudget(b, "r", payload, call)!!
                assertNotNull(commit(first, token, b))
            }
            a.replace(state(b))
            owner(f, a).use { reopened ->
                assertEquals(ceiling, reopened.currentProviderMetadata()!!.budget)
                assertNull(reopened.reserveBudget(b, "fresh", payload, call))
                assertNull(reopened.reserveBudget(b, "r", payload, call))
            }
        }
    }

    @Test fun competing_connections_admit_once_and_reject_duplicate_requests_and_replay() {
        val f = file(); val a = ServiceAdmissionAuthority(state())
        owner(f, a).use { one -> owner(f, a).use { two ->
            val token = one.reserveBudget(binding(), "r", payload, call)!!
            val start = java.util.concurrent.CountDownLatch(1)
            val pool = Executors.newFixedThreadPool(2)
            try {
                val commits = listOf(one, two).map { o -> pool.submit<String?> {
                    check(start.await(5, TimeUnit.SECONDS)); commit(o, token)
                } }
                start.countDown()
                assertEquals(1, commits.count { it.get(5, TimeUnit.SECONDS) != null })
                assertNull(commit(one, token)); assertNull(commit(two, token))
                val duplicates = listOf(one, two).map { o -> pool.submit<String?> {
                    o.reserveBudget(binding(), "r", payload, call)
                } }
                assertTrue(duplicates.all { it.get(5, TimeUnit.SECONDS) == null })
            } finally { start.countDown(); pool.shutdownNow() }
        }}
    }

}
