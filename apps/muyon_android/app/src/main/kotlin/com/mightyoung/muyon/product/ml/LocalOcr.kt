package com.mightyoung.muyon.product.ml

import ai.onnxruntime.OnnxJavaType
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import ai.onnxruntime.TensorInfo
import android.graphics.Bitmap
import android.graphics.PointF
import java.io.Closeable
import java.io.File
import java.nio.FloatBuffer
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.roundToInt

data class OcrLine(val text: String, val confidence: Float, val points: List<PointF>)

/** Offline PP-OCRv5 CPU inference. Call on a background thread; close waits for active inference. */
class LocalOcr(det: File, rec: File, dictionary: List<String>) : Closeable {
    private val dictionary = dictionary.toList()
    private val environment = OrtEnvironment.getEnvironment()
    private val detector: OrtSession
    private val recognizer: OrtSession
    private var closed = false

    init {
        require(this.dictionary.size == 18385 && this.dictionary.first() == "" && this.dictionary.last() == " ") { "OCR dictionary must match 18385 classes" }
        require(det.isFile && rec.isFile) { "OCR models missing" }
        OrtSession.SessionOptions().use { options ->
            options.setIntraOpNumThreads(2)
            detector = environment.createSession(det.absolutePath, options)
            try {
                recognizer = environment.createSession(rec.absolutePath, options)
            } catch (failure: Throwable) { detector.close(); throw failure }
        }
        try {
            for (session in listOf(detector, recognizer)) {
                require(session.inputNames == setOf("x") && session.outputNames.contains("fetch_name_0")) { "OCR model interface mismatch" }
                val input = session.inputInfo.getValue("x").info as? TensorInfo
                require(input?.type == OnnxJavaType.FLOAT && input.shape.size == 4) { "OCR model input mismatch" }
            }
        } catch (failure: Throwable) { recognizer.close(); detector.close(); throw failure }
    }

    @Synchronized
    fun recognize(bitmap: Bitmap, checkCancelled: () -> Unit = {}): List<OcrLine> {
        check(!closed) { "OCR service closed" }
        require(!bitmap.isRecycled && bitmap.width > 0 && bitmap.height > 0 && bitmap.width.toLong() * bitmap.height <= 20_000_000) { "OCR image exceeds 20 million pixels or is invalid" }
        checkCancelled()
        val ratio = 960.0 / max(bitmap.width, bitmap.height)
        val width = max(32, (bitmap.width * ratio / 32).roundToInt() * 32)
        val height = max(32, (bitmap.height * ratio / 32).roundToInt() * 32)
        val resized = Bitmap.createScaledBitmap(bitmap, width, height, true)
        val detected = try {
            infer(detector, normalizedBgr(resized, true, checkCancelled = checkCancelled), longArrayOf(1, 3, height.toLong(), width.toLong()), checkCancelled)
        } finally { if (resized !== bitmap) resized.recycle() }
        require(detected.shape.size == 4 && detected.shape[0] == 1L && detected.shape[1] == 1L && detected.shape[2] in 1..4_000_000 && detected.shape[3] in 1..4_000_000) { "OCR detector shape mismatch" }
        val boxes = OcrGeometry.detectBoxes(detected.values, detected.shape[3].toInt(), detected.shape[2].toInt(), bitmap.width, bitmap.height, checkCancelled)
        val lines = mutableListOf<OcrLine>()
        for (box in boxes) {
            checkCancelled()
            val crop = OcrGeometry.perspectiveCrop(bitmap, box.points)
            try {
                val recWidth = ceil(48.0 * crop.width / crop.height).toInt().coerceIn(1, 1920)
                val padded = max(320, recWidth)
                val input = Bitmap.createScaledBitmap(crop, recWidth, 48, true)
                val result = try {
                    infer(recognizer, normalizedBgr(input, false, padded, checkCancelled), longArrayOf(1, 3, 48, padded.toLong()), checkCancelled)
                } finally { if (input !== crop) input.recycle() }
                require(result.shape.size == 3 && result.shape[0] == 1L && result.shape[1] in 1..10000 && result.shape[2] == dictionary.size.toLong()) { "OCR recognizer shape mismatch" }
                val decoded = ctcDecode(result.values, result.shape[1].toInt(), dictionary.size, dictionary, checkCancelled)
                if (decoded.first.isNotEmpty()) lines.add(OcrLine(decoded.first, decoded.second, box.points.map { PointF(it.x, it.y) }))
            } finally { crop.recycle() }
        }
        checkCancelled()
        return lines.toList()
    }

