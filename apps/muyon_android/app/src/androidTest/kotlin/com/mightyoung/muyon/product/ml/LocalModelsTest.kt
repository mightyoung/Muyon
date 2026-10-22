package com.mightyoung.muyon.product.ml

import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.concurrent.CancellationException

class LocalModelsTest {
    @Test fun corruptedInstalledDictionaryIsReplacedFromFrozenOfflineAsset() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val models = LocalModels(context)
        val original = models.install().getValue("dictionary.json").readBytes()
        val dictionary = models.install().getValue("dictionary.json")
        dictionary.writeText("corrupt")
        try {
            val repaired = models.install().getValue("dictionary.json")
            assertArrayEquals(original, repaired.readBytes())
            assertFalse(File(repaired.parentFile, "dictionary.json.part").exists())
        } finally { dictionary.writeBytes(original) }
    }

    @Test fun cancelledInstallationDoesNotPublishPartialModels() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        try {
            LocalModels(context).install { throw CancellationException("test cancellation") }
            fail("cancelled installation returned success")
        } catch (_: CancellationException) { }
        val directory = File(context.noBackupFilesDir, "local-models-v1")
        assertTrue(directory.listFiles().orEmpty().none { it.name.endsWith(".part") })
    }
}
