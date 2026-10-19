package com.mightyoung.muyon.androidlab.agentipc

import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest
import com.mightyoung.muyon.androidlab.agentipc.OrdinaryChatCanaryBudget.TokenProof
import com.mightyoung.muyon.androidlab.agentipc.OrdinaryChatCanaryBudget.FullPayloadProofVerifier
import com.mightyoung.muyon.androidlab.agentipc.OrdinaryChatCanaryBudget.Permit
import com.mightyoung.muyon.androidlab.agentipc.OrdinaryChatCanaryBudget.Usage
import com.mightyoung.muyon.androidlab.agentipc.OrdinaryChatCanaryBudget.Refused

private typealias Budget = OrdinaryChatCanaryBudget
private fun proof(wire: ByteArray, tokens: Long) = TokenProof("fixture-trusted-tokenizer-v1",
    MessageDigest.getInstance("SHA-256").digest(wire).joinToString("") { "%02x".format(it) }, tokens)
private val fixtureVerifier = FullPayloadProofVerifier { _, _ -> true }
private fun fresh() = Budget.provisionNewBatch(Files.createTempDirectory("offline-canary-budget-"))
private fun reserve(b: Budget, id: String, tokens: Long = 10, wire: ByteArray = id.toByteArray()) =
    b.reserve(id, wire, proof(wire, tokens), "CNY", fixtureVerifier)
private fun denied(action: () -> Unit) {
    try { action(); error("expected refusal") } catch (e: Refused) {
        check(e.message == "canary_budget_refused" && e.cause == null)
    }
}
private fun pass(b: Budget, permit: Permit, tokens: Long = 10) {
    b.handoff(permit); b.success(permit, Usage(tokens, 2, tokens * 2 + 16, "CNY"))
}
private fun child(vararg args: String) = ProcessBuilder(listOf(
    Path.of(System.getProperty("java.home"), "bin", "java").toString(), "-cp", System.getProperty("java.class.path"),
    "com.mightyoung.muyon.androidlab.agentipc.Ordinary_chat_canary_budget_testKt") + args).redirectError(ProcessBuilder.Redirect.INHERIT).start()
private fun finished(process: Process): Int {
    check(process.waitFor(20, java.util.concurrent.TimeUnit.SECONDS)); return process.exitValue()
}

