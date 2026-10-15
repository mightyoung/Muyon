package com.mightyoung.muyon.androidlab

/** Main-thread confined state policy; all RPC and native execution live outside this class. */
class AgentServiceClientState(private val expectedBuild: String) {
    var transport = UiAgentTransport.UNBOUND; private set
    var client: UiAgentClientRef? = null; private set
    var snapshot: UiAgentSnapshot? = null; private set
    var historical: UiAgentSnapshot? = null; private set
    var selectedIntent: UiAgentIntent? = null; private set
    var observationUnknown = false; private set
    var visible = false; private set
    var visibilityGeneration = 0L; private set
    fun beginBinding(): UiAgentConnectionTicket = UiAgentConnectionTicket(0)
    fun transportInitializing(ticket: UiAgentConnectionTicket) = Unit
    fun connected(ticket: UiAgentConnectionTicket, meta: UiAgentMeta, lease: String, phase: UiAgentServicePhase): UiAgentApply = UiAgentApply.INVALID
    fun transportLost(ticket: UiAgentConnectionTicket) = Unit
    fun capture(kind: UiAgentObservationKind = UiAgentObservationKind.CURRENT): UiAgentObservationTicket? = null
    fun apply(ticket: UiAgentObservationTicket, incoming: UiAgentSnapshot): UiAgentApply = UiAgentApply.INVALID
    fun detachDisplay() = Unit
    fun activityVisibility(activityId: String, isVisible: Boolean): UiAgentVisibility? = null
    fun visibilityAcknowledged(client: UiAgentClientRef, generation: Long, accepted: Boolean) = Unit
    fun userStart(requestId: String, variant: UiAgentVariant): UiAgentStartDecision = UiAgentStartDecision.Unavailable
    fun release(): UiAgentRelease? = null
}
internal fun validAgentSnapshot(snapshot: UiAgentSnapshot, expectedBuild: String): Boolean = false
