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
private const val OLD_SHA = "0743f051b0291623240dd4c10f8f0260f04b74ef1197a4279af13bbbfbcf3fc7"
private const val FOLLOWUP_DIR = "ordinary-chat-authorized-followup-20261020"
private const val FOLLOWUP_ONCE = "ordinary-chat-authorized-followup-20261020.once"
private const val LEDGER = "ordinary-chat-canary-20261019.ledger"
private fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
/** Exact public stopped-ledger fixture; contains identities/accounting only, no payload or credential. */
private fun priorFixture(): Path {
    val root = Files.createDirectory(Files.createTempDirectory("offline-followup-").resolve("original"))
    Budget.provisionNewBatch(root)
    val body = java.io.ByteArrayOutputStream().also { bytes -> java.io.DataOutputStream(bytes).use { out ->
        out.writeUTF(Budget.BATCH); out.writeInt(1); out.writeLong(Budget.CEILING); out.writeInt(2)
        out.writeLong(2); out.writeLong(8); out.writeLong(128); out.writeByte(1); out.writeInt(1)
        out.writeUTF("chat_eb1eeb36ef9748c7900f5eb810622d00")
        out.writeUTF("0d75468fbd364a8a6809e47880d3b329813207547b5c368d1de38fa86478e80b")
        out.writeUTF("deepseek-flash-1017-full-prompt-bound-cny-v1")
        out.writeLong(143); out.writeLong(1310); out.writeUTF("unknown"); out.writeByte(0)
    } }.toByteArray()
    val bytes = body + MessageDigest.getInstance("SHA-256").digest(body)
    check(digest(bytes) == OLD_SHA)
    Files.write(root.resolve(LEDGER), bytes)
    return root
}
private fun unchanged(root: Path) { check(digest(Files.readAllBytes(root.resolve(LEDGER))) == OLD_SHA) }

