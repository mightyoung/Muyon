package com.mightyoung.muyon.product.chat

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/** Offline protocol seam only; creates no socket and loads no real credential. */
fun main(args: Array<String>) {
    if ("--legacy-send-check" in args) { legacySendCheck(); return }
    var passed = 0
    fun run(name: String, action: () -> Unit) { action(); passed++; println("PASS $name") }
    fun call(response: String, purpose: String = "chat", allowed: () -> Boolean = { true }, authorize: ((() -> Unit) -> Boolean) = { write -> write(); true }): Pair<ByteArray, String> {
        val output = ByteArrayOutputStream()
        val body = ProductHttpsTransport.exchangeConnected(ByteArrayInputStream(response.toByteArray()), output,
            "{}".toByteArray(), "synthetic-not-a-real-credential".toCharArray(), allowed, authorize, purpose = purpose)
        return body to output.toString("US-ASCII")
    }
    fun refused(response: String, purpose: String = "chat") {
        try { call(response, purpose); error("must reject") } catch (_: ProductHttpsFailure) { }
    }
    val ok = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}"
    run("content-length-one-post") { val (body, sent) = call(ok); check(String(body) == "{}"); check(sent.startsWith("POST /chat/completions HTTP/1.1\r\nHost: api.deepseek.com\r\n")); check(Regex("POST ").findAll(sent).count() == 1) }
    run("search-fixed-endpoint-path") { check(call(ok, "search").second.startsWith("POST /v1/tools/search HTTP/1.1\r\n")) }
    run("chunked-repeated-unrelated-headers") { check(String(call("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nSet-Cookie: one\r\nSet-Cookie: two\r\n\r\n2\r\n{}\r\n0\r\n\r\n").first) == "{}") }
    run("duplicate-length-rejected") { refused("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\n{}") }
    run("ambiguous-framing-rejected") { refused("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nTransfer-Encoding: chunked\r\n\r\n{}") }
    run("non-success-status-rejected") { refused("HTTP/1.1 403 Denied\r\nContent-Length: 0\r\n\r\n") }
    run("truncated-body-rejected") { refused("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\n{}") }
    run("unsupported-purpose-rejected") { refused(ok, "arbitrary-url") }
    run("cancelled-before-write-no-bytes") {
        val output = ByteArrayOutputStream()
        try { ProductHttpsTransport.exchangeConnected(ByteArrayInputStream(ok.toByteArray()), output, "{}".toByteArray(), "synthetic-credential".toCharArray(), { false }, { write -> write(); true }); error("must reject") } catch (_: ProductHttpsFailure) { }
        check(output.size() == 0)
    }
    run("repeated-authorize-cannot-write-twice") {
        val output = ByteArrayOutputStream()
        try { ProductHttpsTransport.exchangeConnected(ByteArrayInputStream(ok.toByteArray()), output, "{}".toByteArray(), "synthetic-credential".toCharArray(), { true }, { write -> write(); write(); true }); error("must reject") } catch (_: ProductHttpsFailure) { }
        check(Regex("POST ").findAll(output.toString("US-ASCII")).count() == 1)
    }
    run("deadline-watchdog-closes") {
        val closed = AtomicBoolean(false)
        val watchdog = ProductHttpsTransport.startDeadlineWatchdog(AtomicBoolean(false), AtomicLong(Long.MAX_VALUE), 1L, { true }, { closed.set(true) }, { 2L })
        watchdog.join(1000); check(closed.get() && !watchdog.isAlive)
    }
    for (revocation in listOf("cancel", "configuration", "release", "close", "scope")) {
        run("$revocation-before-write-zero-bytes") { gateRevocationFirst(revocation) }
        run("write-before-$revocation-serialized") { gateWriteFirst(revocation) }
    }
    run("released-session-cannot-register-late") {
        val gate=ProductSendGate();gate.activateConfiguration(gate.invalidateConfiguration());gate.releaseSession("session")
        try {gate.register("request","session");error("must reject late session")}catch(_:IllegalStateException){}
    }
    run("scope-away-and-back-never-restores-old-generation") {
        val registry=ProductScopeRegistry();val a=registry.update("session","project-a")
        check(registry.matches("session","project-a",a.generation))
        registry.update("session","project-b");check(!registry.matches("session","project-a",a.generation))
        val fresh=registry.update("session","project-a");check(fresh.generation>a.generation)
        check(!registry.matches("session","project-a",a.generation));check(registry.matches("session","project-a",fresh.generation))
    }
    println("RESULT $passed passed; 0 failed; no network")
}

