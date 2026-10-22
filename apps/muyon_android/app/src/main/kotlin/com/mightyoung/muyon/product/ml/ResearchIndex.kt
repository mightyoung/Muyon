package com.mightyoung.muyon.product.ml

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.io.Closeable
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.PriorityQueue
import kotlin.math.abs

data class IndexSource(
    val project: String, val paper: String, val revision: String,
    val digest: String, val modelIdentity: String,
)

/** Repeated page numbers represent separate chunks of that page. Page numbers are zero based. */
data class IndexedPage(val page: Int, val text: String, val vector: FloatArray)
data class SearchHit(val source: IndexSource, val page: Int, val text: String, val score: Double)

/** Disposable derived data, deliberately separate from the authoritative business database. */
class ResearchIndex internal constructor(context: Context, databaseName: String) : Closeable {
    constructor(context: Context) : this(context, DATABASE_NAME)

    companion object {
        const val DATABASE_NAME = "research-derived-v1.sqlite"
        const val DIMENSIONS = 768
        const val MAX_CHUNKS = 3200
        const val MAX_CHUNK_CHARACTERS = 768
        private const val MAX_TEXT_CHARACTERS = 2_000_000

        private fun validateText(value: String, limit: Int) {
            require(value.isNotBlank() && value.length <= limit && '\u0000' !in value) { "Invalid index text" }
        }

        private fun validateSource(source: IndexSource) {
            validateText(source.project, 512)
            validateText(source.paper, 512)
            validateText(source.revision, 512)
            require(source.digest.matches(Regex("[0-9a-f]{64}"))) { "Invalid attachment digest" }
            validateText(source.modelIdentity, 2048)
        }

        private fun validateVector(vector: FloatArray) {
            require(vector.size == DIMENSIONS && vector.all { it.isFinite() }) { "Invalid embedding dimensions or values" }
            val normSquared = vector.sumOf { it.toDouble() * it.toDouble() }
            require(abs(normSquared - 1.0) <= 0.001) { "Embedding must be normalized and nonzero" }
        }

        private fun encode(vector: FloatArray): ByteArray = ByteBuffer.allocate(DIMENSIONS * 4)
            .order(ByteOrder.LITTLE_ENDIAN).also { buffer -> vector.forEach { buffer.putFloat(it) } }.array()

        private fun decode(bytes: ByteArray): FloatArray {
            check(bytes.size == DIMENSIONS * 4) { "Invalid stored embedding size" }
            val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
            return FloatArray(DIMENSIONS) { buffer.float }.also(::validateVector)
        }

        private fun checkInterrupted() {
            if (Thread.currentThread().isInterrupted) throw InterruptedException("Index operation cancelled")
        }
    }

