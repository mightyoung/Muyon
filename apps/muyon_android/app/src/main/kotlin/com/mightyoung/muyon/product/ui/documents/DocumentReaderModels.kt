package com.mightyoung.muyon.product.ui.documents

/** Projection of core DocumentRef, not an authority token. Revisions remain decimal strings. */
enum class DocumentFormat { PDF, DOCX, PPTX, XLSX }

internal fun validRevision(value: String): Boolean =
    value.matches(Regex("0|[1-9][0-9]{0,19}")) &&
        (value.length < 20 || value <= "18446744073709551615")

private fun validId(value: String): Boolean = value.matches(Regex("[A-Za-z0-9_.:-]{1,128}"))

data class ReaderDocumentRef(
    val workspaceId: String,
    val projectId: String?,
    val documentId: String,
    val revision: String,
    val format: DocumentFormat,
) {
    init {
        require(validId(workspaceId) && (projectId == null || validId(projectId)) && validId(documentId))
        require(validRevision(revision))
    }
}

data class ReaderPosition(val pageIndex: Int = 0, val zoom: Float = 1f) {
    /** UI page numbers are one based; no integer addition on untrusted input. */
    fun goTo(oneBasedPage: Int, pageCount: Int): ReaderPosition {
        require(pageCount > 0)
        return copy(pageIndex = oneBasedPage.coerceIn(1, pageCount) - 1)
    }
    fun zoom(value: Float): ReaderPosition = copy(zoom = if (value.isFinite()) value.coerceIn(1f, 3f) else 1f)
}

sealed class AnnotationContent {
    data class Comment(val text: String) : AnnotationContent()
    data class Highlight(val quote: String, val note: String?) : AnnotationContent()
    fun editableText(): String = when (this) { is Comment -> text; is Highlight -> note.orEmpty() }
}

/** Raw core anchor is kept intact; UI does not fabricate geometry or resolve text selection. */
data class SidecarAnnotation(
    val id: String,
    val revision: String,
    val document: ReaderDocumentRef,
    val anchorJson: String,
    val locationLabel: String,
    val authorLabel: String,
    val content: AnnotationContent,
    val stale: Boolean,
    val deleted: Boolean,
) {
    init { require(validId(id) && validRevision(revision)) }
    fun belongsTo(current: ReaderDocumentRef): Boolean =
        document.workspaceId == current.workspaceId && document.projectId == current.projectId &&
            document.documentId == current.documentId && document.format == current.format

    fun edit(current: ReaderDocumentRef, text: String): SidecarEdit? {
        if (deleted || stale || document != current || text.isBlank() || text.contains('\u0000') ||
            text.toByteArray(Charsets.UTF_8).size > 8192) return null
        val replacement = when (content) {
            is AnnotationContent.Comment -> AnnotationContent.Comment(text)
            is AnnotationContent.Highlight -> AnnotationContent.Highlight(content.quote, text)
        }
        return SidecarEdit(current, id, revision, anchorJson, replacement)
    }
}

data class SidecarEdit(
    val document: ReaderDocumentRef,
    val annotationId: String,
    val expectedAnnotationRevision: String,
    val anchorJson: String,
    val replacement: AnnotationContent,
)

sealed class SidecarSaveResult {
    /** Only returned after core persistence confirms commit. Refresh snapshot from host. */
    data object Saved : SidecarSaveResult()
    data class Rejected(val reason: String) : SidecarSaveResult()
    /** Host owns original intent/receipt lookup. UI must not blindly retry this edit. */
    data object Unknown : SidecarSaveResult()
}

/** UI submission state only; durable intent and receipt remain host-owned. */
enum class SidecarSubmission(val canSubmit: Boolean) {
    READY(true), SAVING(false), SAVED(false), REJECTED(true), UNKNOWN(false);
    fun finished(result: SidecarSaveResult): SidecarSubmission = when (result) {
        SidecarSaveResult.Saved -> SAVED
        is SidecarSaveResult.Rejected -> REJECTED
        SidecarSaveResult.Unknown -> UNKNOWN
    }
}

/** A page IO/render failure does not invalidate a still-authorized document or known page count. */
enum class ReaderReadStatus { LOADING, READY, PAGE_FAILED, ACCESS_LOST }

data class ReaderNavigation(val pageCount: Int, val status: ReaderReadStatus) {
    val canNavigate: Boolean get() = pageCount > 0 &&
        (status == ReaderReadStatus.READY || status == ReaderReadStatus.PAGE_FAILED)
    val canRetry: Boolean get() = status == ReaderReadStatus.PAGE_FAILED
}
