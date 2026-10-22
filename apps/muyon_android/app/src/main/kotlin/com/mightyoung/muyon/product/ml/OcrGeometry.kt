package com.mightyoung.muyon.product.ml

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PointF
import kotlin.math.*

/** Port of the existing Paddle OCR contour, rotated rectangle and projective crop path. */
internal object OcrGeometry {
    data class Box(val points: List<PointF>, val score: Float)
    private fun cross(o: PointF, a: PointF, b: PointF): Double =
        (a.x - o.x).toDouble() * (b.y - o.y) - (a.y - o.y).toDouble() * (b.x - o.x)

    private fun hull(points: List<PointF>): List<PointF> {
        val sorted = points.sortedWith(compareBy<PointF> { it.x }.thenBy { it.y })
        fun half(input: List<PointF>): MutableList<PointF> {
            val out = mutableListOf<PointF>()
            for (point in input) {
                while (out.size >= 2 && cross(out[out.size - 2], out.last(), point) <= 0) out.removeAt(out.lastIndex)
                out.add(point)
            }
            return out
        }
        val lower = half(sorted)
        val upper = half(sorted.asReversed())
        return lower.dropLast(1) + upper.dropLast(1)
    }

    fun detectBoxes(
        probability: FloatArray, width: Int, height: Int, sourceWidth: Int, sourceHeight: Int,
        checkCancelled: () -> Unit = {},
    ): List<Box> {
        require(width > 0 && height > 0 && width.toLong() * height <= 4_000_000 &&
            probability.size.toLong() == width.toLong() * height && sourceWidth > 0 && sourceHeight > 0) { "Invalid detection map" }
        require(probability.all { it.isFinite() && it in 0f..1f }) { "Invalid detection probabilities" }
        val visited = BooleanArray(probability.size)
        val queue = IntArray(probability.size)
        val results = mutableListOf<Box>()
        var candidates = 0
        for (start in probability.indices) {
            if (start % 1024 == 0) checkCancelled()
            if (candidates >= 1000) break
            if (visited[start] || probability[start] <= .3f) continue
            var head = 0
            var tail = 1
            queue[0] = start
            visited[start] = true
            val boundary = mutableListOf<PointF>()
            while (head < tail) {
                if (head % 1024 == 0) checkCancelled()
                val at = queue[head++]
                val x = at % width
                val y = at / width
                var edge = false
                for (direction in 0..3) {
                    val nx = x + when (direction) { 0 -> -1; 1 -> 1; else -> 0 }
                    val ny = y + when (direction) { 2 -> -1; 3 -> 1; else -> 0 }
                    if (nx !in 0 until width || ny !in 0 until height) { edge = true; continue }
                    val ni = ny * width + nx
                    if (probability[ni] <= .3f) { edge = true; continue }
                    if (!visited[ni]) { visited[ni] = true; queue[tail++] = ni }
                }
                if (edge) boundary.add(PointF(x.toFloat(), y.toFloat()))
            }
            candidates++
            if (boundary.size < 4) continue
            val convex = hull(boundary)
            if (convex.size < 3) continue
            var bestArea = Double.POSITIVE_INFINITY
            var cosine = 1.0
            var sine = 0.0
            var minU = 0.0
            var maxU = 0.0
            var minV = 0.0
            var maxV = 0.0
            for (i in convex.indices) {
                checkCancelled()
                val a = convex[i]
                val b = convex[(i + 1) % convex.size]
                val angle = atan2((b.y - a.y).toDouble(), (b.x - a.x).toDouble())
                val c = cos(angle)
                val s = sin(angle)
                var loU = Double.POSITIVE_INFINITY
                var hiU = Double.NEGATIVE_INFINITY
                var loV = Double.POSITIVE_INFINITY
                var hiV = Double.NEGATIVE_INFINITY
                for (p in convex) {
                    val u = p.x * c + p.y * s
                    val v = -p.x * s + p.y * c
                    loU = min(loU, u); hiU = max(hiU, u)
                    loV = min(loV, v); hiV = max(hiV, v)
                }
                val area = (hiU - loU) * (hiV - loV)
                if (area < bestArea) {
                    bestArea = area; cosine = c; sine = s
                    minU = loU; maxU = hiU; minV = loV; maxV = hiV
                }
            }
            val w = maxU - minU
            val h = maxV - minV
            if (min(w, h) < 3) continue
            var sum = 0.0
            var count = 0
            val left = floor(boundary.minOf { it.x }.toDouble()).toInt()
            val right = ceil(boundary.maxOf { it.x }.toDouble()).toInt()
            val top = floor(boundary.minOf { it.y }.toDouble()).toInt()
            val bottom = ceil(boundary.maxOf { it.y }.toDouble()).toInt()
            for (y in top..bottom) {
                checkCancelled()
                for (x in left..right) {
                    val u = x * cosine + y * sine
                    val v = -x * sine + y * cosine
                    if (u >= minU && u <= maxU && v >= minV && v <= maxV) { sum += probability[y * width + x]; count++ }
                }
            }
            if (count == 0 || sum / count < .6) continue
            // Parallel offset of all four rectangle edges by area * 1.5 / perimeter.
            val offset = w * h * 1.5 / (2 * (w + h))
            minU -= offset; maxU += offset; minV -= offset; maxV += offset
            val points = listOf(minU to minV, maxU to minV, maxU to maxV, minU to maxV).map { (u, v) ->
                PointF(((u * cosine - v * sine) * sourceWidth / width).coerceIn(0.0, sourceWidth - 1.0).toFloat(),
                    ((u * sine + v * cosine) * sourceHeight / height).coerceIn(0.0, sourceHeight - 1.0).toFloat())
            }
            results.add(Box(orderCorners(points), (sum / count).toFloat()))
        }
        return readingOrder(results)
    }

