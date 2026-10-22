package com.mightyoung.muyon.product.documents.host

import com.mightyoung.muyon.product.ui.shell.ReaderSurfaceRequest
import com.mightyoung.muyon.product.ui.shell.ReaderVisibilityObservation

/** Existing Shell facts, not a second UI/lifecycle provider. Actual Activity owner
 * must sample its existing surface for this original native challenge. Null fails
 * closed. Shell c0 has no such challenge callback yet; production supplies none. */
internal fun interface ReaderActivityChallengeSampler {
    fun sample(original: ReaderSurfaceRequest, nativeChallengeId: String, receive: (ReaderVisibilityObservation?) -> Unit)
}
internal interface ReaderContinuationScheduler {
    fun requireOwnerThread()
    fun nowMillis(): Long
    fun scheduleAt(monotonicMillis: Long, action: () -> Unit): AutoCloseable
    fun post(action: () -> Unit)
}

/** Real native result identity supplied by future generated-policy adapter.
 * No IDs/generations synthesized here. No physical/PFD rendering assertion. */
internal class ReaderContinuationFrame(val request: ReaderSurfaceRequest,
    val presentationId: String, val frameGeneration: String, val deadline: ReaderPresentationDeadline) {
    init { require(presentationId.isNotBlank() && frameGeneration.matches(Regex("0|[1-9][0-9]{0,19}"))) }
}
internal sealed class ReaderContinuationResult {
    class Checked(val frame: ReaderContinuationFrame) : ReaderContinuationResult()
    class Replaced(val frame: ReaderContinuationFrame) : ReaderContinuationResult()
    class Unknown(val originalAttemptId: String) : ReaderContinuationResult() {
        init { require(originalAttemptId.isNotBlank() && originalAttemptId.length <= 128) }
    }
    object Unavailable : ReaderContinuationResult()
}
/** Conceptual Host port, NOT a guessed generated ABI. Native adapter must perform
 * exact original attempt/CAS, fresh challenge -> Activity sample, native renew +
 * genuine handoff + drain in shared batch. No boolean allow or automatic replay. */
internal interface ReaderContinuationBackend {
    // NONBLOCKING on controller queue. Actual synchronous FFI work must run on
    // a separate bounded native worker; a blocked controller cannot enforce timers.
    fun check(original: ReaderContinuationFrame, receive: (ReaderContinuationResult) -> Unit)
    fun renew(original: ReaderContinuationFrame,
        sample: (String, (ReaderVisibilityObservation?) -> Unit) -> Unit,
        receive: (ReaderContinuationResult) -> Unit)
}

/** Deadline/control state for an ALREADY real admitted frame. No opener, first
 * grant, fake native adapter or physical-state provider. Default missing backend
 * remains unavailable. Per-frame replacement never creates a new selection. */
