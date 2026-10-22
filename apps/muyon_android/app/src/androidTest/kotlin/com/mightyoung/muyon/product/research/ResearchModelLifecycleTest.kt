package com.mightyoung.muyon.product.research

import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.product.agentipc.ProductClient
import org.junit.Assert.*
import org.junit.Test
import java.io.Closeable
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class ResearchModelLifecycleTest {
    @Test fun releaseAndHostShutdownDrainModelsAfterWorkWithoutBlockingMainThread() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        lateinit var client: ProductClient
        instrumentation.runOnMainSync { client = ProductClient(instrumentation.targetContext) {} }
        val host = ResearchFileHost(instrumentation.targetContext, client)
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val closed = CountDownLatch(2)
        val closeCount = AtomicInteger()
        val first = Closeable { closeCount.incrementAndGet(); closed.countDown() }
        val second = Closeable { closeCount.incrementAndGet(); closed.countDown() }
        try {
            host.ownModel(first); host.ownModel(second)
            host.run({ entered.countDown(); check(release.await(5, TimeUnit.SECONDS)) }) {}
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            // Returning from runOnMainSync before releasing the worker proves disposal does not
            // wait for a native operation on the UI thread.
            instrumentation.runOnMainSync {
                host.releaseModel(first)
                host.close()
                host.releaseModel(second) // Already covered by the host's queued drain.
            }
            assertEquals(0, closeCount.get())
            release.countDown()
            assertTrue(closed.await(5, TimeUnit.SECONDS))
            assertEquals(2, closeCount.get())
            host.close()
            // A new screen owns a new host; a closed helper can never acquire more models.
            assertThrows(IllegalStateException::class.java) { host.ownModel(Closeable {}) }
        } finally {
            release.countDown(); host.close()
            instrumentation.runOnMainSync { client.close() }
        }
    }
}
