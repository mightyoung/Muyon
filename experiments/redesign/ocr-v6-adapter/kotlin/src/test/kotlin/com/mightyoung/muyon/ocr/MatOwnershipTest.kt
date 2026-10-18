package com.mightyoung.muyon.ocr

import android.graphics.PointF
import com.paddle.ocr.model.OCRBox
import com.paddle.ocr.postprocess.QuadTextCrop
import com.paddle.ocr.preprocess.DetPreprocessor
import com.paddle.ocr.util.ImageUtils
import org.junit.Assert.*
import org.junit.BeforeClass
import org.junit.Test
import org.opencv.core.CvException
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.Scalar
import java.util.concurrent.CancellationException
import sun.misc.Unsafe

class MatOwnershipTest {
    companion object {
        @JvmStatic @BeforeClass fun loadNative() {
            nu.pattern.OpenCV.loadLocally()
            NativeMatTracker.install()
        }
    }

    // Android's compile-only PointF constructor is a stub; populate its public data fields.
    private fun point(x: Float, y: Float): PointF {
        val field = Unsafe::class.java.getDeclaredField("theUnsafe").also { it.isAccessible = true }
        return ((field.get(null) as Unsafe).allocateInstance(PointF::class.java) as PointF).also {
            it.x = x; it.y = y
        }
    }
    private fun box(vertical: Boolean = false) = OCRBox(
        if (vertical) listOf(point(0f, 0f), point(8f, 0f), point(8f, 24f), point(0f, 24f))
        else listOf(point(0f, 0f), point(24f, 0f), point(24f, 8f), point(0f, 8f))
    )

    private fun observe(cancelAt: String? = null, body: () -> Mat?) {
        NativeMatTracker.start(cancelAt)
        var returned: Mat? = null
        try {
            returned = body()
            val owned = NativeMatTracker.allocated.filter { it !== returned }
            assertTrue("test must observe actual temporary JNI Mats", owned.isNotEmpty())
            val leaked = owned.filter { it !in NativeMatTracker.released || !it.empty() }
            assertTrue("${leaked.size}/${owned.size} temporary Mats not released: ${leaked.map { it.javaClass.simpleName + ":" + it.rows() + "x" + it.cols() }}", leaked.isEmpty())
            println("Mat ownership: created=${NativeMatTracker.allocated.size}, temporaries=${owned.size}, released=${NativeMatTracker.released.size}, returned=${returned != null}, cancellation=$cancelAt")
            returned?.let {
                assertFalse("returned crop belongs to caller", it in NativeMatTracker.released)
                assertFalse(it.empty())
            }
        } finally {
            NativeMatTracker.stop()
            returned?.release()
            // Clean leaked resources after RED assertions, without relying on GC/finalizers.
            NativeMatTracker.allocated.filter { it !== returned }.forEach { it.release() }
        }
    }

    @Test fun cropReleasesAllTemporariesOnRealNativeException() {
        val src = Mat()
        try { observe {
            assertThrows(CvException::class.java) { QuadTextCrop.crop(src, box()) }
            null
        } } finally { src.release() }
    }

    @Test fun resizeReleasesDestinationOnRealNativeException() {
        val src = Mat()
        try { observe {
            assertThrows(CvException::class.java) { ImageUtils.resizeToMultipleOf32(src, 32, "max", 4000) }
            null
        } } finally { src.release() }
    }

    @Test fun detectionReleasesAllTemporariesOnRealChannelException() {
        val src = Mat(32, 32, CvType.CV_8UC1, Scalar(127.0))
        try { observe {
            assertThrows(IndexOutOfBoundsException::class.java) { DetPreprocessor.preprocess(src, 32, "max", 4000, "BGR") }
            assertFalse("caller source remains owned by caller", src.empty())
            null
        } } finally { src.release() }
    }

    @Test fun detectionReleasesRgbWhenResizeRejectsArguments() {
        val src = Mat(32, 32, CvType.CV_8UC3, Scalar(127.0, 127.0, 127.0))
        try { observe {
            assertThrows(IllegalArgumentException::class.java) { DetPreprocessor.preprocess(src, 32, "invalid", 4000, "RGB") }
            null
        } } finally { src.release() }
    }

    @Test fun detectionReleasesLargeIntermediatesBeforeTensorExtraction() {
        val src = Mat(32, 32, CvType.CV_8UC3, Scalar(127.0, 127.0, 127.0))
        try { observe {
            DetPreprocessor.preprocess(src, 32, "max", 4000, "RGB")
            assertEquals("only the three split channels stay live during tensor extraction", 3, NativeMatTracker.maximumLiveAtExtraction)
            assertEquals("RGB, resized and float Mats must already be released", 0, NativeMatTracker.nonChannelAtExtraction)
            null
        } } finally { src.release() }
    }

    @Test fun normalAndRepeatedCallsPreserveResultsAndCallerOwnership() {
        val src = Mat(32, 32, CvType.CV_8UC3, Scalar(127.0, 127.0, 127.0))
        try { repeat(20) {
            for (mode in listOf("BGR", "RGB")) observe {
                val result = DetPreprocessor.preprocess(src, 32, "max", 4000, mode)
                assertArrayEquals(longArrayOf(1, 3, 32, 32), result.shape)
                assertEquals(((127.0 / 255 - .485) / .229).toFloat(), result.tensorData[0], .00001f)
                assertFalse(src.empty())
                null
            }
            observe { QuadTextCrop.crop(src, box()).also { assertEquals(24, it.cols()); assertEquals(8, it.rows()) } }
            observe { QuadTextCrop.crop(src, box(true)).also { assertEquals(24, it.cols()); assertEquals(8, it.rows()) } }
        } } finally { src.release() }
    }

    @Test fun cancellationReleasesCropAndDetectionTemporaries() {
        val src = Mat(32, 32, CvType.CV_8UC3, Scalar(127.0, 127.0, 127.0))
        try {
            for (stage in listOf("warpPerspective", "rotate")) observe(stage) {
                assertThrows(CancellationException::class.java) { QuadTextCrop.crop(src, box(true)) }; null
            }
            for (stage in listOf("cvtColor", "convertTo", "split")) observe(stage) {
                assertThrows(CancellationException::class.java) { DetPreprocessor.preprocess(src, 32, "max", 4000, "RGB") }; null
            }
            assertFalse(src.empty())
        } finally { src.release() }
    }
}
