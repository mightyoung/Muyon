package com.mightyoung.muyon.product.ui.shell

import android.util.Log
import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.product.agentipc.ProductClient
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** External instrumentation-only read probe. Does not initialize, configure, send or infer. */
class RuntimeHealthSmokeProbe {
    @Test fun actualServiceHealthAndNoProviderConfiguration() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val ready = CountDownLatch(1)
        lateinit var client: ProductClient
        instrumentation.runOnMainSync {
            client = ProductClient(instrumentation.targetContext) { if (it) ready.countDown() }
            client.bind()
        }
        try {
            assertTrue(ready.await(30, TimeUnit.SECONDS))
            fun read(method: String): JSONObject {
                val done = CountDownLatch(1)
                var response: JSONObject? = null
                instrumentation.runOnMainSync { client.call(method) { response = it; done.countDown() } }
                assertTrue(done.await(40, TimeUnit.SECONDS))
                return requireNotNull(response)
            }
            val health = read("health")
            Log.i("MuyonColdSmoke", "HEALTH=" + health.toString())
            assertEquals("ok", health.getString("status"))
            val data = health.getJSONObject("data")
            assertFalse(data.getBoolean("synthetic"))
            assertEquals("3aae195c088f1b943be897efc7d874974066d79a:060e1e61224d6ca3c14452e8e34b929faff70a31bd2b03faa892863be2dd16ef", data.getString("build_id"))
            val available = read("agent_availability")
            Log.i("MuyonColdSmoke", "AVAILABILITY=" + available.toString())
            assertEquals("ok", available.getString("status"))
            assertFalse(available.getJSONObject("data").getBoolean("configured"))
        } finally { instrumentation.runOnMainSync { client.close() } }
    }
}