    internal fun readingOrder(boxes: List<Box>): List<Box> {
        val vertical = boxes.sortedWith(compareBy<Box> { it.points.first().y }.thenBy { it.points.first().x })
        val ordered = ArrayList<Box>(boxes.size)
        var start = 0
        while (start < vertical.size) {
            // Anchor each row to its first top coordinate. Adjacent 6 px gaps must
            // not merge a chain spanning several rows or violate comparator ordering.
            val baseline = vertical[start].points.first().y
            var end = start + 1
            while (end < vertical.size && vertical[end].points.first().y - baseline < 10f) end++
            ordered.addAll(vertical.subList(start, end).sortedWith(compareBy<Box> { it.points.first().x }.thenBy { it.points.first().y }))
            start = end
        }
        return ordered
    }

    internal fun orderCorners(points: List<PointF>): List<PointF> {
        require(points.size == 4 && points.all { it.x.isFinite() && it.y.isFinite() }) { "Invalid OCR quadrilateral" }
        // Walk the convex boundary, then anchor its most horizontal rightward
        // edge. A fixed left/right split swaps axes on positively tilted tall
        // boxes; a fixed top/bottom split does the same on long text lines.
        // The hull winds clockwise in image coordinates, so its rightward
        // horizontal edge is the top edge and preserves all four identities.
        val boundary = hull(points)
        require(boundary.size == 4) { "Degenerate OCR quadrilateral" }
        val start = boundary.indices.filter { i -> boundary[(i + 1) % 4].x > boundary[i].x }
            .minByOrNull { i ->
                val a = boundary[i]; val b = boundary[(i + 1) % 4]
                abs((b.y - a.y).toDouble()) / hypot((b.x - a.x).toDouble(), (b.y - a.y).toDouble())
            } ?: throw IllegalArgumentException("Degenerate OCR quadrilateral")
        return List(4) { boundary[(start + it) % 4] }
    }

    fun perspectiveCrop(source: Bitmap, corners: List<PointF>): Bitmap {
        val box = orderCorners(corners)
        require(box.size == 4 && box.all { it.x.isFinite() && it.y.isFinite() }) { "Invalid OCR quadrilateral" }
        val twiceArea = box.indices.sumOf { i ->
            val a = box[i]; val b = box[(i + 1) % 4]
            a.x.toDouble() * b.y - b.x.toDouble() * a.y
        }
        require(abs(twiceArea) >= 1.0) { "Degenerate OCR quadrilateral" }
        fun distance(a: PointF, b: PointF) = hypot((a.x - b.x).toDouble(), (a.y - b.y).toDouble())
        val width = max(distance(box[0], box[1]), distance(box[2], box[3])).roundToInt().coerceIn(2, 4096)
        val height = max(distance(box[0], box[3]), distance(box[1], box[2])).roundToInt().coerceIn(2, 4096)
        val from = box.flatMap { listOf(it.x, it.y) }.toFloatArray()
        val to = floatArrayOf(0f, 0f, width - 1f, 0f, width - 1f, height - 1f, 0f, height - 1f)
        val matrix = Matrix()
        require(matrix.setPolyToPoly(from, 0, to, 0, 4)) { "Degenerate OCR quadrilateral" }
        val out = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        try {
            Canvas(out).drawBitmap(source, matrix, Paint(Paint.FILTER_BITMAP_FLAG))
            if (height.toDouble() / width < 1.5) return out
            // Paddle's vertical crop normalization is counterclockwise.
            val rotated = Bitmap.createBitmap(out, 0, 0, width, height, Matrix().apply { postRotate(-90f) }, true)
            out.recycle()
            return rotated
        } catch (failure: Throwable) { out.recycle(); throw failure }
    }
}
