package com.mightyoung.muyon.product.ui.documents

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

// Behavioral changes caught: stale annotation editing, lossy revisions, page overflow,
// fake Office previews, ZIP expansion, XML entities and unlabelled formula evaluation.
fun main() {
    val ref = ReaderDocumentRef("workspace", "project", "doc", "18446744073709551615", DocumentFormat.PDF)
    check(runCatching { ref.copy(revision = "18446744073709551616") }.isFailure)
    check(runCatching { ref.copy(revision = "01") }.isFailure)
    check(runCatching { ref.copy(documentId = "../secret") }.isFailure)
    check(ReaderPosition(0, 1f).goTo(1, 10).pageIndex == 0)
    check(ReaderPosition(0, 1f).goTo(Int.MAX_VALUE, 10).pageIndex == 9)
    check(ReaderPosition(0, 1f).goTo(-9, 10).pageIndex == 0)
    check(ReaderPosition(0, 1f).zoom(Float.NaN).zoom == 1f)
    check(ReaderPosition(0, 1f).zoom(100f).zoom == 3f)
    check(SidecarSubmission.READY.canSubmit)
    check(!SidecarSubmission.SAVING.canSubmit)
    check(!SidecarSubmission.UNKNOWN.canSubmit)
    check(!SidecarSubmission.SAVED.canSubmit)
    check(SidecarSubmission.REJECTED.canSubmit)
    check(SidecarSubmission.SAVING.finished(SidecarSaveResult.Unknown) == SidecarSubmission.UNKNOWN)
    check(SidecarSubmission.SAVING.finished(SidecarSaveResult.Saved) == SidecarSubmission.SAVED)
    val item = SidecarAnnotation("note", "2", ref, "{raw-anchor}", "第 1 页", "human:alice",
        AnnotationContent.Comment("before"), false, false)
    check(item.edit(ref, "after")?.expectedAnnotationRevision == "2")
    check(item.edit(ref.copy(projectId = "other"), "after") == null)
    check(!item.belongsTo(ref.copy(projectId = "other")))
    check(item.belongsTo(ref.copy(revision = "1")))
    check(item.edit(ref.copy(revision = "1"), "after") == null)
    check(item.copy(stale = true).edit(ref, "after") == null)
    check(item.copy(deleted = true).edit(ref, "after") == null)
    check(item.edit(ref, " ") == null)
    check(item.edit(ref, "é".repeat(4097)) == null)
    val highlight = item.copy(content = AnnotationContent.Highlight("original quote", "old"))
    check(highlight.edit(ref, "new")?.replacement == AnnotationContent.Highlight("original quote", "new"))
    fun zip(vararg parts: Pair<String, String>): ByteArray {
        val bytes = ByteArrayOutputStream()
        ZipOutputStream(bytes).use { z -> parts.forEach { (name, xml) ->
            z.putNextEntry(ZipEntry(name)); z.write(xml.toByteArray()); z.closeEntry()
        } }
        return bytes.toByteArray()
    }
    fun preview(format: DocumentFormat, vararg parts: Pair<String, String>) =
        OfficeTextPreview.read(ByteArrayInputStream(zip(*parts)), format)
    val doc = preview(DocumentFormat.DOCX, "word/document.xml" to
        "<w:document xmlns:w='urn:w'><w:p><w:r><w:t>Actual document</w:t></w:r></w:p></w:document>")
    check(doc.single().text.trim() == "Actual document")
    val slides = preview(DocumentFormat.PPTX,
        "ppt/slides/slide10.xml" to "<s><t>ten</t></s>", "ppt/slides/slide2.xml" to "<s><t>two</t></s>")
    check(slides.map { it.text.trim() } == listOf("two", "ten"))
    val sheet = preview(DocumentFormat.XLSX,
        "xl/sharedStrings.xml" to "<sst><si><t>Hello</t><t> world</t></si></sst>",
        "xl/worksheets/sheet1.xml" to "<sheet><row><c r='A1' t='s'><v>0</v></c><c r='B1'><f>1+1</f><v>2</v></c></row></sheet>")
    check(sheet.single().text.contains("A1: Hello world"))
    check(sheet.single().text.contains("B1: 2 [公式缓存值]"))
    check(runCatching { preview(DocumentFormat.DOCX, "word/document.xml" to
        "<!DOCTYPE a [<!ENTITY x SYSTEM 'file:///not-read'>]><a><t>&x;</t></a>") }.isFailure)
    check(runCatching { preview(DocumentFormat.DOCX, "word/document.xml" to "<a>broken") }.isFailure)
    check(runCatching { preview(DocumentFormat.DOCX, "other.xml" to "<a/>") }.isFailure)
    check(runCatching { preview(DocumentFormat.DOCX, "../word/document.xml" to "<a/>") }.isFailure)
    check(runCatching { OfficeTextPreview.read(ByteArrayInputStream(ByteArray(40)), DocumentFormat.DOCX) }.isFailure)
    check(runCatching { preview(DocumentFormat.DOCX, "word/document.xml" to "<t>${"a".repeat(210000)}</t>") }.isFailure)
    println("PASS: reader state, sidecar CAS and bounded native Office text checks")
}
