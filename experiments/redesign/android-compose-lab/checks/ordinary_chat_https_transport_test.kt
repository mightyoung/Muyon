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
    credential.fill('\u0000')
    println("HTTPS offline protocol checks passed: $checks; no network or real credential used")
}
