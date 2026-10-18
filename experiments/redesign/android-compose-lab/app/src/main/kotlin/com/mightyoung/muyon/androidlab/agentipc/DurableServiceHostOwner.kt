package com.mightyoung.muyon.androidlab.agentipc

import android.content.ContentValues
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteException
import com.mightyoung.muyon.androidbridge.*
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.RandomAccessFile
import java.nio.channels.FileLock
import java.util.UUID
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/** Trusted in-process authority. All facts are immutable snapshots; every mutation uses replace().
 * Proof/review callbacks must be pure, non-reentrant and must not consult mutable unguarded facts.
 * A proof certifies conservative total input+output tokens and maximum spend for the EXACT call.
 * There is no default approval, token estimate, credential read, or installed production authority.
 */
internal class ServiceAdmissionAuthority(initial: State) {
    class State(val scope: ServiceOwnerScope?, val provider: ServiceOwnerProvider?,
                val payloadReview: (ServiceOwnerAdmissionBinding, ByteArray) -> Boolean,
                val budgetProof: (ServiceOwnerAdmissionBinding, ByteArray, ServiceOwnerCallBudget) -> String?)
    private val lock = ReentrantLock()
    private var state = snapshot(initial)
    private fun snapshot(s: State) = State(s.scope?.let { scope -> scope.copy(decision = scope.decision.copy(
        bindings = java.util.Collections.unmodifiableList(scope.decision.bindings.toList()), selected = java.util.Collections.unmodifiableList(scope.decision.selected.toList()))) },
        s.provider, s.payloadReview, s.budgetProof)
    fun replace(next: State) {
        check(!lock.isHeldByCurrentThread) { "Authority mutation during admission" }
        lock.withLock { state = snapshot(next) }
    }
    fun <T> guarded(block: (State) -> T): T {
        check(!lock.isHeldByCurrentThread) { "Reentrant authority operation" }
        return lock.withLock { block(state) }
    }
}

/** API26 SQLite prerequisite, not a production installation.
 * Dedicated new-schema file only. Never open an existing application/task database here.
 * Lock order: owner monitor -> authority guard -> SQLite transaction; guard remains held through
 * endTransaction. A process file lease rejects other processes and different authority objects.
 * Same authority may use multiple connections. No distributed authority protocol is supported.
 * remaining* is an immutable epoch CEILING, not a sampled balance. Reusing epoch IDs cannot reset it.
 * Raw request IDs, full payloads, bindings and proofs persist indefinitely, including expired rows.
 * No encryption, pruning, backups or production retention policy is provided by this component.
 */