private fun latch() = java.util.concurrent.CountDownLatch(1)
private fun java.util.concurrent.CountDownLatch.waitBounded() { check(await(3, java.util.concurrent.TimeUnit.SECONDS)) }
private fun revoke(gate: ProductSendGate, kind: String) { when(kind) {
    "cancel"->gate.cancel("request");"configuration"->gate.invalidateConfiguration();"release"->gate.releaseSession("session");"close"->gate.close();"scope"->gate.invalidateSessionScope("session");else->error("invalid kind")
} }
private fun gateRevocationFirst(kind: String) {
    val gate=ProductSendGate();gate.activateConfiguration(gate.invalidateConfiguration());val ticket=gate.register("request","session")
    val checked=latch();val resume=latch();val done=latch();val writes=java.util.concurrent.atomic.AtomicInteger(0)
    val worker=Thread { try { check(gate.advisoryAllowed(ticket));checked.countDown();resume.waitBounded();gate.authorizeWrite(ticket){writes.incrementAndGet()} } finally {done.countDown()} }
    worker.start();checked.waitBounded();revoke(gate,kind);resume.countDown();done.waitBounded();worker.join()
    check(writes.get()==0){"revocation completed before authorization, zero later writes required"}
}
private fun gateWriteFirst(kind: String) {
    val gate=ProductSendGate();gate.activateConfiguration(gate.invalidateConfiguration());val ticket=gate.register("request","session")
    val writing=latch();val finishWrite=latch();val revokeStarted=latch();val revoked=latch();val writes=java.util.concurrent.atomic.AtomicInteger(0)
    val worker=Thread {gate.authorizeWrite(ticket){writing.countDown();finishWrite.waitBounded();writes.incrementAndGet()}}
    worker.start();writing.waitBounded()
    // Advisory/watchdog reads must finish even while the write gate is held.
    val advisoryDone=latch();Thread {gate.advisoryAllowed(ticket);advisoryDone.countDown()}.start();advisoryDone.waitBounded()
    val revoker=Thread {revokeStarted.countDown();revoke(gate,kind);revoked.countDown()};revoker.start();revokeStarted.waitBounded()
    val deadline=System.nanoTime()+java.util.concurrent.TimeUnit.SECONDS.toNanos(3)
    while(revoker.state!=Thread.State.BLOCKED && System.nanoTime()<deadline) Thread.yield()
    check(revoker.state==Thread.State.BLOCKED && revoked.count==1L){"revoke must wait for already-linearized write"}
    finishWrite.countDown();worker.join(3000);revoked.waitBounded();revoker.join()
    check(writes.get()==1 && !gate.advisoryAllowed(ticket));check(!gate.authorizeWrite(ticket){error("no second write")})
}
/** Exact old shape: final permission check, pause, revoke completes, then write.
 * Expected to fail the same zero-after-revoke assertion; no socket is created. */
private fun legacySendCheck() {
    val allowed=AtomicBoolean(true);val checked=latch();val resume=latch();val writes=java.util.concurrent.atomic.AtomicInteger(0)
    val worker=Thread {if(allowed.get()){checked.countDown();resume.waitBounded();writes.incrementAndGet()}}
    worker.start();checked.waitBounded();allowed.set(false);resume.countDown();worker.join(3000)
    check(writes.get()==0){"RED: legacy check-then-write emitted after completed cancellation"}
}
