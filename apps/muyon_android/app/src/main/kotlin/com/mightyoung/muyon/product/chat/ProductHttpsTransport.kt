package com.mightyoung.muyon.product.chat

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import javax.net.ssl.SNIHostName
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

/** One attempt, one socket, one POST. All failures are deliberately opaque. */
internal class ProductHttpsTransport {
    fun exchange(
        payload: ByteArray,
        credential: CharArray,
        purpose: String = "chat",
        allowed: () -> Boolean,
        authorizeAndWrite: ((() -> Unit) -> Boolean),
    ): ByteArray {
        var socket: Socket? = null
        val finished = AtomicBoolean(false)
        val writeDeadline = AtomicLong(Long.MAX_VALUE)
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(45)
        var stage = ProductFailureStage.PREPARE
        try {
            require(payload.size in 1..8192)
            validateCredential(credential)
            check(allowed())
            val connection = Socket()
            socket = connection
            startDeadlineWatchdog(finished, writeDeadline, deadline, allowed, { connection.close() })
            val connectDeadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)
            // DNS itself can block; its daemon task has no credentials and cannot send a request.
            stage = ProductFailureStage.DNS
            val lookup = FutureTask { InetAddress.getByName(HOST) }
            Thread(lookup, "ordinary-chat-dns").apply { isDaemon = true; start() }
            val address = try {
                lookup.get(remainingMillis(connectDeadline).toLong(), TimeUnit.MILLISECONDS)
            } finally { lookup.cancel(true) }
            stage = ProductFailureStage.TCP_CONNECT
            connection.connect(InetSocketAddress(address, 443), remainingMillis(connectDeadline))
            // Preserve the DNS peer host for certificate verification when connecting a resolved IP.
            stage = ProductFailureStage.TLS_HANDSHAKE
            val active = (SSLSocketFactory.getDefault() as SSLSocketFactory)
                .createSocket(connection, HOST, 443, true) as SSLSocket
            socket = active
            active.soTimeout = minOf(20_000, remainingMillis(deadline))
            active.sslParameters = active.sslParameters.apply {
                endpointIdentificationAlgorithm = "HTTPS"
                serverNames = listOf(SNIHostName(HOST))
            }
            active.startHandshake()
            check(allowed() && System.nanoTime() < deadline)
            return exchangeConnected(active.inputStream, active.outputStream, payload, credential,
                { allowed() && System.nanoTime() < deadline }, authorizeAndWrite,
                { writing -> writeDeadline.set(if (writing) System.nanoTime() + TimeUnit.SECONDS.toNanos(2) else Long.MAX_VALUE) }, purpose)
        } catch (failure: ProductHttpsFailure) {
            throw failure
        } catch (_: Exception) {
            throw ProductHttpsFailure(stage)
        } finally {
            finished.set(true)
            credential.fill('\u0000')
            try { socket?.close() } catch (_: Exception) { }
        }
    }

    private fun remainingMillis(deadline: Long): Int {
        val millis = TimeUnit.NANOSECONDS.toMillis(deadline - System.nanoTime())
        check(millis > 0)
        return millis.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    }

    companion object {
        private const val HOST = "api.deepseek.com"

        internal fun startDeadlineWatchdog(
            finished: AtomicBoolean,
            writeDeadline: AtomicLong,
            deadline: Long,
            allowed: () -> Boolean,
            close: () -> Unit,
            now: () -> Long = System::nanoTime,
        ): Thread = Thread({
            try {
                while (!finished.get()) {
                    if (!allowed() || now() >= deadline || now() >= writeDeadline.get()) {
                        close()
                        break
                    }
                    Thread.sleep(10)
                }
            } catch (_: Exception) { try { close() } catch (_: Exception) { } }
        }, "ordinary-chat-deadline").apply { isDaemon = true; start() }

        private fun validateCredential(credential: CharArray) {
            require(credential.size in 1..512 && credential.all { it.code in 33..126 })
        }

        /** Protocol seam for offline byte-stream tests; production always establishes its own TLS. */
        internal fun exchangeConnected(
            input: InputStream,
            output: OutputStream,
            payload: ByteArray,
            credential: CharArray,
            allowed: () -> Boolean,
            authorizeAndWrite: ((() -> Unit) -> Boolean),
            writing: (Boolean) -> Unit = {},
            purpose: String = "chat",
        ): ByteArray {
            var request: ByteArray? = null
            var result: ByteArray? = null
            var stage = ProductFailureStage.PREPARE
            var httpStatus: Int? = null
            try {
                require(payload.size in 1..8192)
                validateCredential(credential)
                check(allowed())
                val path = when (purpose) { "chat" -> "/chat/completions"; "search" -> "/v1/tools/search"; else -> error("product_purpose_invalid") }
                val prefix = ("POST $path HTTP/1.1\r\nHost: $HOST\r\n" +
                    "Content-Type: application/json\r\nConnection: close\r\nAuthorization: Bearer ").toByteArray(Charsets.US_ASCII)
                val suffix = "\r\nContent-Length: ${payload.size}\r\n\r\n".toByteArray(Charsets.US_ASCII)
                val bytes = ByteArray(prefix.size + credential.size + suffix.size + payload.size)
                request = bytes
                prefix.copyInto(bytes)
                credential.forEachIndexed { index, char -> bytes[prefix.size + index] = char.code.toByte() }
                suffix.copyInto(bytes, prefix.size + credential.size)
                payload.copyInto(bytes, prefix.size + credential.size + suffix.size)
                val sent = AtomicBoolean(false)
                stage = ProductFailureStage.AUTHORIZE_WRITE
                check(authorizeAndWrite {
                    check(sent.compareAndSet(false, true) && allowed())
                    stage = ProductFailureStage.WRITE
                    writing(true)
                    val started = System.nanoTime()
                    try {
                        output.write(bytes)
                        output.flush()
                        check(System.nanoTime() - started < TimeUnit.SECONDS.toNanos(2))
                    } finally { writing(false) }
                })
                check(sent.get() && allowed())
                result = readResponse(input, allowed, { stage = it }, { httpStatus = it })
                // Fully framed responses must settle the original attempt even
                // when cancellation races with the final read.
                return result
            } catch (failure: ProductHttpsFailure) {
                result?.fill(0)
                throw failure
            } catch (_: Exception) {
                result?.fill(0)
                throw ProductHttpsFailure(stage, httpStatus)
            } finally { request?.fill(0) }
        }

        private fun readResponse(
            input: InputStream,
            allowed: () -> Boolean,
            stage: (ProductFailureStage) -> Unit,
            statusParsed: (Int) -> Unit,
        ): ByteArray {
            stage(ProductFailureStage.HTTP_STATUS)
            var headerBytes = 0
            fun octet(): Int { check(allowed()); return input.read() }
            fun line(limit: Int): String {
                val bytes = ByteArrayOutputStream()
                while (true) {
                    val value = octet()
                    check(value >= 0)
                    if (value == 13) { check(octet() == 10); return bytes.toString("US-ASCII") }
                    // Deliberately accept only ASCII field values plus HTAB; obs-text is unsupported.
                    check(value == 9 || value in 32..126)
                    check(bytes.size() < limit)
                    bytes.write(value)
                }
            }
            fun headerLine(): String {
                val value = line(16_384 - headerBytes)
                headerBytes += value.length + 2
                check(headerBytes <= 16_384)
                return value
            }
            fun fieldName(value: String, colon: Int): String {
                check(colon > 0)
                val name = value.substring(0, colon).lowercase(java.util.Locale.ROOT)
                check(name.all { it in 'a'..'z' || it in '0'..'9' || it in "!#$%&'*+-.^_`|~" })
                return name
            }
            val status = headerLine()
            // Keep only the numeric code; never expose the untrusted reason phrase.
            val match = Regex("HTTP/1\\.1 ([0-9]{3}) [\\t\\x20-\\x7e]*").matchEntire(status)
            check(match != null)
            val code = match.groupValues[1].toInt()
            check(code in 100..599)
            statusParsed(code)
            check(code == 200)
            stage(ProductFailureStage.HTTP_HEADERS)
            val headers = mutableMapOf<String, String>()
            while (true) {
                val value = headerLine()
                if (value.isEmpty()) break
                val colon = value.indexOf(':')
                val name = fieldName(value, colon)
                if (name in setOf("content-length", "transfer-encoding", "content-encoding")) {
                    check(!headers.containsKey(name))
                    headers[name] = value.substring(colon + 1).trim(' ', '\t')
                }
                // Unused fields are discarded independently, never combined (including Set-Cookie).
            }
            val length = headers["content-length"]
            val encoding = headers["transfer-encoding"]
            check(length == null || encoding == null)
            check(encoding == null || encoding.equals("chunked", ignoreCase = true))
            val contentEncoding = headers["content-encoding"]
            check(contentEncoding == null || contentEncoding.equals("identity", ignoreCase = true))
            val contentLength = length?.let {
                check(it.isNotEmpty() && it.all { char -> char in '0'..'9' })
                it.toLong().also { count -> check(count <= 65_536) }.toInt()
            }
            stage(ProductFailureStage.HTTP_BODY)
            val body = ByteArrayOutputStream()
            fun copy(count: Int) {
                check(count >= 0 && body.size() + count <= 65_536)
                repeat(count) { val value = octet(); check(value >= 0); body.write(value) }
            }
            if (encoding != null) {
                var framingBytes = 0
                while (true) {
                    val chunkLine = line(128)
                    framingBytes += chunkLine.length + 2
                    check(framingBytes <= 16_384)
                    val size = chunkLine.substringBefore(';')
                    check(size.isNotEmpty() && size.all { it in "0123456789abcdefABCDEF" })
                    if (';' in chunkLine) {
                        check(chunkLine.substringAfter(';').matches(Regex("[A-Za-z0-9!#$%&'*+.^_`|~-]+(?:=(?:[A-Za-z0-9!#$%&'*+.^_`|~-]+|\"[^\"\\\\]*\"))?(?:;[A-Za-z0-9!#$%&'*+.^_`|~-]+(?:=(?:[A-Za-z0-9!#$%&'*+.^_`|~-]+|\"[^\"\\\\]*\"))?)*")))
                    }
                    val count = size.toLong(16)
                    check(count <= 65_536)
                    if (count == 0L) {
                        while (true) {
                            val trailer = line(16_384 - framingBytes)
                            framingBytes += trailer.length + 2
                            check(framingBytes <= 16_384)
                            if (trailer.isEmpty()) break
                            val colon = trailer.indexOf(':')
                            val name = fieldName(trailer, colon)
                            check(name !in setOf("content-length", "transfer-encoding", "content-encoding", "host", "authorization"))
                        }
                        break
                    }
                    copy(count.toInt())
                    check(octet() == 13 && octet() == 10)
                }
            } else if (contentLength != null) {
                copy(contentLength)
            } else {
                while (true) {
                    val value = octet()
                    if (value < 0) break
                    check(body.size() < 65_536)
                    body.write(value)
                }
            }
            return body.toByteArray()
        }
    }
}

/** Local failure location only: a stage does not establish whether the provider received a request. */
internal enum class ProductFailureStage {
    PREPARE, DNS, TCP_CONNECT, TLS_HANDSHAKE, AUTHORIZE_WRITE, WRITE,
    HTTP_STATUS, HTTP_HEADERS, HTTP_BODY, RESPONSE_VALIDATION, CANDIDATE_PERSIST,
    OWNER_HANDOFF, OWNER_AUTHORITY,
}

internal class ProductHttpsFailure(
    val stage: ProductFailureStage = ProductFailureStage.PREPARE,
    val httpStatus: Int? = null,
) : Exception("ordinary_chat_https_failed")
