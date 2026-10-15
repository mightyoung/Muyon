package com.mightyoung.muyon.androidlab

/** Main-thread confined presentation policy. This class never performs an RPC or native work. */
class AgentServiceClientState(private val expectedBuild: String) {
    var transport = UiAgentTransport.UNBOUND; private set
    var client: UiAgentClientRef? = null; private set
    var snapshot: UiAgentSnapshot? = null; private set
    var historical: UiAgentSnapshot? = null; private set
    var selectedIntent: UiAgentIntent? = null; private set
    var observationUnknown = false; private set
    var visible = false; private set
    var visibilityGeneration = 0L; private set
    private var connection = 0L
    private var leaseGeneration = 0L
    private var displayGeneration = 0L
    private var phase: UiAgentServicePhase? = null
    private var epoch: String? = null
    private var historicalIntent: UiAgentIntent? = null
    private var reconciled = false
    private var pending = false
    private var stopIssued = false
    private var acknowledgedVisibility: Long? = null
    private val activities = mutableSetOf<String>()

    fun beginBinding(): UiAgentConnectionTicket {
        connection = Math.incrementExact(connection)
        invalidateLease()
        transport = UiAgentTransport.BINDING
        return UiAgentConnectionTicket(connection)
    }
    fun transportInitializing(ticket: UiAgentConnectionTicket) {
        if (ticket.generation == connection && client == null) transport = UiAgentTransport.INITIALIZING
    }
    fun connected(ticket: UiAgentConnectionTicket, meta: UiAgentMeta, lease: String, phase: UiAgentServicePhase): UiAgentApply {
        if (ticket.generation != connection) return UiAgentApply.STALE
        if (!validAgentMeta(meta, expectedBuild) || !hex32.matches(lease)) return UiAgentApply.INVALID
        val ref = UiAgentClientRef(meta.serviceEpoch, lease)
        if (transport == UiAgentTransport.CONNECTED && client == ref) return UiAgentApply.APPLIED
        if (epoch != meta.serviceEpoch) stopIssued = false
        epoch = meta.serviceEpoch
        invalidateLease()
        client = ref
        this.phase = phase
        transport = UiAgentTransport.CONNECTED
        return UiAgentApply.APPLIED
    }
    fun transportLost(ticket: UiAgentConnectionTicket) {
        if (ticket.generation != connection) return
        invalidateLease()
        transport = UiAgentTransport.LOST
        observationUnknown = true
    }
    private fun invalidateLease() {
        leaseGeneration = Math.incrementExact(leaseGeneration)
        client = null
        acknowledgedVisibility = null
        reconciled = false
    }
    fun capture(kind: UiAgentObservationKind = UiAgentObservationKind.CURRENT): UiAgentObservationTicket? {
        val ref = client ?: return null
        if (transport != UiAgentTransport.CONNECTED) return null
        return UiAgentObservationTicket(connection, leaseGeneration, displayGeneration, ref, kind,
            if (kind == UiAgentObservationKind.STATUS) selectedIntent else null)
    }
    fun captureLookup(expected: UiAgentIntent): UiAgentObservationTicket? {
        if (!validIntent(expected)) return null
        return capture(UiAgentObservationKind.HISTORICAL)?.copy(expectedIntent = expected)
    }
    fun apply(ticket: UiAgentObservationTicket, incoming: UiAgentSnapshot): UiAgentApply {
        if (ticket.connection != connection || ticket.leaseGeneration != leaseGeneration ||
            ticket.displayGeneration != displayGeneration || ticket.client != client || transport != UiAgentTransport.CONNECTED)
            return UiAgentApply.STALE
        if (!validAgentSnapshot(incoming, expectedBuild)) return UiAgentApply.INVALID
        if (incoming.meta.serviceEpoch != client?.epoch) return UiAgentApply.STALE
        if (ticket.kind == UiAgentObservationKind.HISTORICAL &&
            (ticket.expectedIntent == null || incoming.run?.intent != ticket.expectedIntent)) return UiAgentApply.CONFLICT
        val old = if (ticket.kind == UiAgentObservationKind.HISTORICAL) {
            if (historicalIntent == ticket.expectedIntent) historical else null
        } else snapshot
        if (old?.meta?.serviceEpoch == incoming.meta.serviceEpoch) {
            if (incoming.meta.revision < old.meta.revision) return UiAgentApply.STALE
            if (incoming.meta.revision == old.meta.revision && old != incoming) return UiAgentApply.CONFLICT
        }
        if (ticket.kind != UiAgentObservationKind.HISTORICAL && old?.meta?.serviceEpoch == incoming.meta.serviceEpoch) {
            if (old.phase == UiAgentServicePhase.CLOSED && incoming.phase != UiAgentServicePhase.CLOSED)
                return UiAgentApply.CONFLICT
            if (old.phase == UiAgentServicePhase.CLOSING && incoming.phase != UiAgentServicePhase.CLOSING && incoming.phase != UiAgentServicePhase.CLOSED)
                return UiAgentApply.CONFLICT
            if (old.run != null && incoming.run == null) return UiAgentApply.CONFLICT
        }
        if (ticket.kind == UiAgentObservationKind.STATUS &&
            (ticket.expectedIntent == null || incoming.run?.intent != ticket.expectedIntent)) return UiAgentApply.CONFLICT
        if (ticket.kind != UiAgentObservationKind.HISTORICAL && pending && incoming.run?.intent != selectedIntent)
            return UiAgentApply.CONFLICT
        if (old?.run != null && incoming.run?.intent == old.run.intent && !compatibleAgentTransition(old.run, incoming.run))
            return UiAgentApply.CONFLICT
        if (ticket.kind == UiAgentObservationKind.HISTORICAL) {
            historical = incoming
            historicalIntent = ticket.expectedIntent
        } else {
            snapshot = incoming
            phase = incoming.phase
            incoming.run?.let { selectedIntent = it.intent; pending = false }
            if (ticket.kind == UiAgentObservationKind.CURRENT) reconciled = true
            observationUnknown = false
        }
        return UiAgentApply.APPLIED
    }
    fun detachDisplay() { displayGeneration = Math.incrementExact(displayGeneration) }
    fun activityVisibility(activityId: String, isVisible: Boolean): UiAgentVisibility? {
        require(activityId.isNotEmpty())
        if (isVisible) activities.add(activityId) else activities.remove(activityId)
        val next = activities.isNotEmpty()
        if (next == visible) return null
        visible = next
        visibilityGeneration = Math.incrementExact(visibilityGeneration)
        acknowledgedVisibility = null
        if (!visible && client != null) stopIssued = true
        return client?.let { UiAgentVisibility(it, visibilityGeneration, visible) }
    }
    /** A new native lease starts invisible even when an Activity is already visible. */
    fun visibilityForCurrentLease(): UiAgentVisibility? = client?.let { UiAgentVisibility(it, visibilityGeneration, visible) }
    fun visibilityAcknowledged(client: UiAgentClientRef, generation: Long, accepted: Boolean) {
        if (client == this.client && generation == visibilityGeneration && accepted) acknowledgedVisibility = generation
    }
    fun userStart(requestId: String, variant: UiAgentVariant): UiAgentStartDecision {
        if (!requestPattern.matches(requestId)) return UiAgentStartDecision.Invalid
        val ref = client ?: return UiAgentStartDecision.Unavailable
        if (transport != UiAgentTransport.CONNECTED || phase != UiAgentServicePhase.READY || !visible ||
            acknowledgedVisibility != visibilityGeneration || stopIssued) return UiAgentStartDecision.Unavailable
        if (!reconciled) return UiAgentStartDecision.ReconcileFirst
        if (pending || snapshot?.run.let { it != null && it !is UiAgentRun.Terminal && it !is UiAgentRun.SettledNoAdmission })
            return UiAgentStartDecision.Busy
        val intent = UiAgentIntent(requestId, variant, expectedBuild)
        selectedIntent = intent
        pending = true
        return UiAgentStartDecision.Submit(ref, intent)
    }
    fun release(): UiAgentRelease? {
        val ref = client ?: return null
        visibilityGeneration = Math.incrementExact(visibilityGeneration)
        stopIssued = true
        val result = UiAgentRelease(ref, visibilityGeneration)
        invalidateLease()
        transport = UiAgentTransport.UNBOUND
        return result
    }
}

