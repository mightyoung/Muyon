package com.mightyoung.muyon.androidlab

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.RejectedExecutionException

private const val BUILD = "1234567890abcdef1234567890abcdef12345678"
private fun info() = UiBridgeInfo(1u, BUILD, UiDiagnosticCapability.BUNDLED_DECLARATION_VALIDATION, false, false, false, false, false)
private fun report(r: UiDiagnosticRequest) = UiDiagnosticReport(1u, r.requestId, BUILD, r.variant, "lab", 1uL, 2u, 1u, 1u, 1u)
private open class Backend : DiagnosticNativePort {
    var calls = 0
    override fun bridgeInfo() = info().also { calls++ }
    override fun validateBundledContract(request: UiDiagnosticRequest) = report(request).also { calls++ }
}
private class ManualWorker : Executor {
    private val queue = ArrayDeque<Runnable>()
    override fun execute(command: Runnable) { queue.addLast(command) }
    fun run() { check(queue.isNotEmpty()) { "missing admitted work" }; queue.removeFirst().run() }
    val pending get() = queue.size
}
private class Observer {
    val updates = LinkedBlockingQueue<DiagnosticSnapshot>()
    var last = DiagnosticSnapshot()
    fun receive(s: DiagnosticSnapshot) { last = s; updates.add(s) }
    fun awaitIdle() { while (true) { val s = updates.poll(5, TimeUnit.SECONDS) ?: error("missing completion"); if (!s.nativeBusy) return } }
}
private class Rig(val native: Backend = Backend()) {
    val worker = ManualWorker()
    val c = diagnosticCoordinator(native, worker) { it() }
    val o = Observer()
    val lease = c.attach(o::receive)
    fun handshake() { check(c.startHandshake(lease) is DiagnosticAdmission.Accepted) { "handshake not admitted" }; worker.run(); check(o.last.availability is DiagnosticAvailability.Ready) { "real handshake missing" } }
    fun validate(v: UiDiagnosticVariant = UiDiagnosticVariant.EQUIPMENT): DiagnosticCallToken =
        (c.startValidation(lease, v) as? DiagnosticAdmission.Accepted)?.token ?: error("validation not admitted")
}

