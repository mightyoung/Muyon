package com.mightyoung.muyon.product.ml

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class ResearchIndexTest {
    private lateinit var context: Context
    private lateinit var name: String
    private lateinit var index: ResearchIndex
    private val model = "test-model-sha256:preprocess-v1"
    private fun vector(axis: Int = 0) = FloatArray(768).apply { this[axis] = 1f }
    private fun source(project: String = "project-a", paper: String = "paper-a", revision: String = "1") =
        IndexSource(project, paper, revision, "a".repeat(64), model)
    private fun pages(text: String = "测试论文：机器人装配，金额 1,234.56 元", axis: Int = 0) =
        listOf(IndexedPage(0, text, vector(axis)))
    private fun rejected(action: () -> Unit) {
        try { action(); fail("Expected invalid index input to fail") } catch (_: IllegalArgumentException) { }
    }

    @Before fun open() {
        context = InstrumentationRegistry.getInstrumentation().targetContext
        name = "research-derived-test-${UUID.randomUUID()}.sqlite"
        index = ResearchIndex(context, name)
    }
    @After fun close() { index.close(); context.deleteDatabase(name) }

    @Test fun invalidVectorsAndTextPreservePublishedSource() {
        val original = source()
        index.publish(original, pages())
        val replacement = source(revision = "2")
        for (bad in listOf(FloatArray(768), FloatArray(767), vector().apply { this[0] = Float.NaN },
            vector().apply { this[0] = Float.POSITIVE_INFINITY }, vector().apply { this[0] = 2f })) {
            rejected { index.publish(replacement, listOf(IndexedPage(0, "invalid", bad))) }
            rejected { index.search(original.project, bad, model) { true } }
        }
        rejected { index.publish(replacement, pages("x".repeat(769))) }
        rejected { index.publish(replacement, listOf(IndexedPage(200, "invalid page", vector()))) }
        rejected { index.publish(replacement, emptyList()) }
        assertTrue(index.contains(original)); assertFalse(index.contains(replacement))
        assertEquals(1, index.search(original.project, vector(), model) { it == original }.size)
    }

    @Test fun sqliteFailureRollsBackReplacementAndPartialChunks() {
        val original = source()
        val sibling = original.copy(digest = "b".repeat(64))
        index.publish(original, pages("original"))
        index.publish(sibling, pages("other attachment"))
        SQLiteDatabase.openDatabase(context.getDatabasePath(name).path, null, SQLiteDatabase.OPEN_READWRITE).use { db ->
            db.execSQL("CREATE TRIGGER abort_second_chunk BEFORE INSERT ON chunks WHEN NEW.digest='${original.digest}' AND NEW.ordinal=1 BEGIN SELECT RAISE(ABORT,'test write failure'); END")
        }
        try {
            index.publish(source(revision = "2"), pages("first") + IndexedPage(1, "second", vector()))
            fail("Injected SQLite failure must abort publication")
        } catch (_: android.database.SQLException) { }
        assertTrue(index.contains(original)); assertFalse(index.contains(source(revision = "2")))
        assertTrue(index.contains(sibling))
        val hits = index.search(original.project, vector(), model) { true }
        assertEquals(setOf("original", "other attachment"), hits.map { it.text }.toSet())
        assertEquals(2, hits.size)
    }

    @Test fun searchRevalidatesSourcesAndIsolatesProjectsAndModels() {
        val a = source()
        val b = source(project = "project-b")
        val other = source(paper = "other-model").copy(modelIdentity = "another-model")
        index.publish(a, pages("allowed")); index.publish(b, pages("private other project"))
        index.publish(other, pages("other model"))
        var current = true
        var checks = 0
        fun search() = index.search(a.project, vector(), model) { candidate ->
            checks++; assertEquals(a, candidate); current
        }
        assertEquals(listOf("allowed"), search().map { it.text })
        current = false
        assertTrue(search().isEmpty())
        assertEquals(2, checks)
        assertTrue(index.search("unknown-project", vector(), model) { fail("No candidate expected"); true }.isEmpty())
        index.publish(source(revision = "2"), pages("updated"))
        assertFalse(index.contains(a))
        assertTrue(index.search(a.project, vector(), model) { it == a }.isEmpty())
    }

    @Test fun chunksSurviveReopenAndRankWithPageProvenance() {
        val a = source()
        index.publish(a, listOf(IndexedPage(3, "less relevant", vector(1)),
            IndexedPage(4, "机器人装配论文", vector()), IndexedPage(4, "同页第二片段", vector(2))))
        index.close()
        index = ResearchIndex(context, name)
        assertTrue(index.contains(a))
        val hit = index.search(a.project, vector(), model, 1) { it == a }.single()
        assertEquals(a, hit.source); assertEquals(4, hit.page)
        assertEquals("机器人装配论文", hit.text); assertEquals(1.0, hit.score, 0.00001)
        assertEquals(3, index.search(a.project, vector(), model) { true }.size)
    }

    @Test fun samePaperAttachmentsSurviveReopenAndReplaceOnlyTheirOwnDigest() {
        val a = source()
        val b = a.copy(digest = "b".repeat(64))
        index.publish(a, pages("attachment A"))
        index.publish(b, listOf(IndexedPage(7, "attachment B", vector(1))))
        index.close()
        index = ResearchIndex(context, name)
        assertTrue(index.contains(a)); assertTrue(index.contains(b))
        val original = index.search(a.project, vector(), model) { it == a || it == b }
        assertEquals(2, original.size)
        assertEquals(setOf(a, b), original.map { it.source }.toSet())
        assertEquals("attachment A", original.single { it.source == a }.text)
        assertEquals(7, original.single { it.source == b }.page)
        assertEquals("attachment B", original.single { it.source == b }.text)

        val next = a.copy(revision = "2")
        index.publish(next, pages("attachment A updated"))
        assertFalse(index.contains(a)); assertTrue(index.contains(next)); assertTrue(index.contains(b))
        assertEquals(setOf("attachment A updated", "attachment B"),
            index.search(a.project, vector(), model) { true }.map { it.text }.toSet())
        // The previous revision of the other attachment can remain derived data but is excluded
        // when the business source's current revision no longer matches it.
        val current = index.search(a.project, vector(), model) { it.revision == "2" }
        assertEquals(listOf(next), current.map { it.source })
    }

    @Test fun interruptedPublicationPreservesPreviousSource() {
        val a = source()
        index.publish(a, pages("original"))
        Thread.currentThread().interrupt()
        try {
            try { index.publish(source(revision = "2"), pages()); fail("Expected cancellation") }
            catch (_: InterruptedException) { }
        } finally { Thread.interrupted() }
        assertTrue(index.contains(a))
        assertFalse(index.contains(source(revision = "2")))
    }
}
