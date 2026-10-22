package com.mightyoung.muyon.product.ml

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PointF
import org.junit.Assert.*
import org.junit.Test
import kotlin.math.*

class OcrOrientationRegressionTest {
    private fun corners(angle: Double, width: Float = 200f, height: Float = 24f): List<PointF> {
        val c = cos(angle); val s = sin(angle)
        return listOf(-width / 2 to -height / 2, width / 2 to -height / 2,
            width / 2 to height / 2, -width / 2 to height / 2).map { (x, y) ->
            PointF((160 + x * c - y * s).toFloat(), (120 + x * s + y * c).toFloat())
        }
    }
    private fun fixture(angle: Float, width: Float = 200f, height: Float = 24f): Bitmap {
        val bitmap = Bitmap.createBitmap(320, 240, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)
        canvas.rotate(angle, 160f, 120f)
        val paint = Paint()
        for ((color, bounds) in listOf(
            Color.RED to floatArrayOf(-width / 2, -height / 2, 0f, 0f),
            Color.GREEN to floatArrayOf(0f, -height / 2, width / 2, 0f),
            Color.BLUE to floatArrayOf(0f, 0f, width / 2, height / 2),
            Color.YELLOW to floatArrayOf(-width / 2, 0f, 0f, height / 2))) {
            paint.color = color
            canvas.drawRect(160 + bounds[0], 120 + bounds[1], 160 + bounds[2], 120 + bounds[3], paint)
        }
        return bitmap
    }
    private fun checkColors(bitmap: Bitmap, expected: List<Int>) {
        val locations = listOf(.25f to .25f, .75f to .25f, .75f to .75f, .25f to .75f)
        locations.forEachIndexed { index, (x, y) ->
            assertEquals("Corner $index at ${bitmap.width}x${bitmap.height}", expected[index],
                bitmap.getPixel((bitmap.width * x).toInt(), (bitmap.height * y).toInt()))
        }
    }
    private fun <T> permutations(values: List<T>): List<List<T>> =
        if (values.isEmpty()) listOf(emptyList()) else values.flatMapIndexed { index, first ->
            permutations(values.filterIndexed { other, _ -> other != index }).map { listOf(first) + it }
        }

    @Test fun positiveAndNegativeTiltPreserveAllFourCornerDirections() {
        for (degrees in listOf(-44f, -30f, -15f, 0f, 15f, 30f, 44f)) {
            val angle = Math.toRadians(degrees.toDouble())
            val source = fixture(degrees)
            try {
                for (points in permutations(corners(angle))) {
                    val crop = OcrGeometry.perspectiveCrop(source, points)
                    try {
                        assertTrue("$degrees must be a horizontal recognizer crop", crop.width > crop.height * 5)
                        checkColors(crop, listOf(Color.RED, Color.GREEN, Color.BLUE, Color.YELLOW))
                    } finally { crop.recycle() }
                }
            } finally { source.recycle() }
        }
    }

    @Test fun detectorCornerAxisFollowsLongTextForBothTiltSigns() {
        for (degrees in listOf(-30.0, -15.0, 15.0, 30.0)) {
            val angle = Math.toRadians(degrees)
            val width = 320; val height = 240
            val map = FloatArray(width * height) { index ->
                val x = index % width - 160.0; val y = index / width - 120.0
                if (abs(x * cos(angle) + y * sin(angle)) <= 90 && abs(-x * sin(angle) + y * cos(angle)) <= 10) .95f else 0f
            }
            val points = OcrGeometry.detectBoxes(map, width, height, width, height).single().points
            val dx = points[1].x - points[0].x; val dy = points[1].y - points[0].y
            assertTrue("$degrees reversed the left-to-right text axis", dx > 0)
            assertTrue("$degrees selected the short edge", hypot(dx, dy) > 150)
            assertEquals("$degrees reversed or transposed text", angle, atan2(dy.toDouble(), dx.toDouble()), .035)
        }
    }

    @Test fun tallCropNormalizesCounterclockwiseWithoutSwappingCornerIdentity() {
        for (degrees in listOf(-44f, -30f, -15f, 0f, 15f, 30f, 44f)) {
            val source = fixture(degrees, width = 24f, height = 160f)
            try {
                for (points in permutations(corners(Math.toRadians(degrees.toDouble()), width = 24f, height = 160f))) {
                    val crop = OcrGeometry.perspectiveCrop(source, points)
                    try {
                        assertTrue("$degrees must normalize the tall crop", crop.width > crop.height * 5)
                        checkColors(crop, listOf(Color.GREEN, Color.BLUE, Color.YELLOW, Color.RED))
                    } finally { crop.recycle() }
                }
            } finally { source.recycle() }
        }
    }
}