    private val helper = object : SQLiteOpenHelper(context.applicationContext, databaseName, null, 1) {
        override fun onConfigure(db: SQLiteDatabase) { db.setForeignKeyConstraintsEnabled(true) }
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE sources (project TEXT NOT NULL, paper TEXT NOT NULL, revision TEXT NOT NULL, digest TEXT NOT NULL, model TEXT NOT NULL, PRIMARY KEY(project,paper,digest))")
            db.execSQL("CREATE TABLE chunks (project TEXT NOT NULL, paper TEXT NOT NULL, digest TEXT NOT NULL, ordinal INTEGER NOT NULL, page INTEGER NOT NULL CHECK(page>=0 AND page<200), text TEXT NOT NULL, vector BLOB NOT NULL, PRIMARY KEY(project,paper,digest,ordinal), FOREIGN KEY(project,paper,digest) REFERENCES sources(project,paper,digest) ON DELETE CASCADE)")
        }
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            error("Unsupported derived index version")
        }
    }
    private var closed = false

    /** Validate everything before replacing an existing source; SQLite rolls back any write failure. */
    @Synchronized
    fun publish(source: IndexSource, pages: List<IndexedPage>, checkCancelled: () -> Unit = {}) {
        check(!closed) { "Index is closed" }
        validateSource(source)
        require(pages.isNotEmpty() && pages.size <= MAX_CHUNKS) { "Invalid chunk count" }
        var characters = 0L
        val snapshot = pages.map { chunk ->
            checkCancelled()
            checkInterrupted()
            require(chunk.page in 0 until 200) { "Invalid page number" }
            validateText(chunk.text, MAX_CHUNK_CHARACTERS)
            characters += chunk.text.length
            require(characters <= MAX_TEXT_CHARACTERS) { "Index text limit exceeded" }
            val vector = chunk.vector.copyOf().also(::validateVector)
            chunk.copy(vector = vector)
        }
        val db = helper.writableDatabase
        db.beginTransaction()
        try {
            checkCancelled()
            checkInterrupted()
            db.delete("sources", "project=? AND paper=? AND digest=?", arrayOf(source.project, source.paper, source.digest))
            db.insertOrThrow("sources", null, ContentValues().apply {
                put("project", source.project); put("paper", source.paper); put("revision", source.revision)
                put("digest", source.digest); put("model", source.modelIdentity)
            })
            snapshot.forEachIndexed { ordinal, chunk ->
                checkCancelled()
                checkInterrupted()
                db.insertOrThrow("chunks", null, ContentValues().apply {
                    put("project", source.project); put("paper", source.paper); put("digest", source.digest); put("ordinal", ordinal)
                    put("page", chunk.page); put("text", chunk.text); put("vector", encode(chunk.vector))
                })
            }
            checkInterrupted()
            checkCancelled()
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    /** Presence alone is not freshness evidence. Callers must verify the current authoritative source. */
    @Synchronized
    fun contains(source: IndexSource): Boolean {
        check(!closed) { "Index is closed" }
        validateSource(source)
        return helper.readableDatabase.rawQuery(
            "SELECT 1 FROM sources WHERE project=? AND paper=? AND revision=? AND digest=? AND model=? LIMIT 1",
            arrayOf(source.project, source.paper, source.revision, source.digest, source.modelIdentity),
        ).use { it.moveToFirst() }
    }

    /** Freshness is checked on every search, never inferred from an index cache. No network access. */
    @Synchronized
    fun search(
        project: String, queryVector: FloatArray, modelIdentity: String, limit: Int = 10,
        isCurrent: (IndexSource) -> Boolean,
    ): List<SearchHit> {
        check(!closed) { "Index is closed" }
        validateText(project, 512); validateText(modelIdentity, 2048)
        require(limit in 1..100) { "Invalid search limit" }
        val query = queryVector.copyOf().also(::validateVector)
        val best = PriorityQueue<SearchHit>(compareBy { it.score })
        val current = mutableMapOf<IndexSource, Boolean>()
        helper.readableDatabase.rawQuery(
            "SELECT s.paper,s.revision,s.digest,c.page,c.text,c.vector FROM sources s JOIN chunks c ON c.project=s.project AND c.paper=s.paper AND c.digest=s.digest WHERE s.project=? AND s.model=? ORDER BY s.paper,s.digest,c.ordinal",
            arrayOf(project, modelIdentity),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                checkInterrupted()
                val source = IndexSource(project, cursor.getString(0), cursor.getString(1), cursor.getString(2), modelIdentity)
                if (!current.getOrPut(source) { isCurrent(source) }) continue
                val vector = decode(cursor.getBlob(5))
                val score = query.indices.sumOf { query[it].toDouble() * vector[it].toDouble() }.coerceIn(-1.0, 1.0)
                val hit = SearchHit(source, cursor.getInt(3), cursor.getString(4), score)
                if (best.size < limit) best.add(hit)
                else if (score > requireNotNull(best.peek()).score) { best.remove(); best.add(hit) }
            }
        }
        return best.sortedWith(compareByDescending<SearchHit> { it.score }.thenBy { it.source.paper }.thenBy { it.source.digest }.thenBy { it.page })
    }

    @Synchronized
    override fun close() {
        if (!closed) { helper.close(); closed = true }
    }
}