    private data class Output(val shape: LongArray, val values: FloatArray)
    private fun infer(session: OrtSession, input: FloatArray, shape: LongArray, checkCancelled: () -> Unit): Output {
        checkCancelled()
        OnnxTensor.createTensor(environment, FloatBuffer.wrap(input), shape).use { tensor ->
            session.run(mapOf("x" to tensor)).use { outputs ->
                checkCancelled()
                val output = outputs.get("fetch_name_0").orElseThrow { IllegalStateException("OCR output missing") } as? OnnxTensor
                    ?: error("OCR output must be a tensor")
                val info = output.info
                require(info.type == OnnxJavaType.FLOAT && info.shape.isNotEmpty() && info.shape.all { it > 0 }) { "OCR output type mismatch" }
                val buffer = output.floatBuffer ?: error("OCR output must contain float values")
                val values = FloatArray(buffer.remaining())
                buffer.get(values)
                var count = 1L
                for (dimension in info.shape) { require(dimension <= Int.MAX_VALUE && count <= Int.MAX_VALUE / dimension) { "OCR output too large" }; count *= dimension }
                require(count == values.size.toLong()) { "OCR output shape mismatch" }
                return Output(info.shape.copyOf(), values)
            }
        }
    }

    @Synchronized override fun close() {
        if (closed) return
        closed = true
        try { detector.close() } finally { recognizer.close() }
        // OrtEnvironment is process shared and belongs to ONNX Runtime.
    }

    companion object {
        internal fun normalizedBgr(bitmap: Bitmap, detection: Boolean, paddedWidth: Int = bitmap.width, checkCancelled: () -> Unit = {}): FloatArray {
            require(paddedWidth >= bitmap.width)
            val plane = paddedWidth * bitmap.height
            val out = FloatArray(plane * 3)
            val pixels = IntArray(bitmap.width)
            val mean = doubleArrayOf(.485, .456, .406)
            val std = doubleArrayOf(.229, .224, .225)
            for (y in 0 until bitmap.height) {
                checkCancelled()
                bitmap.getPixels(pixels, 0, bitmap.width, 0, y, bitmap.width, 1)
                for (x in pixels.indices) {
                    val color = pixels[x]
                    for (c in 0..2) {
                        val value = (color ushr (c * 8)) and 255
                        out[c * plane + y * paddedWidth + x] = if (detection) ((value / 255.0 - mean[c]) / std[c]).toFloat() else (value / 127.5 - 1).toFloat()
                    }
                }
            }
            return out
        }

        internal fun ctcDecode(probabilities: FloatArray, steps: Int, classes: Int, dictionary: List<String>, checkCancelled: () -> Unit = {}): Pair<String, Float> {
            require(steps > 0 && classes > 0 && classes == dictionary.size && probabilities.size.toLong() == steps.toLong() * classes) { "OCR class shape mismatch" }
            var previous = -1
            var score = 0.0
            var count = 0
            val text = StringBuilder()
            for (t in 0 until steps) {
                checkCancelled()
                var index = 0
                var best = Float.NEGATIVE_INFINITY
                for (c in 0 until classes) {
                    val value = probabilities[t * classes + c]
                    require(value.isFinite() && value in 0f..1f) { "Invalid OCR probabilities" }
                    if (value > best) { best = value; index = c }
                }
                if (index != 0 && index != previous) { text.append(dictionary[index]); score += best; count++ }
                previous = index
            }
            return text.toString() to if (count == 0) 0f else (score / count).toFloat()
        }
    }
}
