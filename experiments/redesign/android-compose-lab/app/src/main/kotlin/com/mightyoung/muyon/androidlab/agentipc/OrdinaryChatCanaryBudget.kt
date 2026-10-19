package com.mightyoung.muyon.androidlab.agentipc

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.nio.channels.FileChannel
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption
import java.security.MessageDigest

/** Offline accounting only. The owner must call handoff before any network side effect. */
internal class OrdinaryChatCanaryBudget private constructor(private val directory: Path) {
    data class TokenProof(val identity: String, val payloadSha256: String, val fullInputTokenUpperBound: Long)

    /** A trusted installation fact, NOT a byte/character counter or a caller assertion.
     * Must validate the exact full wire, model/template/tokenizer, and max_tokens=128.
     * Missing or unverified evidence must return false. No permissive implementation is supplied.
     */
    fun interface FullPayloadProofVerifier {
        fun verify(payload: ByteArray, proof: TokenProof): Boolean
    }

    data class Permit(val request: String, val payloadSha256: String, val reservedMicroCny: Long)
    /** Reported evidence only; this component cannot verify the supplier's account invoice. */
    data class Usage(val inputTokens: Long, val outputTokens: Long, val reportedFeeMicroCny: Long, val currency: String)
    data class Snapshot(val attempts: Int, val reservedMicroCny: Long, val stopped: Boolean, val states: List<String>, val usage: List<Usage?>)
    data class Record(val permit: Permit, val state: String, val usage: Usage?)
    class Refused internal constructor() : IllegalStateException("canary_budget_refused")

    private data class Entry(val request: String, val digest: String, val proof: String, val input: Long,
                             val reserved: Long, var state: String, var usage: Usage? = null)
    private data class Ledger(var stopped: Boolean, val entries: MutableList<Entry>)
    private val ledgerPath get() = directory.resolve("ordinary-chat-canary-20261019.ledger")
    private val lockPath get() = directory.resolve("ordinary-chat-canary-20261019.lock")
    private val mutationPath get() = directory.resolve("ordinary-chat-canary-20261019.in-progress")
    // Trusted offline tests only; never supplied by an IPC/network caller.
    internal var faultInjector: ((String) -> Unit)? = null

    fun reserve(request: String, payload: ByteArray, proof: TokenProof?, currency: String?,
                verifier: FullPayloadProofVerifier?): Permit = guarded {
        require(request.matches(ID) && payload.isNotEmpty() && payload.size <= MAX_PAYLOAD)
        require(currency == "CNY" && proof != null && verifier != null)
        val wire = payload.copyOf()
        require(proof.identity.matches(ID) && proof.payloadSha256 == sha(wire) && proof.fullInputTokenUpperBound > 0)
        val verificationWire = wire.copyOf()
        require(verifier.verify(verificationWire, proof) && verificationWire.contentEquals(wire) && sha(wire) == proof.payloadSha256)
        val reserve = Math.addExact(Math.multiplyExact(proof.fullInputTokenUpperBound, INPUT_RATE), OUTPUT_CAP * OUTPUT_RATE)
        val ledger = read()
        require(!ledger.stopped && ledger.entries.size < ATTEMPT_LIMIT)
        require(ledger.entries.none { it.request == request || it.digest == proof.payloadSha256 })
        require(ledger.entries.none { it.state == "reserved" || it.state == "handed_off" })
        require(reserve <= CEILING - total(ledger))
        ledger.entries.add(Entry(request, proof.payloadSha256, proof.identity, proof.fullInputTokenUpperBound, reserve, "reserved"))
        write(ledger)
        Permit(request, proof.payloadSha256, reserve)
    }

    fun handoff(permit: Permit) = guarded {
        val ledger = read(); val entry = entry(ledger, permit)
        require(!ledger.stopped && entry.state == "reserved")
        entry.state = "handed_off"; write(ledger)
    }

    fun success(permit: Permit, usage: Usage) = guarded {
        val ledger = read(); val entry = entry(ledger, permit)
        val valid = !ledger.stopped && entry.state == "handed_off" && usage.currency == "CNY" &&
            usage.inputTokens in 1..entry.input && usage.outputTokens in 0..OUTPUT_CAP &&
            usage.reportedFeeMicroCny >= 0 && usage.reportedFeeMicroCny <= entry.reserved &&
            usage.reportedFeeMicroCny <= usage.inputTokens * INPUT_RATE + usage.outputTokens * OUTPUT_RATE
        if (!valid) {
            entry.state = "unknown"; ledger.stopped = true; write(ledger); throw Refused()
        }
        entry.state = "success"; entry.usage = usage; write(ledger)
    }

