package com.mightyoung.muyon.product.documents.host

import com.mightyoung.muyon.product.ui.documents.DocumentFormat
import com.mightyoung.muyon.product.ui.documents.ReaderDocumentRef
import com.mightyoung.muyon.product.ui.shell.ReaderExactSelection
import com.mightyoung.muyon.product.ui.shell.ReaderSurfaceRequest
import com.mightyoung.muyon.product.ui.shell.ReaderVisibilityObservation

private class Clock : ReaderContinuationScheduler {
    var now = 0L
    private class Job(val time: Long, val action: () -> Unit, var cancelled: Boolean = false)
    private val jobs = mutableListOf<Job>()
    override fun requireOwnerThread() = Unit // SYNTHETIC single-thread test scheduler
    override fun nowMillis() = now
    override fun scheduleAt(monotonicMillis: Long, action: () -> Unit): AutoCloseable {
        val job = Job(monotonicMillis, action); jobs.add(job)
        return AutoCloseable { job.cancelled = true }
    }
    override fun post(action: () -> Unit) = action()
    fun advance(to: Long) {
        repeat(1000) {
            val next = jobs.filter { !it.cancelled && it.time <= to }.minByOrNull { it.time }
            if (next == null) { now = to; return }
            next.cancelled = true; now = next.time; next.action()
        }
        error("busy_schedule_loop")
    }
}
private class FixtureBackend(val clock: Clock) : ReaderContinuationBackend {
    var checks = 0; var renewals = 0
    var original: ReaderContinuationFrame? = null
    var respond: ((ReaderContinuationResult) -> Unit)? = null
    var challenge: ((String, (ReaderVisibilityObservation?) -> Unit) -> Unit)? = null
    override fun check(original: ReaderContinuationFrame, receive: (ReaderContinuationResult) -> Unit) {
        checks++; receive(ReaderContinuationResult.Checked(ReaderContinuationFrame(original.request, original.presentationId,
            original.frameGeneration, original.deadline.checked(clock.now, original.deadline.expiresAtMillis-clock.now, 1000))))
    }
    override fun renew(original: ReaderContinuationFrame, sample: (String, (ReaderVisibilityObservation?) -> Unit) -> Unit,
        receive: (ReaderContinuationResult) -> Unit) { renewals++; this.original = original; respond = receive; challenge = sample }
}
fun readerControllerChecks() {
    val request = ReaderSurfaceRequest("real-surface-fixture", 1, 1, 1, 0,
        ReaderExactSelection(ReaderDocumentRef("workspace", "project", "doc", "1", DocumentFormat.PDF), "source", "a".repeat(64)))
    val clock = Clock(); val backend = FixtureBackend(clock)
    var clears = 0; var published = 0; var lateCloses = 0; var stops = 0
    val controller = ReaderContinuationController(clock, { true }, { clears++ }, { published++ }, { lateCloses++ }, { stops++ }, backend,
        ReaderActivityChallengeSampler { original, _, receive -> receive(ReaderVisibilityObservation(clock.now*1_000_000, "observation-fixture-${clock.now}", original)) })
    val first = ReaderContinuationFrame(request, "actual-native-fixture-1", "1", ReaderPresentationDeadline.fromNative(0, 15000, 1000))
    check(controller.admit(first))
    clock.advance(12999); check(backend.renewals == 0)
    clock.advance(13000); check(backend.renewals == 1 && backend.checks > 0)
    var samples = 0
    backend.challenge!!("challenge-fixture") { if (it != null) samples++ }
    backend.challenge!!("challenge-fixture") { if (it != null) samples++ }
    backend.challenge!!("different-challenge-fixture") { if (it != null) samples++ }
    check(samples == 1) // observation itself is also single-use across challenges
    // one native original challenge cannot be resampled/replayed
    val next = ReaderContinuationFrame(request, "actual-native-fixture-2", "1", ReaderPresentationDeadline.fromNative(13000, 15000, 1000))
    backend.respond!!(ReaderContinuationResult.Replaced(next))
    check(clears == 1 && published == 1)
    // Duplicate reply wrapper with same genuine native frame must NOT close new output.
    backend.respond!!(ReaderContinuationResult.Replaced(ReaderContinuationFrame(request, next.presentationId, next.frameGeneration, next.deadline)))
    check(lateCloses == 0)
    clock.advance(26000); check(backend.renewals == 2) // static same page renews again, no new selection
    backend.challenge!!("challenge-fixture-2") { check(it != null) }
    val third = ReaderContinuationFrame(request, "actual-native-fixture-3", "1", ReaderPresentationDeadline.fromNative(26000, 15000, 1000))
    backend.respond!!(ReaderContinuationResult.Replaced(third))
    clock.advance(39000); check(backend.renewals == 3 && clears == 2 && published == 2) // synthetic same page survives >30s
    clock.advance(40000); check(clears == 3 && stops == 1) // bounded hung-renew timeout before hard expiry
    clock.advance(41000)
    backend.respond!!(ReaderContinuationResult.Unknown("original-attempt-fixture"))
    check(controller.originalUnknownAttempt == "original-attempt-fixture")
    check(!controller.admit(next)) // no implicit resume/replay
    println("PASS reader controller: static-page earliest-TTL renew, one-use challenge, duplicate native-frame reply, hard expiry/no replay; synthetic backend/clock only")
}
