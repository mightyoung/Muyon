package com.mightyoung.muyon.product.ml

import org.junit.Assert.*
import org.junit.Test
import java.io.Closeable
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class ModelResourceCacheTest {
    private class Resource : Closeable {
        var closes = 0
        override fun close() { closes++ }
    }

    @Test fun sameIdentityReusesAndScopeOrModelChangeClosesOriginalExactlyOnce() {
        val cache = ModelResourceCache<Resource>()
        val opened = mutableListOf<Resource>()
        fun load(key: String) = cache.use(key, { Resource().also(opened::add) }) { it }
        val original = load("projectA:model1:inode1")
        assertSame(original, load("projectA:model1:inode1"))
        val changed = load("projectA:model1:inode2")
        assertNotSame(original, changed)
        assertEquals(1, original.closes)
        val anotherScope = load("projectB:model1:inode2")
        assertEquals(1, changed.closes)
        cache.close(); cache.close()
        assertEquals(1, anotherScope.closes)
        assertEquals(3, opened.size)
        assertThrows(IllegalStateException::class.java) { load("projectB:model1:inode2") }
    }

    @Test fun failedOpenAndInferenceAreNeverReusedAndCloseWaitsForActiveUse() {
        val cache = ModelResourceCache<Resource>()
        assertThrows(IllegalArgumentException::class.java) {
            cache.use("model", { throw IllegalArgumentException("open failed") }) { }
        }
        val failed = Resource()
        assertThrows(IllegalArgumentException::class.java) {
            cache.use("model", { failed }) { throw IllegalArgumentException("inference failed") }
        }
        assertEquals(1, failed.closes)
        val active = Resource()
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val finished = CountDownLatch(1)
        val using = Thread {
            cache.use("model", { active }) { entered.countDown(); check(release.await(5, TimeUnit.SECONDS)) }
        }
        using.start()
        assertTrue(entered.await(5, TimeUnit.SECONDS))
        val closing = Thread { cache.close(); finished.countDown() }
        closing.start()
        assertFalse(finished.await(100, TimeUnit.MILLISECONDS))
        assertEquals(0, active.closes)
        release.countDown()
        assertTrue(finished.await(5, TimeUnit.SECONDS))
        using.join(5000); closing.join(5000)
        assertEquals(1, active.closes)
    }
}