fun main(args: Array<String>) {
    if (args.size == 3 && args[0] == "followup-contend") {
        val root = Path.of(args[1]); val b = Budget.openAuthorizedFollowup(root)
        println("READY"); System.out.flush()
        while (!Files.exists(root.resolve("start"))) Thread.sleep(10)
        try { reserve(b, args[2]); println("RESERVED") } catch (_: Refused) { println("REFUSED") }
        return
    }
    if (args.size == 2 && args[0] == "followup-reopen") {
        val b = Budget.openAuthorizedFollowup(Path.of(args[1]))
        check(b.snapshot().stopped && b.snapshot().reservedMicroCny == 1044L)
        denied { reserve(b, "no-followup-retry") }; return
    }
    if (args.size == 2 && args[0] == "followup-kill") {
        val b = Budget.openAuthorizedFollowup(Path.of(args[1])); val p = reserve(b, "followup-killed"); b.handoff(p)
        println("READY"); System.out.flush(); Thread.sleep(60000); error("parent must kill")
    }
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
    test("authorized followup exact original unchanged two new attempts third refused") {
        val root = priorFixture(); val original = Budget.openExisting(root)
        check(original.snapshot().stopped && original.snapshot().reservedMicroCny == 1310L)
        val b = Budget.openAuthorizedFollowup(root)
        check(Files.list(root).use { paths -> paths.allMatch { Files.isRegularFile(it) } })
        check(Files.getPosixFilePermissions(root.parent.resolve(FOLLOWUP_DIR)) ==
            java.nio.file.attribute.PosixFilePermissions.fromString("rwx------"))
        check(b.batchIdentity == "muyon-ordinary-chat-20261020-authorized-followup" && b.ceilingMicroCny == 998690L)
        check(original.batchIdentity == Budget.BATCH && original.ceilingMicroCny == Budget.CEILING)
        denied { reserve(b, "chat_eb1eeb36ef9748c7900f5eb810622d00") }
        pass(b, reserve(b, "followup-one")); pass(b, reserve(b, "followup-two"))
        denied { reserve(b, "followup-three") }
        val s = Budget.openAuthorizedFollowup(root).snapshot()
        check(s.attempts + original.snapshot().attempts == 3 && s.reservedMicroCny + 1310 == 3398L)
        denied { reserve(original, "old-never-reopens") }; unchanged(root)
    }
    test("authorized cumulative ceiling exact fit and insufficient retained reserves") {
        val root = priorFixture(); val b = Budget.openAuthorizedFollowup(root)
        denied { reserve(b, "too-large", 498834) }; check(b.snapshot().attempts == 0)
        val exact = reserve(b, "exact-ceiling", 498833); check(exact.reservedMicroCny + 1310 == Budget.CEILING)
        pass(b, exact); denied { reserve(b, "no-remaining") }; unchanged(root)
        val another = priorFixture(); val c = Budget.openAuthorizedFollowup(another)
        pass(c, reserve(c, "retained", 400000)); denied { reserve(c, "insufficient", 100000) }
        check(c.snapshot().attempts == 1); unchanged(another)
    }
    test("authorized unknown stays stopped across process and epoch no resend") {
        val root = priorFixture(); val b = Budget.openAuthorizedFollowup(root); val p = reserve(b, "new-unknown")
        b.handoff(p); b.stop(p)
        check(finished(child("followup-reopen", root.toString())) == 0)
        denied { b.success(p, Usage(10, 1, 28, "CNY")) }; denied { reserve(b, "new-retry") }
        check(b.snapshot().stopped && b.snapshot().reservedMicroCny == 1044L); unchanged(root)
    }
    test("authorized pending process death stops only new round without refund") {
        val root = priorFixture(); val pending = child("followup-kill", root.toString())
        check(pending.inputStream.bufferedReader().readLine() == "READY")
        pending.destroyForcibly(); check(finished(pending) != 0)
        check(finished(child("followup-reopen", root.toString())) == 0); unchanged(root)
    }
    test("authorized success persistence faults remain stopped on reopen") {
        for (stage in listOf("before_rename", "after_rename", "ledger_directory_force")) {
            val root = priorFixture(); val b = Budget.openAuthorizedFollowup(root); val p = reserve(b, "new-fault")
            b.handoff(p); b.faultInjector = { if (it == stage) throw java.io.IOException("redacted") }
            denied { b.success(p, Usage(10, 1, 28, "CNY")) }
            check(finished(child("followup-reopen", root.toString())) == 0)
            unchanged(root)
        }
    }
    test("authorized marker child loss corruption and orphan refuse recreation") {
        for (mode in listOf("marker-missing", "marker-corrupt", "ledger-missing", "ledger-corrupt", "lock-missing", "child-missing", "permissions", "symlink")) {
            val root = priorFixture(); val b = Budget.openAuthorizedFollowup(root)
            val childDir = root.parent.resolve(FOLLOWUP_DIR)
            when (mode) {
                "marker-missing" -> Files.delete(root.resolve(FOLLOWUP_ONCE))
                "marker-corrupt" -> Files.write(root.resolve(FOLLOWUP_ONCE), byteArrayOf(1))
                "ledger-missing" -> Files.delete(childDir.resolve(LEDGER))
                "ledger-corrupt" -> Files.write(childDir.resolve(LEDGER), byteArrayOf(1))
                "lock-missing" -> Files.delete(childDir.resolve("ordinary-chat-canary-20261019.lock"))
                "permissions" -> Files.setPosixFilePermissions(childDir, java.nio.file.attribute.PosixFilePermissions.fromString("rwxr-x---"))
                "symlink" -> { val moved = root.parent.resolve("relocated"); Files.move(childDir, moved); Files.createSymbolicLink(childDir, moved) }
                else -> { Files.delete(childDir.resolve(LEDGER)); Files.delete(childDir.resolve("ordinary-chat-canary-20261019.lock")); Files.delete(childDir) }
            }
            denied { b.snapshot() }; denied { Budget.openAuthorizedFollowup(root) }; unchanged(root)
        }
        val orphan = priorFixture(); Files.createDirectory(orphan.parent.resolve(FOLLOWUP_DIR))
        denied { Budget.openAuthorizedFollowup(orphan) }; check(!Files.exists(orphan.resolve(FOLLOWUP_ONCE)))
    }
    test("authorized every operation rejects changed missing or mutating original") {
        for (mode in listOf("changed", "missing", "mutation")) {
            val root = priorFixture(); val b = Budget.openAuthorizedFollowup(root); val p = reserve(b, "prior-guard")
            when (mode) {
                "changed" -> Files.write(root.resolve(LEDGER), byteArrayOf(1, 2, 3))
                "missing" -> Files.delete(root.resolve(LEDGER))
                else -> Files.createFile(root.resolve("ordinary-chat-canary-20261019.in-progress"))
            }
            val childBefore = Files.readAllBytes(root.parent.resolve(FOLLOWUP_DIR).resolve(LEDGER))
            denied { b.snapshot() }; denied { b.record(p.request) }; denied { b.handoff(p) }
            denied { b.success(p, Usage(10, 1, 28, "CNY")) }; denied { b.stop(p) }; denied { reserve(b, "blocked") }
            denied { Budget.openAuthorizedFollowup(root) }
            check(childBefore.contentEquals(Files.readAllBytes(root.parent.resolve(FOLLOWUP_DIR).resolve(LEDGER))))
        }
        val unapproved = Files.createTempDirectory("offline-unapproved-"); Budget.provisionNewBatch(unapproved)
        denied { Budget.openAuthorizedFollowup(unapproved) }; check(!Files.exists(unapproved.resolve(FOLLOWUP_ONCE)))
    }
    test("authorized concurrent processes serialize original then sibling lock") {
        val root = priorFixture(); Budget.openAuthorizedFollowup(root)
        val contenders = listOf(child("followup-contend", root.toString(), "new-left"), child("followup-contend", root.toString(), "new-right"))
        val readers = contenders.map { it.inputStream.bufferedReader() }
        check(readers.all { it.readLine() == "READY" }); Files.createFile(root.resolve("start"))
        val outcomes = readers.map { it.readLine() }
        check(contenders.all { finished(it) == 0 })
        check(outcomes.count { it == "RESERVED" } == 1 && outcomes.count { it == "REFUSED" } == 1)
        check(Budget.openAuthorizedFollowup(root).snapshot().stopped); unchanged(root)
    }
    println("$count offline canary budget groups passed; zero network requests")
}
