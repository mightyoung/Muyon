package com.mightyoung.muyon.study.adapters

import org.junit.Assert.*
import org.junit.Test
import java.nio.file.Files

class ArchivePathsTest {
    @Test fun acceptsExpectedModelAndRejectsEscapePaths() {
        val root = Files.createTempDirectory("model-test").toFile()
        try {
            assertEquals(root.resolve("am/final.mdl"), ArchivePaths.destination(root, "vosk-model-small-cn-0.22/am/final.mdl"))
            assertNull(ArchivePaths.destination(root, "vosk-model-small-cn-0.22/"))
            for(path in listOf("/absolute", "vosk-model-small-cn-0.22/../escape", "vosk-model-small-cn-0.22/am/../../escape", "other/am/final.mdl", "vosk-model-small-cn-0.22/evil\\path")) {
                try { ArchivePaths.destination(root, path); fail("Accepted $path") } catch (_: IllegalArgumentException) { }
            }
        } finally { root.deleteRecursively() }
    }
}
