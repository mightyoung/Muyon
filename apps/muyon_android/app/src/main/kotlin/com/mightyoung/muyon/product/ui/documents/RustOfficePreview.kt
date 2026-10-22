package com.mightyoung.muyon.product.ui.documents

import com.mightyoung.muyon.productbridge.officeExtractText
import java.io.ByteArrayOutputStream
import java.io.InputStream

/**
 * On-device Office text preview backed by the Rust engine (muyon-office via UniFFI).
 * Read-only: the engine enforces archive/part/XML limits again; this layer only
 * bounds the bytes it hands across the FFI boundary.
 */
object RustOfficePreview {
    private const val MAX_ARCHIVE = 16 * 1024 * 1024

    fun read(input: InputStream, format: DocumentFormat): List<OfficeSection> {
        require(format != DocumentFormat.PDF) { "PDF requires PdfRenderer" }
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val n = input.read(buffer)
            if (n < 0) break
            require(out.size() + n <= MAX_ARCHIVE) { "Office archive limit" }
            out.write(buffer, 0, n)
        }
        return officeExtractText(out.toByteArray()).map { OfficeSection(it.name, it.text) }
    }
}
