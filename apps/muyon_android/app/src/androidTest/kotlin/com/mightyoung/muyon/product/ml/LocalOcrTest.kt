package com.mightyoung.muyon.product.ml

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.PointF
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CancellationException
import java.io.File
import java.util.UUID
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

class LocalOcrTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private fun models(): LocalOcr {
        val installed = LocalModels(instrumentation.targetContext).install()
        val json = JSONArray(installed.getValue("dictionary.json").readText())
        return LocalOcr(installed.getValue("det.onnx"), installed.getValue("rec.onnx"), List(json.length()) { json.getString(it) })
    }

    @Test fun ctcKeepsBlankSeparatedRepeatsAndRejectsMalformedProbabilities() {
        val dictionary = listOf("", "中", "A")
        val values = floatArrayOf(.1f, .8f, .1f, .1f, .7f, .2f, .9f, .05f, .05f, .1f, .85f, .05f, .1f, .1f, .8f)
        val decoded = LocalOcr.ctcDecode(values, 5, 3, dictionary)
        assertEquals("中中A", decoded.first)
        assertEquals((.8f + .85f + .8f) / 3, decoded.second, .00001f)
        assertThrows(IllegalArgumentException::class.java) { LocalOcr.ctcDecode(values, 4, 3, dictionary) }
        for (bad in listOf(Float.NaN, Float.POSITIVE_INFINITY, -1f, 1.1f)) {
            assertThrows(IllegalArgumentException::class.java) { LocalOcr.ctcDecode(floatArrayOf(bad, .9f, .1f), 1, 3, dictionary) }
        }
        assertEquals("", LocalOcr.ctcDecode(floatArrayOf(1f, 0f, 0f), 1, 3, dictionary).first)
    }

    @Test fun bgrPlaneOrderAndRecognizerPaddingMatchPinnedPreprocessing() {
        val bitmap = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
        try {
            bitmap.eraseColor(Color.rgb(255, 128, 0))
            val rec = LocalOcr.normalizedBgr(bitmap, false, 2)
            assertArrayEquals(floatArrayOf(-1f, 0f, (128 / 127.5 - 1).toFloat(), 0f, 1f, 0f), rec, .00001f)
            val det = LocalOcr.normalizedBgr(bitmap, true)
            assertArrayEquals(floatArrayOf((-.485 / .229).toFloat(), ((128 / 255.0 - .456) / .224).toFloat(), ((1 - .406) / .225).toFloat()), det, .00001f)
        } finally { bitmap.recycle() }
    }

    @Test fun rotatedContourRetainsAngleAndWeakInvalidMapsCannotBecomeTextBoxes() {
        val width = 120
        val height = 100
        val angle = .35
        val map = FloatArray(width * height) { index ->
            val x = index % width - 60.0
            val y = index / width - 50.0
            if (abs(x * cos(angle) + y * sin(angle)) <= 30 && abs(-x * sin(angle) + y * cos(angle)) <= 6) .95f else 0f
        }
        val boxes = OcrGeometry.detectBoxes(map, width, height, width, height)
        assertEquals(1, boxes.size)
        val p = boxes.single().points
        assertTrue("Rotated text must not be replaced with an axis aligned rectangle", abs(p[1].y - p[0].y) > 8)
        assertTrue(boxes.single().score > .8f)
        assertTrue(OcrGeometry.detectBoxes(FloatArray(width * height) { if (map[it] > 0) .4f else 0f }, width, height, width, height).isEmpty())
        assertThrows(IllegalArgumentException::class.java) { OcrGeometry.detectBoxes(floatArrayOf(Float.NaN), 1, 1, 1, 1) }
        assertThrows(IllegalArgumentException::class.java) { OcrGeometry.detectBoxes(floatArrayOf(1f), 2, 2, 2, 2) }
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        try {
            val cropped = OcrGeometry.perspectiveCrop(bitmap, p)
            try { assertTrue(cropped.width > cropped.height * 2) } finally { cropped.recycle() }
            assertThrows(IllegalArgumentException::class.java) { OcrGeometry.perspectiveCrop(bitmap, List(4) { PointF(1f, 1f) }) }
        } finally { bitmap.recycle() }
    }

    @Test fun readingOrderUsesFixedRowAnchorsAcrossThresholdChainsAndMultipleRows() {
        fun box(x: Float, y: Float) = OcrGeometry.Box(listOf(PointF(x, y), PointF(x + 4, y), PointF(x + 4, y + 3), PointF(x, y + 3)), 1f)
        val a = box(20f, 0f)
        val b = box(10f, 6f)
        val c = box(0f, 12f)
        for (input in listOf(listOf(a, b, c), listOf(a, c, b), listOf(b, a, c), listOf(b, c, a), listOf(c, a, b), listOf(c, b, a))) {
            assertEquals(listOf(b, a, c), OcrGeometry.readingOrder(input))
        }
        val row1 = listOf(box(10f, 6f), box(20f, 0f), box(30f, 9f))
        val row2 = listOf(box(5f, 18f), box(25f, 10f))
        val row3 = listOf(box(0f, 29f), box(30f, 20f))
        val row4 = listOf(box(2f, 30f))
        val expected = row1 + row2 + row3 + row4
        assertEquals(expected, OcrGeometry.readingOrder(expected.asReversed()))
        assertEquals(expected, OcrGeometry.readingOrder(listOf(row3[1], row1[2], row2[0], row4[0], row1[1], row3[0], row2[1], row1[0])))
        assertTrue(OcrGeometry.readingOrder(emptyList()).isEmpty())
    }

    @Test fun realModelsRecognizeChineseAmountAndRotatedFixture() {
        models().use { ocr ->
            for (name in listOf("ml/ocr.png", "ml/ocr.rotated.png")) {
                val bitmap = instrumentation.context.assets.open(name).use { BitmapFactory.decodeStream(it) }
                    ?: error("Fixture image decoding failed")
                try {
                    val lines = ocr.recognize(bitmap)
                    val text = lines.joinToString("\n") { it.text }
                    assertTrue("$name produced no OCR lines", lines.isNotEmpty())
                    assertTrue("$name lost Chinese material text: $text", text.contains("材料"))
                    assertTrue("$name lost amount 123.45: $text", text.contains("123.45"))
                    assertTrue("$name lost amount 678.90: $text", text.contains("678.90"))
                    for (line in lines) {
                        assertTrue(line.confidence.isFinite() && line.confidence in 0f..1f)
                        assertEquals(4, line.points.size)
                        assertTrue(line.points.all { it.x in 0f..(bitmap.width - 1f) && it.y in 0f..(bitmap.height - 1f) })
                    }
                } finally { bitmap.recycle() }
            }
        }
    }

    @Test fun realModelsRecognizeScannedPdfRenderedByAndroid() {
        val file = File(instrumentation.targetContext.cacheDir, "ocr-fixture-${UUID.randomUUID()}.pdf")
        try {
            instrumentation.context.assets.open("ml/ocr.pdf").use { input -> file.outputStream().use { output -> input.copyTo(output) } }
            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                PdfRenderer(descriptor).use { pdf ->
                    assertEquals(1, pdf.pageCount)
                    pdf.openPage(0).use { page ->
                        // Actual Android PDF rasterization at 144 dpi, not the source PNG.
                        val bitmap = Bitmap.createBitmap(page.width * 2, page.height * 2, Bitmap.Config.ARGB_8888)
                        try {
                            bitmap.eraseColor(Color.WHITE)
                            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                            models().use { ocr ->
                                val lines = ocr.recognize(bitmap)
                                val text = lines.joinToString("\n") { it.text }
                                assertTrue("PDF lost Chinese material text: $text", text.contains("材料"))
                                assertTrue("PDF lost first amount: $text", text.contains("123.45"))
                                assertTrue("PDF lost second amount: $text", text.contains("678.90"))
                                assertTrue(lines.all { it.confidence.isFinite() && it.confidence > 0f && it.points.size == 4 })
                            }
                        } finally { bitmap.recycle() }
                    }
                }
            }
        } finally { file.delete() }
    }

    @Test fun realModelsReturnNoTextForBlankAndCancellationDoesNotPoisonSession() {
        val bitmap = Bitmap.createBitmap(640, 480, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.WHITE) }
        val ocr = models()
        try {
            assertThrows(CancellationException::class.java) { ocr.recognize(bitmap) { throw CancellationException("fixture cancellation") } }
            assertTrue(ocr.recognize(bitmap).isEmpty())
            ocr.close()
            assertThrows(IllegalStateException::class.java) { ocr.recognize(bitmap) }
        } finally { ocr.close(); bitmap.recycle() }
    }
}
