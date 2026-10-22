package com.mightyoung.muyon.product.ui.documents

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor

/** Short lived native renderer: exactly one page and descriptor per request, never a document cache. */
object NativeDocumentPreview {
    data class PdfPage(val bitmap: Bitmap, val pageCount: Int)
    fun pdf(descriptor: ParcelFileDescriptor, pageIndex: Int): PdfPage = descriptor.use { fd ->
        PdfRenderer(fd).use { renderer ->
            require(pageIndex in 0 until renderer.pageCount) { "PDF page out of range" }
            renderer.openPage(pageIndex).use { page ->
                require(page.width > 0 && page.height > 0) { "Invalid PDF page geometry" }
                // 4 MiB ARGB budget. Extreme aspect ratios cannot overflow integer arithmetic.
                val ratio = page.height.toDouble() / page.width
                val width = minOf(1280.0, kotlin.math.sqrt(1_048_576.0 / ratio)).toInt().coerceAtLeast(1)
                val height = (width * ratio).toInt().coerceIn(1, 1_048_576 / width)
                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                try {
                    bitmap.eraseColor(Color.WHITE)
                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    PdfPage(bitmap, renderer.pageCount)
                } catch (failure: Throwable) { bitmap.recycle(); throw failure }
            }
        }
    }
}
