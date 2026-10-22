package com.mightyoung.muyon.product.documents.host

import com.mightyoung.muyon.productbridge.DocumentAccessRequest
import com.mightyoung.muyon.productbridge.DocumentPresentationChunkResult
import com.mightyoung.muyon.productbridge.DocumentPresentationOpenRequest
import com.mightyoung.muyon.productbridge.DocumentPresentationUseRequest
import com.mightyoung.muyon.productbridge.DocumentReaderScope
import com.mightyoung.muyon.productbridge.ProductCore
import org.json.JSONObject

/** Actual generated01e1 presentation transport, NOT policy/renderer/IPC.
 * No public JSON route, grant issuer, fallback, IDs, revisions or visibility inputs.
 * The Service supplies its REAL owner; every native invocation needs its current
 * serialized batch permit. Raw projections/bytes are NOT publication admission.
 * This adapter does not restore permission from a wire grant reference: native
 * still validates the exact existing persisted access on every use.
 */
internal class NativeReaderPresentationPort internal constructor(
    private val principal: LocalWorkspaceReaderPrincipal,
    private val domain: ReaderDocumentBatchDomain,
    val administrativeOwner: ReaderAdministrativeOwner,
    private val core: () -> ProductCore,
) {
    private fun scope() = DocumentReaderScope(serviceSession = principal.serviceSession,
        generation = principal.scopeGeneration.toString(), project = principal.projectId)
    private fun business(permit: ReaderNativeBatchPermit) { permit.requireBusiness(principal, domain) }
    private fun use(presentationId: String, originalFrameGeneration: String) = DocumentPresentationUseRequest(
        scope = scope(), presentationId = presentationId, frameGeneration = originalFrameGeneration)

    /** Only genuine current selection admission may invoke this, BEFORE lookup.
     * Keep returned native token; Host sequence is never a replacement token. */
    fun beginSelection(permit: ReaderNativeBatchPermit): String {
        business(permit)
        return core().documentPresentationBeginSelection(scope())
    }
    /** Grant reference must come from the future trusted current policy resolver.
     * Neither a source nor permit asserts permission. There is no production
     * resolver attached yet; no model/card/UI JSON can call this private port. */
    fun open(permit: ReaderNativeBatchPermit, source: ExactReaderSource, nativeSelectionId: String,
        existingGrantId: String, existingGrantGeneration: String): String {
        business(permit)
        permit.requireSource(source)
        require(source.workspaceId == principal.workspaceId && source.projectId == principal.projectId)
        val reference = JSONObject().put("scope", JSONObject().put("workspace_id", source.workspaceId)
            .put("project_id", source.projectId)).put("document_id", source.documentId)
            .put("revision", source.revision).put("format", source.format)
        return core().documentPresentationOpen(DocumentPresentationOpenRequest(
            access = DocumentAccessRequest(scope = scope(), documentRefJson = reference.toString(),
                grantId = existingGrantId, grantGeneration = existingGrantGeneration), selectionId = nativeSelectionId))
    }
    fun chunk(permit: ReaderNativeBatchPermit, presentationId: String, originalFrameGeneration: String,
        maxBytes: UInt): DocumentPresentationChunkResult {
        business(permit)
        require(maxBytes in 1u..65_536u)
        return core().documentPresentationChunk(use(presentationId, originalFrameGeneration), maxBytes)
    }
    /** Check never changes grant, selection or frame generation. */
    fun check(permit: ReaderNativeBatchPermit, presentationId: String, originalFrameGeneration: String): String {
        business(permit)
        return core().documentPresentationCheck(use(presentationId, originalFrameGeneration))
    }
    /** Explicit actual native advance only; no local next-generation arithmetic. */
    fun advanceFrame(permit: ReaderNativeBatchPermit, presentationId: String, originalFrameGeneration: String): String {
        business(permit)
        return core().documentPresentationAdvanceFrame(use(presentationId, originalFrameGeneration))
    }
    fun closeExact(permit: ReaderNativeBatchPermit, presentationId: String, originalFrameGeneration: String) {
        business(permit)
        core().documentPresentationClose(use(presentationId, originalFrameGeneration))
    }
    /** Exact recorded ticket cleanup after UI/scope permission died. Old A
     * cannot substitute a current frame: native validates ORIGINAL scope/id/gen. */
    fun closeAdministrative(permit: ReaderAdministrativePermit, originalPresentationId: String, originalFrameGeneration: String) {
        permit.requireOwner(administrativeOwner, domain)
        core().documentPresentationClose(use(originalPresentationId, originalFrameGeneration))
    }
    /** ONLY actual Binder/session release, never selection/page cleanup: it closes
     * all original client's readers. Do not use it for old A inside live client B. */
    fun releaseDisconnectedClient(permit: ReaderAdministrativePermit) {
        permit.requireDisconnected(administrativeOwner, domain)
        core().documentReadReleaseOwner(administrativeOwner.serviceSession)
    }
    fun takeAdministrativeInvalidations(permit: ReaderAdministrativePermit): String {
        permit.requireOwner(administrativeOwner, domain)
        return core().documentPresentationTakeInvalidations()
    }
    /** Drain must run after success AND error, even if scope died mid-operation.
     * It is administration for THIS native owner, never a client listing endpoint.
     * Caller must decode/route conservatively BEFORE releasing same batch lock. */
    fun takeInvalidations(permit: ReaderNativeBatchPermit): String {
        permit.requireAdministrative(domain)
        return core().documentPresentationTakeInvalidations()
    }
}
