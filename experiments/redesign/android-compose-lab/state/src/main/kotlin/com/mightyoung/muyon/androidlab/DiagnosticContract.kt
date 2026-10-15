package com.mightyoung.muyon.androidlab

/** Private lab projection, not a business/execution/authorization contract. */
enum class UiDiagnosticVariant { EQUIPMENT, RESEARCH, INQUIRY, SEEDED_EQUIPMENT }
enum class UiDiagnosticCapability { BUNDLED_DECLARATION_VALIDATION }
data class UiBridgeInfo(
    val protocol: UInt, val buildIdentity: String, val capability: UiDiagnosticCapability,
    val model: Boolean, val attachments: Boolean, val businessRead: Boolean, val write: Boolean, val execute: Boolean,
)
data class UiDiagnosticRequest(val protocol: UInt, val requestId: String, val variant: UiDiagnosticVariant)
data class UiDiagnosticReport(
    val protocol: UInt, val requestId: String, val buildIdentity: String, val variant: UiDiagnosticVariant,
    val namespace: String, val catalogGeneration: ULong, val dataCount: UInt, val operationCount: UInt,
    val relationCount: UInt, val viewCount: UInt,
)
enum class DiagnosticError {
    NATIVE_LOAD, UNSUPPORTED_PROTOCOL, INVALID_REQUEST_ID, DECLARATION_REJECTED, INTERNAL_FAILURE,
    PROTOCOL_MISMATCH, REQUEST_MISMATCH, NATIVE_FAILURE,
}
class DiagnosticNativeFailure(val code: DiagnosticError) : RuntimeException(code.name)
interface DiagnosticNativePort {
    fun bridgeInfo(): UiBridgeInfo
    fun validateBundledContract(request: UiDiagnosticRequest): UiDiagnosticReport
}
sealed interface DiagnosticAvailability {
    data object NotChecked : DiagnosticAvailability
    data class Ready(val info: UiBridgeInfo) : DiagnosticAvailability
    data class Unavailable(val code: DiagnosticError) : DiagnosticAvailability
}
@ConsistentCopyVisibility
data class DiagnosticLease internal constructor(val generation: Long)
@ConsistentCopyVisibility
data class DiagnosticCallToken internal constructor(val requestId: String, val ownerGeneration: Long)
sealed interface DiagnosticAdmission {
    data class Accepted(val token: DiagnosticCallToken) : DiagnosticAdmission
    data object Busy : DiagnosticAdmission
    data object Detached : DiagnosticAdmission
    data object NotReady : DiagnosticAdmission
}
sealed interface DiagnosticPresentation {
    data object Idle : DiagnosticPresentation
    data class Running(val token: DiagnosticCallToken) : DiagnosticPresentation
    data class Complete(val token: DiagnosticCallToken, val report: UiDiagnosticReport) : DiagnosticPresentation
    data class Failed(val token: DiagnosticCallToken, val code: DiagnosticError) : DiagnosticPresentation
    data class LocallyTimedOut(val token: DiagnosticCallToken) : DiagnosticPresentation
}
data class DiagnosticSnapshot(
    val availability: DiagnosticAvailability = DiagnosticAvailability.NotChecked,
    val nativeBusy: Boolean = false,
    val presentation: DiagnosticPresentation = DiagnosticPresentation.Idle,
)
interface RustDiagnosticCoordinator {
    fun attach(listener: (DiagnosticSnapshot) -> Unit): DiagnosticLease
    fun startHandshake(lease: DiagnosticLease): DiagnosticAdmission
    fun startValidation(lease: DiagnosticLease, variant: UiDiagnosticVariant): DiagnosticAdmission
    fun expire(lease: DiagnosticLease, token: DiagnosticCallToken)
    fun detach(lease: DiagnosticLease)
}