internal class DurableServiceHostOwner(
    file: File,
    private val authority: ServiceAdmissionAuthority?,
    private val clock: () -> Long = System::currentTimeMillis,
    private val holdMillis: Long = 60_000L
) : ServiceHostOwnerSource, AutoCloseable {
    companion object { const val DATABASE_NAME = "muyon-admission-v1.sqlite" }
    private var db: SQLiteDatabase? = null
    private var lease: AdmissionLease? = null
    init {
        try {
            require(holdMillis > 0)
            require(authority != null)
            lease = AdmissionLeases.acquire(file, authority)
            val fresh = !file.exists()
            // A custom corruption handler must NEVER delete/recreate a damaged existing ledger.
            val opened = SQLiteDatabase.openDatabase(file.path, null,
                SQLiteDatabase.OPEN_READWRITE or (if (fresh) SQLiteDatabase.CREATE_IF_NECESSARY else 0),
                DatabaseErrorHandler { throw SQLiteException("Admission storage corrupted") })
            db = opened
            opened.beginTransaction()
            try {
                if (fresh) {
                    AdmissionSchema.tables.values.forEach { opened.execSQL(it) }
                    opened.execSQL("INSERT INTO clock_guard VALUES (1,0)")
                    opened.version = 1
                }
                require(opened.version == 1) { "Unsupported admission schema" }
                opened.rawQuery("PRAGMA quick_check", null).use { require(it.moveToFirst() && it.getString(0) == "ok") }
                AdmissionSchema.validate(opened)
                opened.rawQuery("SELECT high_water FROM clock_guard WHERE id=1", null).use { require(it.moveToFirst()) }
                opened.setTransactionSuccessful()
            } finally { opened.endTransaction() }
        } catch (_: Exception) { db?.close(); db = null; lease?.close(); lease = null }
    }
    @Synchronized override fun close() { db?.close(); db = null; lease?.close(); lease = null }
    private fun <T> read(block: (ServiceAdmissionAuthority.State) -> T): T? = try {
        if (db == null) null else authority?.guarded(block)
    } catch (_: Exception) { null }
    @Synchronized override fun currentScope() = read { it.scope }
    @Synchronized override fun currentProviderMetadata() = read { it.provider }
    @Synchronized override fun credentialHandleExists(profileId: String, credentialRef: String) = read {
        it.provider?.let { p -> p.credentialHandleAvailable && p.profile.id == profileId && p.profile.credentialRef == credentialRef } ?: false
    } ?: false
    private fun valid(s: ServiceAdmissionAuthority.State, b: ServiceOwnerAdmissionBinding): Boolean {
        val p = s.provider ?: return false
        val scope = s.scope ?: return false
        return scope.decision.allowed && scope.decision.available && scope.decision.scopeAllowed &&
            p.credentialHandleAvailable && b.modelAllowed && b.outboundAllowed &&
            b == ServiceOwnerAdmissionBinding(p.profile, p.profileRevision, p.policyRevision, p.grantRevision,
                p.authorizationOwner, p.modelAllowed, p.outboundAllowed, p.budget)
    }
    @Synchronized override fun reviewPayload(binding: ServiceOwnerAdmissionBinding, payload: ByteArray): Boolean = read {
        valid(it, binding) && it.payloadReview(binding, payload.copyOf())
    } ?: false

    private fun <T> transaction(block: (SQLiteDatabase, ServiceAdmissionAuthority.State, Long) -> T?): T? = try {
        val database = db
        if (database == null) null else authority?.guarded { state ->
            val now = clock()
            // Persist clock observation/expiry BEFORE fallible reserve/consume work. A duplicate,
            // proof exception or failed admission write must never erase an observed expiry.
            database.beginTransaction()
            var clockAccepted = false
            try {
                val water = database.rawQuery("SELECT high_water FROM clock_guard WHERE id=1", null).use {
                    check(it.moveToFirst()); it.getLong(0)
                }
                if (now >= 0 && now >= water) {
                    database.execSQL("UPDATE clock_guard SET high_water=? WHERE id=1", arrayOf(now))
                    database.execSQL("UPDATE reservations SET state='expired' WHERE state='held' AND expires<=?", arrayOf(now))
                    clockAccepted = true
                }
                database.setTransactionSuccessful()
            } finally { database.endTransaction() }
            if (!clockAccepted) null else {
                // The shared authority guard also excludes other supported connections between
                // these transactions. State consumption and admission metadata remain atomic.
                database.beginTransaction()
                try {
                    val result = block(database, state, now)
                    database.setTransactionSuccessful()
                    result
                } finally { database.endTransaction() }
            }
        }
    } catch (_: Exception) { null }

    @Synchronized override fun reserveBudget(binding: ServiceOwnerAdmissionBinding, requestId: String,
        payload: ByteArray, budget: ServiceOwnerCallBudget): String? {
        val bytes = payload.copyOf()
        return transaction { database, state, now ->
            if (requestId.isEmpty() || !valid(state, binding) || !state.payloadReview(binding, bytes.copyOf())) return@transaction null
            val proof = state.budgetProof(binding, bytes.copyOf(), budget)?.takeIf { it.isNotEmpty() } ?: return@transaction null
            val cap = binding.budget
            val calls = signed(cap.remainingCalls); val tokens = signed(cap.remainingTokens); val micros = signed(cap.remainingMicros)
            val costTokens = signed(budget.maxTokens); val costMicros = signed(budget.maxMicros)
            require(costTokens > 0 && costMicros > 0)
            val epoch = AdmissionEncoding.epoch(binding)
            val ceiling = AdmissionEncoding.ceiling(binding)
            database.rawQuery("SELECT ceiling FROM epochs WHERE epoch=?", arrayOf(epoch)).use { c ->
                if (c.moveToFirst()) require(c.getBlob(0).contentEquals(ceiling)) else {
                    database.insertOrThrow("epochs", null, ContentValues().apply { put("epoch", epoch); put("ceiling", ceiling) })
                }
            }
            var usedCalls = 0L; var usedTokens = 0L; var usedMicros = 0L
            database.rawQuery("SELECT tokens,micros FROM reservations WHERE epoch=? AND state IN ('held','consumed')", arrayOf(epoch)).use { c ->
                while (c.moveToNext()) {
                    usedCalls = Math.addExact(usedCalls, 1L)
                    usedTokens = Math.addExact(usedTokens, c.getLong(0))
                    usedMicros = Math.addExact(usedMicros, c.getLong(1))
                }
            }
            if (Math.addExact(usedCalls, 1L) > calls || Math.addExact(usedTokens, costTokens) > tokens || Math.addExact(usedMicros, costMicros) > micros) return@transaction null
            val token = UUID.randomUUID().toString()
            database.insertOrThrow("reservations", null, ContentValues().apply {
                put("token", token); put("request_id", AdmissionEncoding.textValue(requestId)); put("epoch", epoch)
                put("owner", binding.authorizationOwner); put("binding", AdmissionEncoding.binding(binding))
                put("scope", AdmissionEncoding.scope(state.scope!!)); put("payload", bytes)
                put("budget", AdmissionEncoding.callBudget(budget)); put("proof", AdmissionEncoding.textValue(proof))
                put("tokens", costTokens); put("micros", costMicros)
                put("expires", Math.addExact(now, holdMillis)); put("state", "held")
            })
            token
        }
    }

    @Synchronized override fun commitAdmission(reservation: String, binding: ServiceOwnerAdmissionBinding,
        requestId: String, payload: ByteArray, credentialProfileId: String, credentialRef: String): String? {
        val bytes = payload.copyOf()
        return transaction { database, state, _ ->
            if (!valid(state, binding) || credentialProfileId != binding.profile.id || credentialRef != binding.profile.credentialRef) return@transaction null
            database.rawQuery("SELECT request_id,owner,binding,scope,payload,budget,proof,state,epoch,tokens,micros FROM reservations WHERE token=?", arrayOf(reservation)).use { c ->
                if (!c.moveToFirst() || c.getString(7) != "held" || !c.getBlob(0).contentEquals(AdmissionEncoding.textValue(requestId)) ||
                    c.getString(1) != binding.authorizationOwner || !c.getBlob(2).contentEquals(AdmissionEncoding.binding(binding)) ||
                    !c.getBlob(3).contentEquals(AdmissionEncoding.scope(state.scope!!)) || !c.getBlob(4).contentEquals(bytes)) return@transaction null
                val budget = AdmissionEncoding.readCallBudget(c.getBlob(5))
                require(c.getString(8) == AdmissionEncoding.epoch(binding))
                require(c.getLong(9) == signed(budget.maxTokens) && c.getLong(10) == signed(budget.maxMicros))
                database.rawQuery("SELECT ceiling FROM epochs WHERE epoch=?", arrayOf(c.getString(8))).use { epoch ->
                    require(epoch.moveToFirst() && epoch.getBlob(0).contentEquals(AdmissionEncoding.ceiling(binding)))
                }
                if (!state.payloadReview(binding, bytes.copyOf())) return@transaction null
                val proof = state.budgetProof(binding, bytes.copyOf(), budget)?.takeIf { it.isNotEmpty() } ?: return@transaction null
                if (!c.getBlob(6).contentEquals(AdmissionEncoding.textValue(proof))) return@transaction null
                val id = UUID.randomUUID().toString()
                val changed = database.update("reservations", ContentValues().apply { put("state", "consumed") }, "token=? AND state='held'", arrayOf(reservation))
                check(changed == 1)
                database.insertOrThrow("admissions", null, ContentValues().apply { put("id", id); put("token", reservation) })
                id
            }
        }
    }
    /** Explicit cancellation uses the existing expired tombstone. Only held budget is refunded;
     * request_id remains unique forever, and consumed admissions can never be refunded.
     * Opaque unguessable reservation is a capability local to the bound native callback owner.
     */
    @Synchronized override fun releaseReservation(reservation: String): Boolean = transaction { database, _, _ ->
        database.update("reservations", ContentValues().apply { put("state", "expired") },
            "token=? AND state='held'", arrayOf(reservation)) == 1
    } ?: false

    private fun signed(n: ULong): Long { require(n <= Long.MAX_VALUE.toULong()); return n.toLong() }
}

