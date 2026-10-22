package com.mightyoung.muyon.androidlab.agentipc

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

fun main() {
    var checks = 0
    val credential = "synthetic-offline-key".toCharArray()
    fun run(response: String, allowed: () -> Boolean = { true }, authorize: ((() -> Unit) -> Boolean) = { it(); true }): Pair<String, String> {
        val output = ByteArrayOutputStream()
        val body = OrdinaryChatHttpsTransport.exchangeConnected(ByteArrayInputStream(response.toByteArray()), output,
            "{}".toByteArray(), credential, allowed, authorize)
        return body.toString(Charsets.UTF_8) to output.toString("US-ASCII")
    }
    fun reject(block: () -> Unit) {
        try { block(); error("expected rejection") } catch (failure: OrdinaryChatHttpsFailure) {
            check(failure.message == "ordinary_chat_https_failed" && failure.cause == null)
        }
        checks++
    }
    val (body, request) = run("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}")
    check(body == "{}" && request.startsWith("POST /chat/completions HTTP/1.1\r\nHost: api.deepseek.com\r\n"))
    check(request.split("POST ").size == 2 && request.endsWith("\r\n\r\n{}")); checks++
    check(run("HTTP/1.1 200 Fine\r\nTransfer-Encoding: chunked\r\n\r\n2;name=value\r\n{}\r\n0\r\nX-Trace: safe\r\n\r\n").first == "{}"); checks++
    check(run("HTTP/1.1 200 OK\r\n\r\n{}").first == "{}"); checks++
    reject { run("HTTP/1.1 302 Redirect\r\nLocation: https://other.invalid\r\n\r\n") }
    reject { run("HTTP/1.1 401 Unauthorized\r\n\r\n") }
    reject { run("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nTransfer-Encoding: chunked\r\n\r\n") }
    reject { run("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\n{}") }
    reject { run("HTTP/1.1 200 OK\r\nContent-Length: 65537\r\n\r\n") }
    reject { run("HTTP/1.1 200 OK\r\n\r\n" + "a".repeat(65_537)) }
    reject { run("HTTP/1.1 200 OK\r\nX-Huge: " + "a".repeat(16_384) + "\r\n\r\n") }
    reject { run("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n10001\r\n") }
    reject { run("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\n{}XX") }
    reject { run("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\n{}") }
    reject { run("", allowed = { false }) }
    var writes = 0
    reject {
        OrdinaryChatHttpsTransport.exchangeConnected(ByteArrayInputStream(byteArrayOf()), object : OutputStream() {
            override fun write(value: Int) { writes++ }
            override fun write(bytes: ByteArray) { writes++ }
        }, byteArrayOf(1), credential, { true }, { false })
    }
    check(writes == 0)
    reject {
        OrdinaryChatHttpsTransport.exchangeConnected(ByteArrayInputStream(byteArrayOf()), object : OutputStream() {
            override fun write(value: Int) { error("unused") }
            override fun write(bytes: ByteArray) { writes++; throw java.io.IOException("sensitive detail") }
        }, byteArrayOf(1), credential, { true }, { it(); true })
    }
    check(writes == 1) // A failed write must never be repeated.
    var writable = true
    reject { run("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}", { writable }, { it(); writable = false; true }) }
    var reads = 0
    reject {
        OrdinaryChatHttpsTransport.exchangeConnected(object : InputStream() {
            val source = ByteArrayInputStream("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}".toByteArray())
            override fun read(): Int { reads++; return source.read() }
        }, ByteArrayOutputStream(), byteArrayOf(1), credential, { reads < 12 }, { it(); true })
    }
    var retained: ByteArray? = null
    OrdinaryChatHttpsTransport.exchangeConnected(ByteArrayInputStream("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n".toByteArray()), object : OutputStream() {
        override fun write(value: Int) { error("unused") }
        override fun write(bytes: ByteArray) { retained = bytes }
    }, byteArrayOf(1), credential, { true }, { it(); true })
    check(retained!!.all { it == 0.toByte() }); checks++
    reject { run("", authorize = { it(); it(); true }) }
    reject { OrdinaryChatHttpsTransport.exchangeConnected(ByteArrayInputStream(byteArrayOf()), ByteArrayOutputStream(), ByteArray(8193), credential, { true }, { it(); true }) }
    for (reason in listOf("total", "write", "cancel")) {
        val closed = CountDownLatch(1)
        val done = AtomicBoolean(false)
        val thread = OrdinaryChatHttpsTransport.startDeadlineWatchdog(done,
            AtomicLong(if (reason == "write") 5 else 100), if (reason == "total") 5 else 100,
            { reason != "cancel" }, { closed.countDown() }, { 10 })
        check(closed.await(1, TimeUnit.SECONDS))
        done.set(true)
        thread.join(1000)
        check(!thread.isAlive)
        checks++
    }
    val completedClose = AtomicBoolean(false)
    OrdinaryChatHttpsTransport.startDeadlineWatchdog(AtomicBoolean(true), AtomicLong(0), 0,
        { false }, { completedClose.set(true) }, { 10 }).join(1000)
    check(!completedClose.get()); checks++
    val poisoned = "synthetic-offline-key".toCharArray()
    reject { OrdinaryChatHttpsTransport().exchange(byteArrayOf(1), poisoned, { false }, { it(); true }) }
    check(poisoned.all { it == '\u0000' }); checks++
    check(checks == 27) // Preserve every original protocol/bounds/watchdog check above.
    fun failureAt(stage: OrdinaryChatFailureStage, status: Int? = null, block: () -> Unit): OrdinaryChatHttpsFailure {
        try { block(); error("expected diagnostic failure") } catch (failure: OrdinaryChatHttpsFailure) {
            check(failure.message == "ordinary_chat_https_failed" && failure.cause == null)
            check(failure.stage == stage && failure.httpStatus == status)
            check(failure.suppressed.isEmpty())
            checks++
            return failure
        }
    }
    for (stage in OrdinaryChatFailureStage.entries) {
        val failure = OrdinaryChatHttpsFailure(stage)
        check(failure.stage == stage && failure.httpStatus == null && failure.cause == null)
        check(failure.message == "ordinary_chat_https_failed")
        checks++
    }
    check(OrdinaryChatHttpsFailure().stage == OrdinaryChatFailureStage.PREPARE); checks++
    failureAt(OrdinaryChatFailureStage.PREPARE) { run("", allowed = { false }) }
    failureAt(OrdinaryChatFailureStage.AUTHORIZE_WRITE) { run("", authorize = { false }) }
    failureAt(OrdinaryChatFailureStage.HTTP_STATUS) { run("") }
    failureAt(OrdinaryChatFailureStage.HTTP_HEADERS, 200) { run("HTTP/1.1 200 OK\r\nBroken header\r\n") }
    failureAt(OrdinaryChatFailureStage.HTTP_HEADERS, 200) { run("HTTP/1.1 200 OK\r\nContent-Length: 65537\r\n\r\n") }
    failureAt(OrdinaryChatFailureStage.HTTP_BODY, 200) { run("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\n{}") }
    for (line in listOf("HTTP/1.0 401 Forbidden", "HTTP/1.1 099 Bad", "HTTP/1.1 600 Bad",
        "HTTP/1.1 20 OK", "HTTP/1.1 0200 OK", "HTTP/1.1  401 Bad", "HTTP/1.1 401", "HTTP/1.1\t401 Bad")) {
        failureAt(OrdinaryChatFailureStage.HTTP_STATUS) { run("$line\r\n") }
    }
    for (status in listOf(100, 302, 401, 429, 500, 599)) {
        val statusLine = "HTTP/1.1 $status sensitive-reason\r\n".toByteArray()
        var offset = 0
        failureAt(OrdinaryChatFailureStage.HTTP_STATUS, status) {
            OrdinaryChatHttpsTransport.exchangeConnected(object : InputStream() {
                override fun read(): Int {
                    check(offset < statusLine.size) { "must not read headers or body" }
                    return statusLine[offset++].toInt()
                }
            }, ByteArrayOutputStream(), byteArrayOf(1), credential, { true }, { it(); true })
        }
        check(offset == statusLine.size)
    }
    val preserved = OrdinaryChatHttpsFailure(OrdinaryChatFailureStage.OWNER_AUTHORITY)
    check(failureAt(OrdinaryChatFailureStage.OWNER_AUTHORITY) {
        run("", authorize = { throw preserved })
    } === preserved); checks++
    var failedWrites = 0
    var failedRequest: ByteArray? = null
    val sensitiveFailure = failureAt(OrdinaryChatFailureStage.WRITE) {
        OrdinaryChatHttpsTransport.exchangeConnected(ByteArrayInputStream(byteArrayOf()), object : OutputStream() {
            override fun write(value: Int) { error("unused") }
            override fun write(bytes: ByteArray) {
                failedWrites++
                failedRequest = bytes
                throw java.io.IOException("synthetic-offline-key secret-payload secret-response")
            }
        }, "secret-payload".toByteArray(), credential, { true }, { it(); true })
    }
    check(failedWrites == 1 && failedRequest!!.all { it == 0.toByte() }); checks++
    // The diagnostic object contains only fixed enum/numeric fields, never a request, key, or original exception.
    check(sensitiveFailure.javaClass.declaredFields.filterNot { java.lang.reflect.Modifier.isStatic(it.modifiers) }
        .all { it.type == OrdinaryChatFailureStage::class.java || it.type == java.lang.Integer::class.java })
    check(!sensitiveFailure.toString().contains("secret") && sensitiveFailure.cause == null); checks++
    val outerPoisoned = "synthetic-offline-key".toCharArray()
    failureAt(OrdinaryChatFailureStage.PREPARE) {
        OrdinaryChatHttpsTransport().exchange(byteArrayOf(1), outerPoisoned, { false }, { it(); true })
    }
    check(outerPoisoned.all { it == '\u0000' }); checks++
    check(checks == 68) // Keep all original protocol, bounds, redaction and stage assertions.
    fun headers(value: String) = "HTTP/1.1 200 OK\r\n$value\r\n{}"
    // Independent non-framing fields are discarded, including Set-Cookie (never combined).
    check(run(headers("Set-Cookie: one=a\r\nSet-Cookie: two=b\r\nVary: Accept\r\nVary: Origin\r\nContent-Length: 2\r\n")).first == "{}"); checks++
    check(run(headers("sEt-CoOkIe: one=a\r\nSET-COOKIE: two=b\r\nvArY: Accept\r\nVARY: Origin\r\nContent-Length: 2\r\n")).first == "{}"); checks++
    check(run(headers("X_Underscore: yes\r\n!#$%&'*+-.^_`|~: tokens\r\nContent-Length: 2\r\n")).first == "{}"); checks++
    check(run(headers("Content-Length:\t 2 \t\r\nContent-Encoding: \tIdEnTiTy\t \r\n")).first == "{}"); checks++
    check(run("HTTP/1.1 200 OK\r\nTransfer-Encoding:\tchunked \t\r\n\r\n2\r\n{}\r\n0\r\nX_Underscore: yes\r\n!#$%&'*+-.^_`|~: tokens\r\nVary: A\r\nVary: B\r\n\r\n").first == "{}"); checks++
    for (name in listOf("Bad Name", "Bad\tName", "Bad(Name)", "Bad/Name", "Bad@Name", "Bad[Name]", "", "Content-Length ")) {
        failureAt(OrdinaryChatFailureStage.HTTP_HEADERS, 200) { run(headers("$name: 2\r\nContent-Length: 2\r\n")) }
    }
    for (fields in listOf(
        "Content-Length: 2\r\ncontent-length: 2\r\n",
        "Transfer-Encoding: chunked\r\nTRANSFER-ENCODING: chunked\r\n",
        "Content-Length: 2\r\nTransfer-Encoding: chunked\r\n",
        "Transfer-Encoding: chunked\r\nContent-Length: 2\r\n",
        "Content-Length: 2, 2\r\n",
        "Content-Length: 2\r\nContent-Encoding: gzip\r\n",
        "Content-Length: 2\r\nContent-Encoding: br\r\n",
        "Content-Length: 2\r\nContent-Encoding: identity, gzip\r\n",
        "Content-Length: 2\r\nContent-Encoding: \r\n",
        "Content-Length: 2\r\nContent-Encoding: identity\r\ncontent-encoding: identity\r\n",
        "Content-Length: 2\r\nX-Value: forbidden\u000bwhitespace\r\n",
        "Content-Length: 2\r\nX-Value: non-ASCII-\u0080\r\n",
        "Content-Length: 2\r\nX-Huge: " + "a".repeat(16_384) + "\r\n",
    )) {
        failureAt(OrdinaryChatFailureStage.HTTP_HEADERS, 200) { run(headers(fields)) }
    }
    for (trailer in listOf("Bad Name: x", "Bad/Name: x", "CONTENT-LENGTH: 2", "Transfer-Encoding: chunked", "Host: elsewhere", "Authorization: secret",
        "Content-Encoding: identity", "cOnTeNt-EnCoDiNg: gzip")) {
        failureAt(OrdinaryChatFailureStage.HTTP_BODY, 200) {
            run("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\n{}\r\n0\r\n$trailer\r\n\r\n")
        }
    }
    credential.fill('\u0000')
    println("HTTPS offline protocol checks passed: $checks; no network or real credential used")
}
