package com.mightyoung.muyon.product.ml

import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.concurrent.CancellationException
import android.os.Build

class ModelFileVerificationCacheTest {
    private fun fixture(block: (File) -> Unit) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val file = File.createTempFile("model-receipt-", ".bin", context.cacheDir)
        try { file.writeText("abcd"); block(file) } finally { file.delete() }
    }

    @Test fun verifiedIdentityReusesHashAndEveryIdentityChangeInvalidates() = fixture { file ->
        var stamp = "inode1:size4:mtime1:ctime1"
        var reads = 0
        val cache = ModelFileVerificationCache({ stamp }) { _, check -> check(); reads++; "digest" }
        assertTrue(cache.verify(file, 4, "digest"))
        assertTrue(cache.verify(file, 4, "digest"))
        assertEquals(1, reads)
        // A same-size write with restored mtime must still invalidate through ctime.
        stamp = "inode1:size4:mtime1:ctime2"
        assertTrue(cache.verify(file, 4, "digest"))
        assertEquals(2, reads)
        stamp = "inode2:size4:mtime1:ctime2"
        assertTrue(cache.verify(file, 4, "digest"))
        assertEquals(3, reads)
        assertFalse(cache.verify(file, 4, "new-model-digest"))
        assertEquals(4, reads)
        assertTrue(cache.verify(file, 4, "digest"))
        assertEquals(5, reads)
    }

    @Test fun failuresCancellationAndUnstableMetadataNeverBecomeReceipts() = fixture { file ->
        var reads = 0
        var stamp = "before"
        val cache = ModelFileVerificationCache({ stamp }) { _, _ -> reads++; stamp = "after$reads"; "digest" }
        assertFalse(cache.verify(file, 4, "digest"))
        assertFalse(cache.verify(file, 4, "digest"))
        assertEquals(2, reads)
        assertThrows(CancellationException::class.java) {
            cache.verify(file, 4, "digest") { throw CancellationException() }
        }
        assertEquals(2, reads)
        val imprecise = ModelFileVerificationCache({ null }) { _, _ -> reads++; "digest" }
        assertTrue(imprecise.verify(file, 4, "digest"))
        assertTrue(imprecise.verify(file, 4, "digest"))
        assertEquals(4, reads)
        file.delete()
        assertFalse(imprecise.verify(file, 4, "digest"))
        assertEquals(4, reads)
    }

    @Test fun actualFileMetadataInvalidatesSameSizeWriteEvenWithRestoredMtime() = fixture { file ->
        var reads = 0
        val cache = ModelFileVerificationCache(hash = { _, _ -> reads++; "digest" })
        assertTrue(cache.verify(file, 4, "digest"))
        assertTrue(cache.verify(file, 4, "digest"))
        assertEquals(if (Build.VERSION.SDK_INT >= 27) 1 else 2, reads)
        val mtime = file.lastModified()
        file.writeText("efgh")
        assertTrue(file.setLastModified(mtime))
        assertTrue(cache.verify(file, 4, "digest"))
        assertEquals(if (Build.VERSION.SDK_INT >= 27) 2 else 3, reads)
    }
}