fun runDiagnosticChecks() {
    val cases = linkedMapOf<String, () -> Unit>()
    cases["construction never calls native"] = { val r = Rig(); check(r.native.calls == 0); check(r.o.last == DiagnosticSnapshot()) }
    cases["validation requires actual handshake"] = { val r = Rig(); check(r.c.startValidation(r.lease, UiDiagnosticVariant.EQUIPMENT) == DiagnosticAdmission.NotReady); check(r.worker.pending == 0) }
    cases["handshake is worker only and busy before entry"] = { val r = Rig(); check(r.c.startHandshake(r.lease) is DiagnosticAdmission.Accepted); check(r.native.calls == 0); check(r.o.last.nativeBusy); check(r.c.startHandshake(r.lease) == DiagnosticAdmission.Busy); r.worker.run(); check(r.o.last.availability is DiagnosticAvailability.Ready) }
    cases["missing library has safe unavailable result"] = { val r = Rig(object : Backend() { override fun bridgeInfo(): UiBridgeInfo = throw DiagnosticNativeFailure(DiagnosticError.NATIVE_LOAD) }); check(r.c.startHandshake(r.lease) is DiagnosticAdmission.Accepted); r.worker.run(); check(r.o.last.availability == DiagnosticAvailability.Unavailable(DiagnosticError.NATIVE_LOAD)); check(!r.o.last.nativeBusy) }
    for ((name, changed) in listOf<Pair<String, (UiBridgeInfo) -> UiBridgeInfo>>("protocol" to { it.copy(protocol=2u) }, "build" to { it.copy(buildIdentity="bad") }, "model" to { it.copy(model=true) }, "execute" to { it.copy(execute=true) }, "read" to { it.copy(businessRead=true) }, "write" to { it.copy(write=true) }, "attachment" to { it.copy(attachments=true) })) {
        cases["handshake rejects $name mismatch"] = { val r = Rig(object : Backend() { override fun bridgeInfo() = changed(info()) }); check(r.c.startHandshake(r.lease) is DiagnosticAdmission.Accepted); r.worker.run(); check(r.o.last.availability == DiagnosticAvailability.Unavailable(DiagnosticError.PROTOCOL_MISMATCH)) }
    }
    cases["four variants carry internal bounded identifiers and unsigned counts"] = {
        val r = Rig(object : Backend() { override fun validateBundledContract(request: UiDiagnosticRequest): UiDiagnosticReport { check(request.protocol == 1u); check(Regex("[A-Za-z0-9_-]{1,64}").matches(request.requestId)); return report(request).copy(catalogGeneration=ULong.MAX_VALUE, dataCount=UInt.MAX_VALUE) } })
        r.handshake(); val ids = mutableSetOf<String>(); UiDiagnosticVariant.entries.forEach { v -> val token = r.validate(v); r.worker.run(); val done = r.o.last.presentation as DiagnosticPresentation.Complete; check(done.report.variant == v && done.report.requestId == token.requestId); check(ids.add(token.requestId)); check(done.report.catalogGeneration == ULong.MAX_VALUE && done.report.dataCount == UInt.MAX_VALUE) }
    }
    for ((name, changed) in listOf<Pair<String, (UiDiagnosticReport) -> UiDiagnosticReport>>("id" to { it.copy(requestId="other") }, "variant" to { it.copy(variant=UiDiagnosticVariant.RESEARCH) }, "protocol" to { it.copy(protocol=2u) }, "build" to { it.copy(buildIdentity="f".repeat(40)) })) {
        cases["report rejects $name mismatch"] = { val r = Rig(object : Backend() { override fun validateBundledContract(request: UiDiagnosticRequest) = changed(report(request)) }); r.handshake(); r.validate(); r.worker.run(); check((r.o.last.presentation as DiagnosticPresentation.Failed).code == DiagnosticError.REQUEST_MISMATCH); check(r.o.last.availability is DiagnosticAvailability.Ready) }
    }
    for (code in listOf(DiagnosticError.UNSUPPORTED_PROTOCOL, DiagnosticError.INVALID_REQUEST_ID, DiagnosticError.DECLARATION_REJECTED, DiagnosticError.INTERNAL_FAILURE)) {
        cases["native typed $code remains closed and slot releases"] = { val r = Rig(object : Backend() { override fun validateBundledContract(request: UiDiagnosticRequest): UiDiagnosticReport = throw DiagnosticNativeFailure(code) }); r.handshake(); r.validate(); r.worker.run(); check((r.o.last.presentation as DiagnosticPresentation.Failed).code == code); check(!r.o.last.nativeBusy); check(r.c.startHandshake(r.lease) is DiagnosticAdmission.Accepted) }
    }
    cases["unexpected native error never exposes raw reason"] = { val r = Rig(object : Backend() { override fun bridgeInfo(): UiBridgeInfo = error("secret-error-do-not-display") }); check(r.c.startHandshake(r.lease) is DiagnosticAdmission.Accepted); r.worker.run(); check(r.o.last.availability == DiagnosticAvailability.Unavailable(DiagnosticError.NATIVE_FAILURE)); check(!r.o.last.toString().contains("secret")) }
    cases["expired handshake cannot publish readiness"] = { val r = Rig(); val t = (r.c.startHandshake(r.lease) as DiagnosticAdmission.Accepted).token; r.c.expire(r.lease,t); check(r.o.last.nativeBusy); r.worker.run(); check(r.o.last.availability == DiagnosticAvailability.NotChecked); check(r.o.last.presentation is DiagnosticPresentation.LocallyTimedOut) }
    cases["detached lease cannot start work"] = { val r = Rig(); r.c.detach(r.lease); check(r.c.startHandshake(r.lease) == DiagnosticAdmission.Detached); check(r.worker.pending == 0) }
    cases["rejected worker submission releases admission"] = { val o = Observer(); val c = diagnosticCoordinator(Backend(), Executor { throw RejectedExecutionException() }) { it() }; val l = c.attach(o::receive); check(c.startHandshake(l) is DiagnosticAdmission.Accepted); check(!o.last.nativeBusy); check(o.last.availability == DiagnosticAvailability.Unavailable(DiagnosticError.NATIVE_FAILURE)) }
    cases["delayed delivery rechecks lease and current snapshot"] = { val deliveries = ArrayDeque<() -> Unit>(); val w = ManualWorker(); val c = diagnosticCoordinator(Backend(),w) { deliveries.addLast(it) }; var deliveriesToDead = 0; val l = c.attach { deliveriesToDead++ }; c.startHandshake(l); w.run(); c.detach(l); while(deliveries.isNotEmpty()) deliveries.removeFirst()(); check(deliveriesToDead == 0) }
    for (mode in listOf("dismiss", "timeout", "holder recreation")) {
        cases["blocking native across $mode stays single flight until actual return"] = {
            val entered=CountDownLatch(1); val release=CountDownLatch(1); val finished=CountDownLatch(1)
            val native=object : Backend() { override fun validateBundledContract(request: UiDiagnosticRequest): UiDiagnosticReport { entered.countDown(); check(release.await(5,TimeUnit.SECONDS)); return report(request) } }
            val w=Executor { work -> Thread { try { work.run() } finally { finished.countDown() } }.apply { isDaemon=true }.start() }
            // Handshake deliberately synchronous to prepare, validation actual blocked worker.
            var calls=0; val c=diagnosticCoordinator(native, Executor { if(calls++==0) it.run() else w.execute(it) }) { it() }
            val a=Observer(); val la=c.attach(a::receive); check(c.startHandshake(la) is DiagnosticAdmission.Accepted)
            val token=(c.startValidation(la,UiDiagnosticVariant.EQUIPMENT) as DiagnosticAdmission.Accepted).token
            try { check(entered.await(5,TimeUnit.SECONDS)); if(mode=="timeout") c.expire(la,token) else c.detach(la)
                val b=Observer(); val lb=c.attach(b::receive); check(b.last.nativeBusy); check(c.startHandshake(lb)==DiagnosticAdmission.Busy); check(c.startValidation(lb,UiDiagnosticVariant.INQUIRY)==DiagnosticAdmission.Busy)
                check(calls==2); check(b.last.presentation==DiagnosticPresentation.Idle)
                release.countDown(); check(finished.await(5,TimeUnit.SECONDS)); check(!b.last.nativeBusy); check(b.last.presentation==DiagnosticPresentation.Idle)
                if(mode=="timeout") check(a.last.presentation is DiagnosticPresentation.LocallyTimedOut)
                check(c.startHandshake(lb) is DiagnosticAdmission.Accepted)
            } finally { release.countDown() }
        }
    }
    cases["listener reentrant detach cannot deadlock admission"] = { val w=ManualWorker(); val c=diagnosticCoordinator(Backend(),w) { it() }; var l:DiagnosticLease?=null; l=c.attach { if(it.nativeBusy) c.detach(l!!) }; check(c.startHandshake(l) is DiagnosticAdmission.Accepted); w.run(); check(c.startHandshake(l)==DiagnosticAdmission.Detached) }
    var failures=0
    cases.forEach { (name, test) -> try { test(); println("PASS diagnostic $name") } catch(t:Throwable) { failures++; println("FAIL diagnostic $name: ${t.message}") } }
    check(failures==0) { "$failures/${cases.size} diagnostic checks failed" }
    println("${cases.size}/${cases.size} diagnostic coordinator checks passed; native FFI/Android runtime NOT_RUN")
}