private val hex32 = Regex("[0-9a-f]{32}")
private val hex40 = Regex("[0-9a-f]{40}")
private val requestPattern = Regex("[A-Za-z0-9_-]{1,64}")
private val coreIdentifier = Regex("[A-Za-z0-9_.-]{1,64}")
private fun validAgentMeta(meta: UiAgentMeta, expectedBuild: String) = meta.protocol == 1u &&
    hex40.matches(meta.buildIdentity) && meta.buildIdentity == expectedBuild && hex32.matches(meta.serviceEpoch) && meta.revision >= 0
private fun validIntent(intent: UiAgentIntent) = requestPattern.matches(intent.requestId) && hex40.matches(intent.sourceBuildIdentity)
private fun validIdentity(identity: UiAgentRunIdentity) = hex32.matches(identity.runId) && hex32.matches(identity.admittedEpoch) &&
    (identity.actualTask?.let { coreIdentifier.matches(it.taskId) && coreIdentifier.matches(it.attemptId) } ?: true)
private fun validReceipt(receipt: UiAgentReceipt) = when (receipt.outcome) {
    UiAgentReceiptOutcome.NOT_STARTED -> receipt.opaqueId == null
    UiAgentReceiptOutcome.UNKNOWN -> receipt.opaqueId == null || coreIdentifier.matches(receipt.opaqueId)
    UiAgentReceiptOutcome.RECORDED_SUCCESS, UiAgentReceiptOutcome.RECORDED_FAILURE ->
        receipt.opaqueId?.let { coreIdentifier.matches(it) } == true
}
internal fun validAgentSnapshot(snapshot: UiAgentSnapshot, expectedBuild: String): Boolean {
    if (!validAgentMeta(snapshot.meta, expectedBuild)) return false
    val run = snapshot.run ?: return true
    if (!validIntent(run.intent)) return false
    return when (run) {
        is UiAgentRun.Queued, is UiAgentRun.SettledNoAdmission -> true
        is UiAgentRun.Admitted -> validIdentity(run.identity)
        is UiAgentRun.Running -> validIdentity(run.identity)
        is UiAgentRun.Unresolved -> (run.identity?.let(::validIdentity) ?: true) && validReceipt(run.receipt)
        is UiAgentRun.Terminal -> with(run.summary) {
            validIdentity(identity) && validReceipt(receipt) &&
                (terminal != UiAgentTerminal.COMPLETED || (identity.actualTask != null && reason == UiAgentReason.NONE &&
                    receipt.outcome == UiAgentReceiptOutcome.RECORDED_SUCCESS))
        }
    }
}
private fun identity(run: UiAgentRun): UiAgentRunIdentity? = when(run) {
    is UiAgentRun.Admitted -> run.identity
    is UiAgentRun.Running -> run.identity
    is UiAgentRun.Terminal -> run.summary.identity
    is UiAgentRun.Unresolved -> run.identity
    else -> null
}
private fun compatibleAgentTransition(old: UiAgentRun, next: UiAgentRun): Boolean {
    if (old is UiAgentRun.Terminal || old is UiAgentRun.SettledNoAdmission) return old == next
    val before = identity(old)
    val after = identity(next)
    if (before != null && (after == null || before.runId != after.runId || before.admittedEpoch != after.admittedEpoch ||
        (before.actualTask != null && before.actualTask != after.actualTask))) return false
    if (old is UiAgentRun.Running && next is UiAgentRun.Admitted) return false
    return true
}