/** Exact supported SQLite manifest, including automatically created constraint indexes.
 * Reject equivalent-but-different schemas rather than infer/repair constraints. Android's own
 * locale metadata is permitted only with its standard definition; it has no admission authority.
 */
private object AdmissionSchema {
    val tables = linkedMapOf(
        "epochs" to "CREATE TABLE epochs (epoch TEXT PRIMARY KEY, ceiling BLOB NOT NULL)",
        "clock_guard" to "CREATE TABLE clock_guard (id INTEGER PRIMARY KEY CHECK(id=1), high_water INTEGER NOT NULL)",
        "reservations" to "CREATE TABLE reservations (token TEXT PRIMARY KEY, request_id BLOB NOT NULL UNIQUE, epoch TEXT NOT NULL, owner TEXT NOT NULL, binding BLOB NOT NULL, scope BLOB NOT NULL, payload BLOB NOT NULL, budget BLOB NOT NULL, proof BLOB NOT NULL, tokens INTEGER NOT NULL, micros INTEGER NOT NULL, expires INTEGER NOT NULL, state TEXT NOT NULL CHECK(state IN ('held','consumed','expired')))",
        "admissions" to "CREATE TABLE admissions (id TEXT PRIMARY KEY, token TEXT NOT NULL UNIQUE REFERENCES reservations(token))")
    fun validate(db: SQLiteDatabase) {
        val expected = mutableMapOf<String, List<String?>>()
        tables.forEach { (name, sql) -> expected[name] = listOf("table", name, sql) }
        mapOf("epochs" to 1, "reservations" to 2, "admissions" to 2).forEach { (table, count) ->
            for (i in 1..count) expected["sqlite_autoindex_${table}_$i"] = listOf("index", table, null)
        }
        val actual = mutableMapOf<String, List<String?>>()
        db.rawQuery("SELECT type,name,tbl_name,sql FROM sqlite_master", null).use { c ->
            while (c.moveToNext()) {
                val name = c.getString(1)
                if (name == "android_metadata") {
                    require(c.getString(0) == "table" && c.getString(2) == name &&
                        c.getString(3) == "CREATE TABLE android_metadata (locale TEXT)")
                } else actual[name] = listOf(c.getString(0), c.getString(2), if (c.isNull(3)) null else c.getString(3))
            }
        }
        require(actual == expected) { "Unsupported admission schema manifest" }
    }
}