fun main(args: Array<String>) {
    if (args.size >= 2 && args[0] == "kill-pending") {
        val b = Budget.openExisting(Path.of(args[1])); val p = reserve(b, "killed-pending"); b.handoff(p)
        println("READY"); System.out.flush(); Thread.sleep(60000); error("parent must kill pending process")
    }
    if (args.size == 3 && args[0] == "contend") {
        val dir = Path.of(args[1]); val b = Budget.openExisting(dir)
        println("READY"); System.out.flush()
        while (!Files.exists(dir.resolve("start"))) Thread.sleep(10)
        try { reserve(b, args[2]); println("RESERVED") } catch (_: Refused) { println("REFUSED") }
        return
    }
    // Separate process used solely to prove reopening cannot reset a pending batch.
    if (args.size == 2 && args[0] == "reopen") {
        val b = Budget.openExisting(Path.of(args[1])); check(b.snapshot().stopped)
        denied { reserve(b, "after-epoch-change") }; return
    }
    var count = 0
    fun test(name: String, action: () -> Unit) { action(); count++; println("PASS $name") }
    test("complete payload history bound and mismatch") {
        val b = fresh(); val full = "user:first;assistant:remember-blue;user:what-color".toByteArray()
        val p = reserve(b, "history", 1000, full); check(p.reservedMicroCny == 3024L)
        val wrong = proof("user:what-color".toByteArray(), 5)
        denied { b.reserve("wrong", full, wrong, "CNY", fixtureVerifier) }
    }
    test("missing currency proof verifier and false verifier") {
        val b = fresh(); val wire = byteArrayOf(1)
        denied { b.reserve("missing", wire, null, "CNY", fixtureVerifier) }
        denied { b.reserve("currency", wire, proof(wire, 10), "USD", fixtureVerifier) }
        denied { b.reserve("verifier", wire, proof(wire, 10), "CNY", null) }
        denied { b.reserve("false", wire, proof(wire, 10), "CNY", FullPayloadProofVerifier { _, _ -> false }) }
        denied { b.reserve("mutating", wire, proof(wire, 10), "CNY", FullPayloadProofVerifier { supplied, _ -> supplied[0] = 9; true }) }
        check(b.snapshot().attempts == 0)
    }
    test("insufficient funds and overflow fail before attempt") {
        val b = fresh(); denied { reserve(b, "too-much", 500000) }; denied { reserve(b, "overflow", Long.MAX_VALUE) }
        check(b.snapshot().attempts == 0)
        val p = reserve(b, "large", 400000); pass(b, p)
        denied { reserve(b, "remaining", 100000) }; check(b.snapshot().attempts == 1)
    }
    test("two attempts lifetime ceiling duplicate identity payload and third") {
        val b = fresh(); val first = reserve(b, "one"); pass(b, first)
        denied { reserve(b, "one") }; denied { reserve(b, "same-wire", wire = "one".toByteArray()) }
        val second = reserve(b, "two"); pass(b, second)
        denied { reserve(b, "three") }; check(b.snapshot().attempts == 2 && b.snapshot().reservedMicroCny == 2088L)
    }
    test("pre and post handoff cancellation timeout late success cannot release stop") {
        for (handoff in listOf(false, true)) {
            val b = fresh(); val p = reserve(b, "cancel"); if (handoff) b.handoff(p)
            b.stop(p); val reserved = b.snapshot().reservedMicroCny
            denied { b.success(p, Usage(10, 2, 36, "CNY")) }
            denied { b.handoff(p) }; denied { reserve(b, "retry") }
            check(b.snapshot().stopped && b.snapshot().reservedMicroCny == reserved)
        }
    }
    test("missing malformed out-of-bounds usage stops batch") {
        for (usage in listOf(Usage(11, 1, 10, "CNY"), Usage(10, 129, 10, "CNY"),
            Usage(10, 1, -1, "CNY"), Usage(10, 1, 1, "USD"))) {
            val b = fresh(); val p = reserve(b, "bad-usage"); b.handoff(p)
            denied { b.success(p, usage) }; check(b.snapshot().stopped)
        }
        val b = fresh(); val p = reserve(b, "missing-usage"); b.handoff(p); b.stop(p)
        check(b.snapshot().states == listOf("unknown"))
    }
    test("separate process reopen pending to unknown independent of epoch") {
        val dir = Files.createTempDirectory("offline-reopen-"); val b = Budget.provisionNewBatch(dir)
        val p = reserve(b, "pending"); b.handoff(p)
        val child = ProcessBuilder(Path.of(System.getProperty("java.home"), "bin", "java").toString(),
            "-cp", System.getProperty("java.class.path"), "com.mightyoung.muyon.androidlab.agentipc.Ordinary_chat_canary_budget_testKt", "reopen", dir.toString())
            .inheritIO().start()
        check(child.waitFor() == 0); check(b.snapshot().stopped && b.snapshot().reservedMicroCny == p.reservedMicroCny)
        denied { b.success(p, Usage(10, 1, 28, "CNY")) }
    }
    test("success mutation faults before after rename and directory force remain stopped across processes") {
        for (stage in listOf("before_rename", "after_rename", "ledger_directory_force")) {
            val dir = Files.createTempDirectory("offline-fault-"); val b = Budget.provisionNewBatch(dir)
            val p = reserve(b, "fault"); b.handoff(p)
            b.faultInjector = { at -> if (at == stage) throw java.io.IOException("private diagnostic must not escape") }
            denied { b.success(p, Usage(10, 1, 28, "CNY")) }
            check(Files.exists(dir.resolve("ordinary-chat-canary-20261019.in-progress")))
            denied { reserve(b, "same-process-after-fault") }
            check(Files.exists(dir.resolve("ordinary-chat-canary-20261019.in-progress")))
            val reopened = child("reopen", dir.toString()); check(finished(reopened) == 0)
            b.faultInjector = null
            check(b.snapshot().stopped && b.snapshot().reservedMicroCny == p.reservedMicroCny)
            denied { reserve(b, "after-fault") }
        }
    }
    test("real process kill after durable handoff preserves reservation and stop") {
        val dir = Files.createTempDirectory("offline-kill-"); Budget.provisionNewBatch(dir)
        val pending = child("kill-pending", dir.toString())
        check(pending.inputStream.bufferedReader().readLine() == "READY")
        pending.destroyForcibly(); check(finished(pending) != 0)
        val b = Budget.openExisting(dir)
        check(b.snapshot().stopped && b.snapshot().attempts == 1 && b.snapshot().reservedMicroCny == 1044L)
        denied { reserve(b, "retry-killed") }
    }
    test("concurrent processes share one file lock and cannot both reserve") {
        val dir = Files.createTempDirectory("offline-contention-"); Budget.provisionNewBatch(dir)
        val contenders = listOf(child("contend", dir.toString(), "left"), child("contend", dir.toString(), "right"))
        val readers = contenders.map { it.inputStream.bufferedReader() }
        check(readers.all { it.readLine() == "READY" }); Files.createFile(dir.resolve("start"))
        val outcomes = readers.map { it.readLine() }
        check(contenders.all { finished(it) == 0 })
        check(outcomes.count { it == "RESERVED" } == 1 && outcomes.count { it == "REFUSED" } == 1)
        val b = Budget.openExisting(dir); check(b.snapshot().attempts == 1 && b.snapshot().stopped)
    }
    test("corrupt missing oversized ledger and recreation fail closed") {
        for (mode in listOf("corrupt", "missing", "oversized")) {
            val dir = Files.createTempDirectory("offline-corruption-"); Budget.provisionNewBatch(dir)
            val ledger = dir.resolve("ordinary-chat-canary-20261019.ledger")
            when (mode) {
                "corrupt" -> Files.write(ledger, byteArrayOf(1, 2, 3))
                "missing" -> Files.delete(ledger)
                else -> Files.write(ledger, ByteArray(4097))
            }
            denied { Budget.openExisting(dir) }; denied { Budget.provisionNewBatch(dir) }
        }
    }
    println("$count offline canary budget groups passed; zero network requests")
}