    /** Timeout, missing usage, cancellation (even before handoff), or late reply. Never refunds. */
    fun stop(permit: Permit) = guarded {
        val ledger = read(); val entry = entry(ledger, permit)
        entry.state = "unknown"; ledger.stopped = true; write(ledger)
    }

    fun snapshot(): Snapshot = guarded {
        val ledger = read()
        Snapshot(ledger.entries.size, total(ledger), ledger.stopped, ledger.entries.map { it.state }, ledger.entries.map { it.usage })
    }

    /** Local correlation only; never resumes a pending send or manufactures a new permit. */
    fun record(request: String): Record? = guarded {
        read().entries.singleOrNull { it.request == request }?.let {
            Record(Permit(it.request, it.digest, it.reserved), it.state, it.usage)
        }
    }

    private fun entry(ledger: Ledger, permit: Permit): Entry = ledger.entries.single {
        it.request == permit.request && it.digest == permit.payloadSha256 && it.reserved == permit.reservedMicroCny
    }

    private fun total(ledger: Ledger) = ledger.entries.fold(0L) { sum, entry -> Math.addExact(sum, entry.reserved) }

    private fun <T> guarded(action: () -> T): T = sanitized {
        require(Files.isRegularFile(lockPath) && !Files.isSymbolicLink(lockPath))
        val channel = FileChannel.open(lockPath, StandardOpenOption.WRITE)
        var lock: java.nio.channels.FileLock? = null
        try {
            lock = channel.lock()
            if (Files.exists(mutationPath)) {
                val ledger = read(); ledger.stopped = true
                ledger.entries.forEach { it.state = "unknown" }
                write(ledger)
            }
            action()
        } finally {
            // A release/close failure cannot turn an already durable commit into an ambiguous failure.
            try { lock?.release() } catch (_: Exception) { }
            try { channel.close() } catch (_: Exception) { }
        }
    }

    private fun read(): Ledger {
        require(Files.isRegularFile(ledgerPath) && !Files.isSymbolicLink(ledgerPath))
        require(Files.size(ledgerPath) in 33..MAX_LEDGER.toLong())
        val bytes = FileChannel.open(ledgerPath, StandardOpenOption.READ).use { channel ->
            val buffer = java.nio.ByteBuffer.allocate(MAX_LEDGER + 1)
            while (buffer.hasRemaining() && channel.read(buffer) >= 0) { /* bounded even if file grows */ }
            require(buffer.position() in 33..MAX_LEDGER)
            buffer.array().copyOf(buffer.position())
        }
        val body = bytes.copyOfRange(0, bytes.size - 32)
        require(MessageDigest.isEqual(MessageDigest.getInstance("SHA-256").digest(body), bytes.copyOfRange(body.size, bytes.size)))
        return DataInputStream(ByteArrayInputStream(body)).use { input ->
            require(input.readUTF() == BATCH && input.readInt() == 1)
            require(input.readLong() == CEILING && input.readInt() == ATTEMPT_LIMIT)
            require(input.readLong() == INPUT_RATE && input.readLong() == OUTPUT_RATE && input.readLong() == OUTPUT_CAP)
            val stopped = input.readUnsignedByte(); require(stopped in 0..1)
            val count = input.readInt(); require(count in 0..ATTEMPT_LIMIT)
            val entries = mutableListOf<Entry>()
            repeat(count) {
                val request = input.readUTF(); val digest = input.readUTF(); val proof = input.readUTF()
                val tokens = input.readLong(); val reserve = input.readLong(); val state = input.readUTF()
                require(request.matches(ID) && digest.matches(DIGEST) && proof.matches(ID) && tokens > 0)
                require(reserve == Math.addExact(Math.multiplyExact(tokens, INPUT_RATE), OUTPUT_CAP * OUTPUT_RATE))
                require(reserve in 1..CEILING && state in setOf("reserved", "handed_off", "success", "unknown"))
                val hasUsage = input.readUnsignedByte(); require(hasUsage in 0..1)
                val usage = if (hasUsage == 1) Usage(input.readLong(), input.readLong(), input.readLong(), input.readUTF()) else null
                require(state != "success" || usage != null)
                if (usage != null) require(usage.currency == "CNY" && usage.inputTokens in 1..tokens &&
                    usage.outputTokens in 0..OUTPUT_CAP && usage.reportedFeeMicroCny in 0..reserve &&
                    usage.reportedFeeMicroCny <= usage.inputTokens * INPUT_RATE + usage.outputTokens * OUTPUT_RATE)
                entries.add(Entry(request, digest, proof, tokens, reserve, state, usage))
            }
            require(input.available() == 0 && entries.map { it.request }.distinct().size == count && entries.map { it.digest }.distinct().size == count)
            Ledger(stopped == 1, entries).also {
                require(total(it) <= CEILING && (entries.none { e -> e.state == "unknown" } || it.stopped))
            }
        }
    }

