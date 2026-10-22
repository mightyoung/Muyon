package com.mightyoung.muyon.androidlab

import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.Executor
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/** Create once in Application. Panel/Activity owners only attach and detach. */
fun createRustDiagnosticCoordinator(native: DiagnosticNativePort, delivery: (() -> Unit) -> Unit): RustDiagnosticCoordinator =
    diagnosticCoordinator(native, ThreadPoolExecutor(1, 1, 0L, TimeUnit.MILLISECONDS, ArrayBlockingQueue(1),
        { work -> Thread(work, "muyon-rust-diagnostic").apply { isDaemon = true } }, ThreadPoolExecutor.AbortPolicy()), delivery)

internal fun diagnosticCoordinator(native: DiagnosticNativePort, worker: Executor, delivery: (() -> Unit) -> Unit): RustDiagnosticCoordinator =
    SingleFlightDiagnosticCoordinator(native, worker, delivery)

private class SingleFlightDiagnosticCoordinator(
    private val native: DiagnosticNativePort,
    private val worker: Executor,
    private val delivery: (() -> Unit) -> Unit,
) : RustDiagnosticCoordinator {
    private data class Observer(val listener: (DiagnosticSnapshot) -> Unit,
        var token: DiagnosticCallToken? = null, var presentation: DiagnosticPresentation = DiagnosticPresentation.Idle)
    private val lock = Any()
    private var generation = 0L
    private var callSequence = 0L
    private var slot: DiagnosticCallToken? = null
    private var availability: DiagnosticAvailability = DiagnosticAvailability.NotChecked
    private val observers = linkedMapOf<DiagnosticLease, Observer>()

    override fun attach(listener: (DiagnosticSnapshot) -> Unit): DiagnosticLease {
        val lease = synchronized(lock) { DiagnosticLease(++generation).also { observers[it] = Observer(listener) } }
        publish(listOf(lease))
        return lease
    }
    override fun detach(lease: DiagnosticLease) { synchronized(lock) { observers.remove(lease) } }
    override fun expire(lease: DiagnosticLease, token: DiagnosticCallToken) {
        val changed = synchronized(lock) {
            val observer = observers[lease]
            if (observer?.token != token) false else {
                observer.token = null
                observer.presentation = DiagnosticPresentation.LocallyTimedOut(token)
                true
            }
        }
        if (changed) publish(listOf(lease))
    }
    override fun startHandshake(lease: DiagnosticLease): DiagnosticAdmission = start(lease, null)
    override fun startValidation(lease: DiagnosticLease, variant: UiDiagnosticVariant): DiagnosticAdmission = start(lease, variant)

    private fun start(lease: DiagnosticLease, variant: UiDiagnosticVariant?): DiagnosticAdmission {
        val admitted = synchronized(lock) {
            val observer = observers[lease] ?: return DiagnosticAdmission.Detached
            if (slot != null) return DiagnosticAdmission.Busy
            val ready = availability as? DiagnosticAvailability.Ready
            if (variant != null && ready == null) return DiagnosticAdmission.NotReady
            val token = DiagnosticCallToken("diag_${++callSequence}", lease.generation)
            slot = token
            observer.token = token
            observer.presentation = DiagnosticPresentation.Running(token)
            token to ready?.info
        }
        val (token, ready) = admitted
        publishAll()
        try {
            worker.execute {
                var result: Any? = null
                var error: DiagnosticError? = null
                try {
                    if (variant == null) {
                        val info = native.bridgeInfo()
                        if (info.protocol != 1u || !Regex("[0-9a-f]{40}").matches(info.buildIdentity) ||
                            info.capability != UiDiagnosticCapability.BUNDLED_DECLARATION_VALIDATION || info.model ||
                            info.attachments || info.businessRead || info.write || info.execute) error = DiagnosticError.PROTOCOL_MISMATCH
                        else result = info
                    } else {
                        val request = UiDiagnosticRequest(1u, token.requestId, variant)
                        val report = native.validateBundledContract(request)
                        if (report.protocol != request.protocol || report.requestId != request.requestId || report.variant != variant ||
                            report.buildIdentity != ready!!.buildIdentity) error = DiagnosticError.REQUEST_MISMATCH
                        else result = report
                    }
                } catch (failure: DiagnosticNativeFailure) { error = failure.code }
                catch (_: LinkageError) { error = DiagnosticError.NATIVE_LOAD }
                catch (_: Exception) { error = DiagnosticError.NATIVE_FAILURE }
                finally { complete(lease, token, variant, result, error ?: if (result == null) DiagnosticError.NATIVE_FAILURE else null) }
            }
        } catch (_: Exception) { complete(lease, token, variant, null, DiagnosticError.NATIVE_FAILURE) }
        return DiagnosticAdmission.Accepted(token)
    }
    private fun complete(lease: DiagnosticLease, token: DiagnosticCallToken, variant: UiDiagnosticVariant?, result: Any?, error: DiagnosticError?) {
        synchronized(lock) {
            // Only the actual worker return/error (or failed submission) owns this release.
            if (slot != token) return
            slot = null
            val observer = observers[lease]
            if (observer?.token == token) {
                observer.token = null
                if (variant == null) {
                    availability = if (error == null) DiagnosticAvailability.Ready(result as UiBridgeInfo)
                        else DiagnosticAvailability.Unavailable(error)
                    observer.presentation = if (error == null) DiagnosticPresentation.Idle else DiagnosticPresentation.Failed(token, error)
                } else observer.presentation = if (error == null) DiagnosticPresentation.Complete(token, result as UiDiagnosticReport)
                    else DiagnosticPresentation.Failed(token, error)
            }
        }
        publishAll()
    }
    private fun publishAll() = publish(synchronized(lock) { observers.keys.toList() })
    private fun publish(leases: List<DiagnosticLease>) {
        // Neither the dispatcher nor arbitrary/reentrant listeners run under the admission lock.
        leases.forEach { lease ->
            try { delivery {
                val update = synchronized(lock) { observers[lease]?.let { it.listener to DiagnosticSnapshot(availability, slot != null, it.presentation) } }
                if (update != null) try { update.first(update.second) } catch (_: Exception) { /* one observer cannot strand native slot */ }
            } } catch (_: Exception) { /* rejected display delivery does not own the native call */ }
        }
    }
}
