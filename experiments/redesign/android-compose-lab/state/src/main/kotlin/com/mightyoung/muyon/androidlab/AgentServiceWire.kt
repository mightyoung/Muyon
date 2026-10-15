package com.mightyoung.muyon.androidlab

/** Private, closed IPC projection. No dynamic operation, business body or native objects. */
enum class UiAgentLocalStatus { INITIALIZING, UNAVAILABLE, BUSY, INVALID_REQUEST }
enum class UiAgentError { UNSUPPORTED_PROTOCOL, INVALID_ROOT, INVALID_REQUEST_ID, INVALID_IDENTITY, INVALID_GENERATION, EPOCH_MISMATCH, CLIENT_UNAVAILABLE, CLIENT_NOT_VISIBLE, REQUEST_CONFLICT, BUSY, CLOSED, TARGET_UNAVAILABLE, RECOVERY_REQUIRED, BUDGET_EXCEEDED, INTERNAL_FAILURE }
enum class UiAgentAck { APPLIED, REQUESTED, ALREADY_TERMINAL, NOT_RUNNING, NOT_ACTIVE, CLOSING, CLOSED }
sealed interface UiAgentWireReply {
    data class Local(val status: UiAgentLocalStatus): UiAgentWireReply
    data class Connected(val meta: UiAgentMeta, val client: UiAgentClientRef, val phase: UiAgentServicePhase): UiAgentWireReply
    data class Snapshot(val value: UiAgentSnapshot): UiAgentWireReply
    data class Started(val meta: UiAgentMeta, val run: UiAgentRun, val existing: Boolean): UiAgentWireReply
    data class Ack(val meta: UiAgentMeta, val value: UiAgentAck): UiAgentWireReply
    data class Rejected(val meta: UiAgentMeta, val error: UiAgentError): UiAgentWireReply
    data class Unresolved(val meta: UiAgentMeta): UiAgentWireReply
    data class Busy(val meta: UiAgentMeta): UiAgentWireReply
}
object AgentServiceWire {
    const val MAX_PAYLOAD_BYTES = 7680 // Actual Android Parcel including overhead is separately capped at 8KiB.
    fun encode(reply: UiAgentWireReply, expectedBuild: String): ByteArray? = null
    fun decode(bytes: ByteArray, expectedBuild: String): UiAgentWireReply? = null
}