    private fun write(ledger: Ledger) {
        val body = ByteArrayOutputStream().also { bytes -> DataOutputStream(bytes).use { output ->
            output.writeUTF(BATCH); output.writeInt(1); output.writeLong(CEILING); output.writeInt(ATTEMPT_LIMIT)
            output.writeLong(INPUT_RATE); output.writeLong(OUTPUT_RATE); output.writeLong(OUTPUT_CAP)
            output.writeByte(if (ledger.stopped) 1 else 0); output.writeInt(ledger.entries.size)
            ledger.entries.forEach { entry ->
                output.writeUTF(entry.request); output.writeUTF(entry.digest); output.writeUTF(entry.proof)
                output.writeLong(entry.input); output.writeLong(entry.reserved); output.writeUTF(entry.state)
                output.writeByte(if (entry.usage == null) 0 else 1)
                entry.usage?.let { output.writeLong(it.inputTokens); output.writeLong(it.outputTokens); output.writeLong(it.reportedFeeMicroCny); output.writeUTF(it.currency) }
            }
        } }.toByteArray()
        val bytes = body + MessageDigest.getInstance("SHA-256").digest(body); require(bytes.size <= MAX_LEDGER)
        // Monotonic uncertainty marker is durable BEFORE changing the ledger. Any failure leaves it.
        require(!Files.isSymbolicLink(mutationPath))
        FileChannel.open(mutationPath, StandardOpenOption.CREATE, StandardOpenOption.WRITE).use { it.force(true) }
        FileChannel.open(directory, StandardOpenOption.READ).use { it.force(true) }
        val temporary = Files.createTempFile(directory, ".canary-", ".pending")
        try {
            FileChannel.open(temporary, StandardOpenOption.WRITE).use { channel ->
                val buffer = java.nio.ByteBuffer.wrap(bytes); while (buffer.hasRemaining()) channel.write(buffer)
                channel.force(true)
            }
            faultInjector?.invoke("before_rename")
            Files.move(temporary, ledgerPath, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
            faultInjector?.invoke("after_rename")
            faultInjector?.invoke("ledger_directory_force")
            FileChannel.open(directory, StandardOpenOption.READ).use { it.force(true) }
        } finally { Files.deleteIfExists(temporary) }
        // No fallible operation after removal. If deletion is lost on crash, recovery only stops more.
        Files.delete(mutationPath)
    }

    companion object {
        const val BATCH = "muyon-ordinary-chat-20261019-cny1-two-requests"
        const val CEILING = 1_000_000L
        const val ATTEMPT_LIMIT = 2
        const val INPUT_RATE = 2L
        const val OUTPUT_RATE = 8L
        const val OUTPUT_CAP = 128L
        private const val MAX_LEDGER = 4096
        private const val MAX_PAYLOAD = 1_048_576
        private val ID = Regex("[A-Za-z0-9_-]{1,128}")
        private val DIGEST = Regex("[0-9a-f]{64}")
        private fun sha(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        private fun <T> sanitized(action: () -> T): T = try { action() } catch (_: Exception) { throw Refused() }

        /** Explicit one-time installation. An existing marker blocks recreation after loss/corruption. */
        fun provisionNewBatch(stablePrivateDirectory: Path): OrdinaryChatCanaryBudget = sanitized {
            require(Files.isDirectory(stablePrivateDirectory) && !Files.isSymbolicLink(stablePrivateDirectory))
            val budget = OrdinaryChatCanaryBudget(stablePrivateDirectory)
            require(!Files.exists(budget.ledgerPath))
            FileChannel.open(budget.lockPath, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE).use { channel ->
                channel.force(true)
                channel.lock().use { budget.write(Ledger(false, mutableListOf())) }
            }
            budget
        }

        /** No epoch or credential generation parameter: the caller must use one stable private directory. */
        fun openExisting(stablePrivateDirectory: Path): OrdinaryChatCanaryBudget = sanitized {
            val budget = OrdinaryChatCanaryBudget(stablePrivateDirectory)
            budget.guarded {
                val ledger = budget.read()
                if (ledger.entries.any { it.state == "reserved" || it.state == "handed_off" }) {
                    ledger.entries.filter { it.state == "reserved" || it.state == "handed_off" }.forEach { it.state = "unknown" }
                    ledger.stopped = true; budget.write(ledger)
                }
            }
            budget
        }
    }
}
