package com.mightyoung.muyon.androidlab

import com.mightyoung.muyon.androidbridge.BridgeException
import com.mightyoung.muyon.androidbridge.DiagnosticCapability
import com.mightyoung.muyon.androidbridge.DiagnosticRequest
import com.mightyoung.muyon.androidbridge.DiagnosticVariant
import com.mightyoung.muyon.androidbridge.bridgeInfo as generatedBridgeInfo
import com.mightyoung.muyon.androidbridge.validateBundledContract as generatedValidateBundledContract

/** No eager generated access. Every method is called only by the shared worker. */
internal class GeneratedDiagnosticPort(
    private val expectedProtocol: UInt,
    private val expectedBuild: String,
) : DiagnosticNativePort {
    override fun bridgeInfo(): UiBridgeInfo = native {
        requirePackagedIdentity()
        val info = generatedBridgeInfo()
        if (info.protocol != expectedProtocol || info.buildIdentity != expectedBuild ||
            info.capability != DiagnosticCapability.BUNDLED_DECLARATION_VALIDATION) fail(DiagnosticError.PROTOCOL_MISMATCH)
        UiBridgeInfo(info.protocol, info.buildIdentity, UiDiagnosticCapability.BUNDLED_DECLARATION_VALIDATION,
            info.model, info.attachments, info.businessRead, info.write, info.execute)
    }
    override fun validateBundledContract(request: UiDiagnosticRequest): UiDiagnosticReport = native {
        requirePackagedIdentity()
        val report = generatedValidateBundledContract(DiagnosticRequest(request.protocol, request.requestId, when (request.variant) {
            UiDiagnosticVariant.EQUIPMENT -> DiagnosticVariant.EQUIPMENT
            UiDiagnosticVariant.RESEARCH -> DiagnosticVariant.RESEARCH
            UiDiagnosticVariant.INQUIRY -> DiagnosticVariant.INQUIRY
            UiDiagnosticVariant.SEEDED_EQUIPMENT -> DiagnosticVariant.SEEDED_EQUIPMENT
        }))
        val variant = when (report.variant) {
            DiagnosticVariant.EQUIPMENT -> UiDiagnosticVariant.EQUIPMENT
            DiagnosticVariant.RESEARCH -> UiDiagnosticVariant.RESEARCH
            DiagnosticVariant.INQUIRY -> UiDiagnosticVariant.INQUIRY
            DiagnosticVariant.SEEDED_EQUIPMENT -> UiDiagnosticVariant.SEEDED_EQUIPMENT
        }
        UiDiagnosticReport(report.protocol, report.requestId, report.buildIdentity, variant, report.namespace,
            report.catalogGeneration, report.dataCount, report.operationCount, report.relationCount, report.viewCount)
    }
    private fun requirePackagedIdentity() {
        if (expectedBuild.isEmpty()) fail(DiagnosticError.NATIVE_LOAD)
        if (expectedProtocol != 1u || !Regex("[0-9a-f]{40}").matches(expectedBuild)) fail(DiagnosticError.PROTOCOL_MISMATCH)
    }
    private fun fail(code: DiagnosticError): Nothing = throw DiagnosticNativeFailure(code)
    private inline fun <T> native(call: () -> T): T = try { call() }
        catch (error: DiagnosticNativeFailure) { throw error }
        catch (_: BridgeException.UnsupportedProtocol) { fail(DiagnosticError.UNSUPPORTED_PROTOCOL) }
        catch (_: BridgeException.InvalidRequestId) { fail(DiagnosticError.INVALID_REQUEST_ID) }
        catch (_: BridgeException.DeclarationRejected) { fail(DiagnosticError.DECLARATION_REJECTED) }
        catch (_: BridgeException.InternalFailure) { fail(DiagnosticError.INTERNAL_FAILURE) }
        catch (_: LinkageError) { fail(DiagnosticError.NATIVE_LOAD) }
        catch (_: Exception) { fail(DiagnosticError.NATIVE_FAILURE) }
}