internal class ReaderContinuationController(
    private val scheduler: ReaderContinuationScheduler,
    private val isOriginalCurrent: (ReaderSurfaceRequest) -> Boolean,
    private val clearExact: (ReaderContinuationFrame) -> Unit,
    private val publishReplacement: (ReaderContinuationFrame) -> Unit,
    private val disposeLateExact: (ReaderContinuationFrame) -> Unit,
    private val stopOriginalAdministrative: (ReaderContinuationFrame) -> Unit,
    private val backend: ReaderContinuationBackend? = null,
    private val activity: ReaderActivityChallengeSampler? = null,
) {
    private var current: ReaderContinuationFrame? = null
    private var wake: AutoCloseable? = null
    private var expiry: AutoCloseable? = null
    private var inFlightTimeout: AutoCloseable? = null
    private var generation = 0L
    private var busy = false
    private var held = false
    private val outstanding = mutableSetOf<String>()
    private val seenChallenges = mutableSetOf<String>()
    private val seenObservations = mutableSetOf<String>()
    private val unknownAttempts = linkedSetOf<String>()
    val unresolvedOriginalAttempts: Set<String> get() { scheduler.requireOwnerThread(); return unknownAttempts.toSet() }
    var cleanupUnknown = false; private set
    var originalUnknownAttempt: String? = null; private set

    fun admit(frame: ReaderContinuationFrame): Boolean {
        scheduler.requireOwnerThread()
        if (held || backend == null || activity == null || !isOriginalCurrent(frame.request) || frame.deadline.isExpired(scheduler.nowMillis())) return false
        check(current == null) // No replacement-by-latest; explicit continuation only.
        current = frame; arm(frame); return true
    }
    private fun advance() { generation = Math.addExact(generation, 1); wake?.close(); expiry?.close(); wake = null; expiry = null; inFlightTimeout?.close(); inFlightTimeout = null }
    private fun fail(frame: ReaderContinuationFrame, unknown: String? = null) {
        if (current !== frame) return
        held = true; originalUnknownAttempt = unknown; current = null; busy = false
        advance()
        try { clearExact(frame) } catch (_: Exception) { cleanupUnknown = true }
        // Captured ORIGINAL owner/root; no current business principal required.
        try { stopOriginalAdministrative(frame) } catch (_: Exception) { cleanupUnknown = true }
    }
    /** Real lifecycle/scope/selection stop uses original object identity. */
    fun stopExact(original: ReaderSurfaceRequest): Boolean {
        scheduler.requireOwnerThread()
        val frame = current ?: return false
        if (frame.request !== original) return false
        fail(frame); return true
    }
    /** Root/intent identity ignores page sequence but never a new selection/epoch. */
    fun stopReadingIntent(original: ReaderSurfaceRequest): Boolean {
        scheduler.requireOwnerThread()
        val frame = current ?: return false
        val actual = frame.request
        if (actual.surfaceId != original.surfaceId || actual.selectionSequence != original.selectionSequence ||
            actual.lifecycleEpoch != original.lifecycleEpoch || actual.selection != original.selection) return false
        fail(frame); return true
    }
    private fun sameNativeFrame(a: ReaderContinuationFrame, b: ReaderContinuationFrame?) = b != null &&
        a.presentationId == b.presentationId && a.frameGeneration == b.frameGeneration
    private fun discard(frame: ReaderContinuationFrame) {
        if (sameNativeFrame(frame, current)) return // duplicate wrapper must not close live output
        try { disposeLateExact(frame) } catch (_: Exception) { cleanupUnknown = true; current?.let { fail(it) } }
    }
    private fun arm(frame: ReaderContinuationFrame) {
        advance()
        val stamp = generation
        val now = scheduler.nowMillis()
        expiry = scheduler.scheduleAt(frame.deadline.expiresAtMillis) {
            scheduler.requireOwnerThread()
            if (generation == stamp && current === frame) fail(frame)
        }
        wake = scheduler.scheduleAt(frame.deadline.nextWakeAtMillis(now)) {
            scheduler.requireOwnerThread()
            if (generation == stamp && current === frame) tick(frame, stamp)
        }
    }
    private fun tick(frame: ReaderContinuationFrame, stamp: Long) {
        if (busy || current !== frame || generation != stamp) return
        if (!isOriginalCurrent(frame.request) || frame.deadline.isExpired(scheduler.nowMillis())) { fail(frame); return }
        busy = true
        // A hung check/sample must not leave display alive until a much later
        // hard expiry or block all future polling. No retries on timeout.
        inFlightTimeout = scheduler.scheduleAt(minOf(frame.deadline.expiresAtMillis, Math.addExact(scheduler.nowMillis(), 1_000))) {
            scheduler.requireOwnerThread()
            if (generation == stamp && current === frame && busy) fail(frame)
        }
        // Expiry timer remains armed during native/sample work. Late replies can
        // never extend a displayed expired frame or erase a newer replacement.
        val receive: (ReaderContinuationResult) -> Unit = { result -> scheduler.post { receive(frame, stamp, result) } }
        try {
            if (frame.deadline.renewalDue(scheduler.nowMillis())) {
                checkNotNull(backend).renew(frame, { challenge, callback ->
                    scheduler.post {
                        if (current !== frame || generation != stamp || !isOriginalCurrent(frame.request) ||
                            frame.deadline.isExpired(scheduler.nowMillis()) || challenge.isBlank() || challenge.length > 128 || seenChallenges.size >= 256 || !seenChallenges.add(challenge) || !outstanding.add(challenge)) callback(null)
                        else try {
                            val sampleStartedMillis = scheduler.nowMillis()
                            checkNotNull(activity).sample(frame.request, challenge) { observation -> scheduler.post {
                                val valid = outstanding.remove(challenge) && current === frame && generation == stamp &&
                                    isOriginalCurrent(frame.request) && !frame.deadline.isExpired(scheduler.nowMillis()) &&
                                    observation?.request === frame.request && observation.sampledAtNanos >= 0 &&
                                    observation.sampledAtNanos / 1_000_000 >= sampleStartedMillis &&
                                    scheduler.nowMillis() - observation.sampledAtNanos / 1_000_000 in 0..2_000 &&
                                    observation.observationId.isNotBlank() && observation.observationId.length <= 128 &&
                                    seenObservations.size < 256 && seenObservations.add(observation.observationId)
                                callback(if (valid) observation else null)
                            } }
                        } catch (_: Exception) { outstanding.remove(challenge); callback(null); fail(frame) }
                    }
                }, receive)
            } else checkNotNull(backend).check(frame, receive)
        } catch (_: Exception) { fail(frame) }
    }
    private fun receive(previous: ReaderContinuationFrame, stamp: Long, result: ReaderContinuationResult) {
        scheduler.requireOwnerThread()
        // Original outcome retention is independent of display liveness. A late
        // unknown must remain queryable without touching a newer frame.
        if (result is ReaderContinuationResult.Unknown) {
            if (unknownAttempts.size < 256) unknownAttempts.add(result.originalAttemptId)
            else { held = true; current?.let { fail(it) } }
            if (current === previous || (held && current == null)) originalUnknownAttempt = result.originalAttemptId
        }
        val supplied = when (result) { is ReaderContinuationResult.Checked -> result.frame; is ReaderContinuationResult.Replaced -> result.frame; else -> null }
        if (current !== previous || generation != stamp || !busy || !isOriginalCurrent(previous.request) || previous.deadline.isExpired(scheduler.nowMillis())) {
            if (supplied != null) discard(supplied)
            if (current === previous) fail(previous)
            return
        }
        busy = false
        when (result) {
            is ReaderContinuationResult.Unknown -> fail(previous, result.originalAttemptId)
            ReaderContinuationResult.Unavailable -> fail(previous)
            is ReaderContinuationResult.Checked -> {
                if (supplied == null || supplied.request !== previous.request || supplied.presentationId != previous.presentationId ||
                    supplied.frameGeneration != previous.frameGeneration || supplied.deadline.expiresAtMillis > previous.deadline.expiresAtMillis ||
                    supplied.deadline.isExpired(scheduler.nowMillis())) {
                    if (supplied != null && supplied !== previous) discard(supplied)
                    fail(previous)
                } else { current = supplied; arm(supplied) }
            }
            is ReaderContinuationResult.Replaced -> {
                if (supplied == null || supplied.request !== previous.request ||
                    (supplied.presentationId == previous.presentationId && supplied.frameGeneration == previous.frameGeneration) ||
                    supplied.deadline.isExpired(scheduler.nowMillis())) {
                    if (supplied != null && supplied !== previous) discard(supplied)
                    fail(previous)
                } else {
                    try { clearExact(previous); current = supplied; publishReplacement(supplied); arm(supplied) }
                    catch (_: Exception) { current = supplied; fail(supplied) }
                }
            }
        }
    }
}
