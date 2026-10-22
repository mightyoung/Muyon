package com.mightyoung.muyon.product.ml

import android.os.Debug
import android.os.SystemClock
import android.util.Log
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.math.abs
import kotlin.math.sqrt

/** Real packaged GGUF and production JNI; no fixture vectors or remote service. */
class LocalEmbeddingTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    private fun installedModel(): File {
        val start = SystemClock.elapsedRealtime()
        val model = LocalModels(context).install().getValue("embedding.gguf")
        assertEquals("fixed production model byte length", 309855456L, model.length())
        Log.i(TAG, "verified_asset_install_ms=${SystemClock.elapsedRealtime() - start}")
        return model
    }

    private fun assertVector(vector: FloatArray) {
        assertEquals("public projected dimension", 768, vector.size)
        assertTrue("every coordinate must be finite", vector.all { it.isFinite() })
        val norm = sqrt(vector.sumOf { it.toDouble() * it })
        assertEquals("nonzero unit vector", 1.0, norm, 1e-5)
    }

    private fun cosine(left: FloatArray, right: FloatArray): Double =
        left.indices.sumOf { left[it].toDouble() * right[it] }

    @Test fun realModelNormalizesDeterministicallyAndRanksEnglishAndChineseQueries() {
        val model = installedModel()
        val loadStart = SystemClock.elapsedRealtime()
        LocalEmbedding(model).use { embedding ->
            val loadMs = SystemClock.elapsedRealtime() - loadStart
            assertEquals(768, embedding.dimension)
            val relevant = "Neural networks are trained on labeled images with backpropagation and gradient descent to classify image content."
            val unrelated = "Roses grow best in sunny gardens. Water the roots and prune the flowers during the gardening season."
            val coldStart = SystemClock.elapsedRealtime()
            val relevantVector = embedding.embed(relevant)
            val firstInferenceMs = SystemClock.elapsedRealtime() - coldStart
            val warmStart = SystemClock.elapsedRealtime()
            val repeated = embedding.embed(relevant)
            val warmInferenceMs = SystemClock.elapsedRealtime() - warmStart
            assertVector(relevantVector)
            assertVector(repeated)
            val largestDifference = relevantVector.indices.maxOf { abs(relevantVector[it] - repeated[it]) }
            assertTrue("same text must survive sequence clearing deterministically: $largestDifference", largestDifference <= 1e-5f)
            val unrelatedVector = embedding.embed(unrelated)
            assertVector(unrelatedVector)

            for ((language, query) in listOf(
                "en" to "How are neural networks trained to classify images?",
                "zh" to "神经网络如何通过训练识别图像？"
            )) {
                val queryVector = embedding.embed(query, query = true)
                assertVector(queryVector)
                val relevantScore = cosine(queryVector, relevantVector)
                val unrelatedScore = cosine(queryVector, unrelatedVector)
                Log.i(TAG, "retrieval_language=$language relevant_cosine=$relevantScore unrelated_cosine=$unrelatedScore")
                assertTrue("$language query must rank image classification above gardening: $relevantScore <= $unrelatedScore",
                    relevantScore > unrelatedScore)
            }

            // Task prefixes must influence the real tokenizer/model output,
            // including after prior calls with the other task role.
            val sameTextAsQuery = embedding.embed(relevant, query = true)
            assertVector(sameTextAsQuery)
            val roleDistance = relevantVector.indices.sumOf {
                val difference = relevantVector[it].toDouble() - sameTextAsQuery[it]
                difference * difference
            }
            assertTrue("query/document roles must produce distinct task-conditioned vectors", roleDistance > 1e-8)
            Log.i(TAG, "model_load_ms=$loadMs first_inference_ms=$firstInferenceMs warm_inference_ms=$warmInferenceMs native_heap_bytes=${Debug.getNativeHeapAllocatedSize()} role_squared_distance=$roleDistance")
        }
    }

    @Test fun realTokenizerRejectsOverflowAndClosedEngineCanBeReopened() {
        val model = installedModel()
        val embedding = LocalEmbedding(model)
        try {
            // 1,400 ordinary words fit the character bound but exceed 512 real
            // tokens. This must fail in native tokenization, not char validation.
            val error = runCatching { embedding.embed("cat ".repeat(1400)) }.exceptionOrNull()
            assertTrue("overflow must be rejected by real model tokenization: $error",
                error is IllegalStateException && error.message.orEmpty().contains("512 tokens"))
            assertVector(embedding.embed("A valid short document after token overflow."))
            assertTrue(runCatching { embedding.embed(" ") }.exceptionOrNull() is IllegalArgumentException)
            assertTrue(runCatching { embedding.embed("invalid\u0000text") }.exceptionOrNull() is IllegalArgumentException)
            embedding.close()
            embedding.close()
            assertTrue("closed instance must reject inference", runCatching { embedding.embed("closed") }.exceptionOrNull() is IllegalStateException)
        } finally {
            embedding.close()
        }
        val reopenStart = SystemClock.elapsedRealtime()
        LocalEmbedding(model).use { reopened ->
            val reopenMs = SystemClock.elapsedRealtime() - reopenStart
            assertVector(reopened.embed("重新打开本地模型后仍然可以生成嵌入向量。", query = true))
            Log.i(TAG, "model_reopen_ms=$reopenMs native_heap_bytes=${Debug.getNativeHeapAllocatedSize()}")
        }
    }

    companion object { private const val TAG = "MuyonLocalEmbeddingTest" }
}
