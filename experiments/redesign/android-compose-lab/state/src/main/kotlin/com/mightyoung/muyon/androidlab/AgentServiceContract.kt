package com.mightyoung.muyon.androidlab

/** Closed private projections. No authority, raw data, counters or generated/native objects. */
enum class UiAgentVariant { EQUIPMENT, RESEARCH, INQUIRY, SEEDED_EQUIPMENT }
enum class UiAgentServicePhase { INITIALIZING, READY, RECOVERY_REQUIRED, CLOSING, CLOSED }
enum class UiAgentTerminal { COMPLETED, CANCELLED, FAILED, BUDGET_EXHAUSTED, OUTCOME_UNKNOWN }
enum class UiAgentReceiptOutcome { NOT_STARTED, UNKNOWN, RECORDED_SUCCESS, RECORDED_FAILURE }
enum class UiAgentReason { NONE, CANCELLED, AUTHORITY_DENIED, PURPOSE_DENIED, CONTRACT_REJECTED, STORAGE_FAILURE, PROVIDER_FAILURE, DEADLINE_EXCEEDED, BUDGET_EXCEEDED, INTERRUPTED, INTERNAL_FAILURE }
enum class UiAgentNoAdmissionReason { CANCELLED_BEFORE_ADMISSION, QUOTA_EXCEEDED, DIRECTORY_REJECTED, INDEX_VALIDATION_REJECTED, STORAGE_REJECTED_BEFORE_ADMISSION }
data class UiAgentMeta(val protocol: UInt, val buildIdentity: String, val serviceEpoch: String, val revision: Long)
data class UiAgentClientRef(val epoch: String, val lease: String)
data class UiAgentIntent(val requestId: String, val variant: UiAgentVariant, val sourceBuildIdentity: String)
data class UiAgentTask(val taskId: String, val attemptId: String)
data class UiAgentRunIdentity(val runId: String, val admittedEpoch: String, val actualTask: UiAgentTask? = null)
data class UiAgentReceipt(val opaqueId: String?, val outcome: UiAgentReceiptOutcome)
data class UiAgentSummary(val intent: UiAgentIntent, val identity: UiAgentRunIdentity, val terminal: UiAgentTerminal,
    val reason: UiAgentReason, val receipt: UiAgentReceipt)
sealed interface UiAgentRun {
    val intent: UiAgentIntent
    data class Queued(override val intent: UiAgentIntent) : UiAgentRun
    data class Admitted(override val intent: UiAgentIntent, val identity: UiAgentRunIdentity) : UiAgentRun
    data class Running(override val intent: UiAgentIntent, val identity: UiAgentRunIdentity) : UiAgentRun
    data class Terminal(val summary: UiAgentSummary) : UiAgentRun { override val intent get() = summary.intent }
    data class SettledNoAdmission(override val intent: UiAgentIntent, val reason: UiAgentNoAdmissionReason) : UiAgentRun
    data class Unresolved(override val intent: UiAgentIntent, val identity: UiAgentRunIdentity?, val receipt: UiAgentReceipt) : UiAgentRun
}
data class UiAgentSnapshot(val meta: UiAgentMeta, val phase: UiAgentServicePhase, val run: UiAgentRun?)
enum class UiAgentTransport { UNBOUND, BINDING, INITIALIZING, CONNECTED, UNAVAILABLE, LOST }
enum class UiAgentApply { APPLIED, STALE, CONFLICT, INVALID }
enum class UiAgentObservationKind { CURRENT, STATUS, HISTORICAL }
@ConsistentCopyVisibility
data class UiAgentConnectionTicket internal constructor(val generation: Long)
@ConsistentCopyVisibility
data class UiAgentObservationTicket internal constructor(val connection: Long, val leaseGeneration: Long,
    val displayGeneration: Long, val client: UiAgentClientRef, val kind: UiAgentObservationKind, val expectedIntent: UiAgentIntent?)
sealed interface UiAgentStartDecision {
    data class Submit(val client: UiAgentClientRef, val intent: UiAgentIntent) : UiAgentStartDecision
    data object Busy : UiAgentStartDecision
    data object Unavailable : UiAgentStartDecision
    data object ReconcileFirst : UiAgentStartDecision
    data object Invalid : UiAgentStartDecision
}
data class UiAgentVisibility(val client: UiAgentClientRef, val generation: Long, val visible: Boolean)
data class UiAgentRelease(val client: UiAgentClientRef, val generation: Long)