/** Versioned length-delimited UTF-16 code units preserve every Kotlin String, including surrogates. */
private object AdmissionEncoding {
    private fun encode(block: DataOutputStream.() -> Unit): ByteArray = ByteArrayOutputStream().also { out ->
        DataOutputStream(out).use { it.writeInt(1); it.block() }
    }.toByteArray()
    private fun DataOutputStream.text(s: String) { writeInt(s.length); s.forEach { writeChar(it.code) } }
    private fun DataOutputStream.cap(c: ServiceOwnerCapabilities) { writeBoolean(c.toolCalls); writeBoolean(c.streaming) }
    private fun DataOutputStream.quota(b: ServiceOwnerBudget) { text(b.revision); text(b.quotaProof); writeLong(b.remainingCalls.toLong()); writeLong(b.remainingTokens.toLong()); writeLong(b.remainingMicros.toLong()) }
    fun textValue(s: String) = encode { text(s) }
    fun epoch(b: ServiceOwnerAdmissionBinding) = encode { text(b.authorizationOwner); text(b.budget.revision); text(b.budget.quotaProof) }.joinToString("") { "%02x".format(it.toInt() and 255) }
    fun ceiling(b: ServiceOwnerAdmissionBinding) = encode { text(b.authorizationOwner); quota(b.budget) }
    fun binding(b: ServiceOwnerAdmissionBinding) = encode {
        val p = b.profile
        text(p.id); text(p.endpoint); text(p.endpointIdentity); text(p.provider); text(p.model)
        text(p.location.name); text(p.purpose.name); text(p.credentialRef); cap(p.declared); cap(p.tested)
        text(b.profileRevision); text(b.policyRevision); text(b.grantRevision); text(b.authorizationOwner)
        writeBoolean(b.modelAllowed); writeBoolean(b.outboundAllowed); quota(b.budget)
    }
    fun scope(s: ServiceOwnerScope) = encode {
        text(s.sourceIdentity); text(s.namespace); text(s.managedRoot); text(s.database)
        val d = s.decision
        text(d.sourceIdentity); text(d.namespace); writeBoolean(d.allowed); writeBoolean(d.available); writeBoolean(d.scopeAllowed)
        writeInt(d.bindings.size); d.bindings.forEach { text(it) }
        text(d.revision); text(d.bindingRevision); text(d.sourceRevision); text(d.ruleRevision); text(d.scope)
        writeInt(d.selected.size); d.selected.forEach { text(it.key); text(it.revision) }
    }
    fun callBudget(b: ServiceOwnerCallBudget) = encode { writeLong(b.maxTokens.toLong()); writeLong(b.maxMicros.toLong()); writeBoolean(b.requiresTools); writeBoolean(b.requiresStreaming) }
    fun readCallBudget(bytes: ByteArray): ServiceOwnerCallBudget = DataInputStream(ByteArrayInputStream(bytes)).use {
        require(it.readInt() == 1)
        val b = ServiceOwnerCallBudget(it.readLong().toULong(), it.readLong().toULong(), it.readBoolean(), it.readBoolean())
        require(it.available() == 0); b
    }
}

private class AdmissionLease(val authority: ServiceAdmissionAuthority, val handle: RandomAccessFile, val lock: FileLock, val path: String) : AutoCloseable {
    var users = 1
    override fun close() = AdmissionLeases.release(this)
}
private object AdmissionLeases {
    private val entries = mutableMapOf<String, AdmissionLease>()
    @Synchronized fun acquire(file: File, authority: ServiceAdmissionAuthority): AdmissionLease {
        val path = file.canonicalPath
        entries[path]?.let { require(it.authority === authority) { "Independent authority unsupported" }; it.users++; return it }
        val handle = RandomAccessFile("$path.owner-lock", "rw")
        try {
            val lock = handle.channel.tryLock() ?: error("Admission database owned by another process")
            return AdmissionLease(authority, handle, lock, path).also { entries[path] = it }
        } catch (e: Exception) { handle.close(); throw e }
    }
    @Synchronized fun release(lease: AdmissionLease) {
        if (--lease.users == 0) { entries.remove(lease.path); try { lease.lock.release() } finally { lease.handle.close() } }
    }
}
