package com.mightyoung.muyon.product

import android.app.ActivityManager
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.os.SystemClock
import android.util.Base64
import android.util.Log
import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.product.agentipc.ProductClient
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

/** One near-cap resource observation, not a performance or import acceptance claim.
 * Uses the real private Service, bundled archive parser and immutable upload.
 * A pre-existing project is required: no business write is issued by this test.
 */
class MaxArchiveResourceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private lateinit var client: ProductClient
    // Pinned to blobs::MAX_UPLOAD_BYTES/archive::MAX_ARCHIVE_BYTES and
    // archive::MAX_MEMBER_BYTES. The resulting ZIP length is asserted below.
    private val archiveCap = 150L * 1024 * 1024
    private val memberCap = 30L * 1024 * 1024
    private val chunkSize = 65_536

    private fun connect() {
        val ready = CountDownLatch(1)
        instrumentation.runOnMainSync {
            client = ProductClient(context) { if (it) ready.countDown() }
            client.bind()
        }
        assertTrue("real Service connection", ready.await(15, TimeUnit.SECONDS))
    }

    private fun call(method: String, payload: JSONObject = JSONObject()): JSONObject {
        val done = CountDownLatch(1)
        var reply: JSONObject? = null
        instrumentation.runOnMainSync { client.call(method, payload) { reply = it; done.countDown() } }
        assertTrue("$method returned within the real client deadline", done.await(35, TimeUnit.SECONDS))
        return requireNotNull(reply)
    }

    private fun data(method: String, payload: JSONObject = JSONObject()): JSONObject {
        val reply = call(method, payload)
        assertEquals("$method must finish explicitly: $reply", "ok", reply.optString("status"))
        return reply.getJSONObject("data")
    }

    private fun writeArchive(file: File, fixture: String) {
        val block = ByteArray(chunkSize) { (it % 251).toByte() }
        fun repeated(length: Long, consume: (ByteArray, Int) -> Unit) {
            var remaining = length
            while (remaining > 0) {
                val count = minOf(remaining, block.size.toLong()).toInt()
                consume(block, count)
                remaining -= count
            }
        }
        ZipOutputStream(file.outputStream().buffered(chunkSize)).use { zip ->
            repeat(5) { index ->
                // Leave 4 KiB for ZIP32 local/central headers; all members fit
                // the actual 30 MiB member limit and total expanded limit.
                val length = memberCap - if (index == 4) 4096 else 0
                val crc = CRC32().also { repeated(length) { bytes, count -> it.update(bytes, 0, count) } }
                val entry = ZipEntry("resources/$fixture/part-$index.bin").apply {
                    method = ZipEntry.STORED
                    size = length
                    compressedSize = length
                    this.crc = crc.value
                    time = 1_600_000_000_000L // DOS-compatible, no extended-time fields.
                }
                zip.putNextEntry(entry)
                repeated(length) { bytes, count -> zip.write(bytes, 0, count) }
                zip.closeEntry()
            }
        }
        assertTrue("ZIP must exercise within one upload chunk of the real cap: ${file.length()}",
            file.length() in (archiveCap - chunkSize)..archiveCap)
        ZipFile(file).use { zip ->
            assertEquals("legal ZIP container", 5, zip.size())
            val entries = zip.entries()
            var expanded = 0L
            while (entries.hasMoreElements()) {
                val entry = entries.nextElement()
                assertEquals(ZipEntry.STORED, entry.method)
                assertTrue(entry.size in 1..memberCap)
                expanded += entry.size
            }
            assertEquals(archiveCap - 4096, expanded)
        }
    }

    private fun businessSnapshot(): String {
        val database = File(context.filesDir, "muyon-product-v2/business-v2.sqlite")
        val counts = JSONObject()
        val receipts = MessageDigest.getInstance("SHA-256")
        SQLiteDatabase.openDatabase(database.absolutePath, null, SQLiteDatabase.OPEN_READONLY).use { db ->
            for (table in listOf("supplier", "supplier_history", "business_history", "projects", "research_entries",
                "research_sources", "research_documents", "research_bindings", "research_citations", "research_import_members", "blob_references")) {
                db.rawQuery("SELECT count(*) FROM $table", null).use { cursor ->
                    assertTrue(cursor.moveToFirst()); counts.put(table, cursor.getLong(0))
                }
            }
            db.rawQuery("SELECT intent_id,binding_digest,status,receipt_json,error,owner_epoch FROM intents ORDER BY intent_id", null).use { cursor ->
                while (cursor.moveToNext()) for (index in 0 until cursor.columnCount) {
                    val value = if (cursor.isNull(index)) "N" else "S${cursor.getString(index)}"
                    val bytes = value.toByteArray(Charsets.UTF_8)
                    receipts.update(bytes.size.toString().toByteArray(Charsets.US_ASCII))
                    receipts.update(0.toByte()); receipts.update(bytes)
                }
            }
        }
        counts.put("intent_receipt_sha256", receipts.digest().joinToString("") { "%02x".format(it) })
        return counts.toString()
    }

    private fun <T> measured(name: String, pid: Int, metrics: JSONObject, action: () -> T): T {
        val sampling = AtomicBoolean(true)
        val peakPss = AtomicInteger(0)
        val samples = AtomicInteger(0)
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val observer = Thread {
            while (sampling.get()) {
                try {
                    val pss = manager.getProcessMemoryInfo(intArrayOf(pid)).single().totalPss
                    if (pss > 0) { samples.incrementAndGet(); peakPss.updateAndGet { maxOf(it, pss) } }
                } catch (_: Exception) { /* Unavailable observations are recorded, never invented. */ }
                try { Thread.sleep(250) } catch (_: InterruptedException) { break }
            }
        }.apply { isDaemon = true; start() }
        val start = SystemClock.elapsedRealtime()
        try { return action() } finally {
            sampling.set(false); observer.interrupt(); observer.join(1000)
            metrics.put(name, JSONObject().put("elapsed_ms", SystemClock.elapsedRealtime() - start)
                .put("core_pss_peak_kib", if (samples.get() == 0) JSONObject.NULL else peakPss.get())
                .put("pss_samples", samples.get()).put("pss_scope", "sampled phase peak, not a guaranteed process high-water mark"))
        }
    }

    @Test(timeout = 600_000)
    fun near150MiBStoredArchiveUsesRealWholeReadPathWithoutBusinessEffects() {
        val fixture = UUID.randomUUID().toString()
        val zip = File(context.cacheDir, "max-archive-resource-$fixture.zip")
        val metrics = JSONObject().put("fixture", fixture).put("archive_cap_bytes", archiveCap)
            .put("member_cap_bytes", memberCap).put("initial_free_bytes", context.cacheDir.usableSpace)
        var upload: String? = null
        var digest: String? = null
        var baseline: String? = null
        var connected = false
        var primaryFailure: Throwable? = null
        try {
            assertTrue("need space for this fixture's ZIP, staging and publication copy", context.cacheDir.usableSpace >= 3 * archiveCap + 64L * 1024 * 1024)
            connect(); connected = true
            val health = data("health")
            val pid = health.getInt("service_pid")
            metrics.put("core_pid", pid).put("build_id", health.getString("build_id"))
            val projects = call("projects", JSONObject().put("limit", 1))
            assertEquals(projects.toString(), "ok", projects.optString("status"))
            val rows = projects.getJSONArray("data")
            assertTrue("run an existing research fixture first; this stress test never creates business records", rows.length() > 0)
            val project = rows.getJSONObject(0).getString("id")
            baseline = businessSnapshot()
            measured("generate_zip", pid, metrics) { writeArchive(zip, fixture) }
            metrics.put("actual_zip_bytes", zip.length())
            upload = data("begin_upload", JSONObject().put("project_id", project)).getString("upload_id")
            measured("upload", pid, metrics) {
                zip.inputStream().buffered(chunkSize).use { input ->
                    val block = ByteArray(chunkSize)
                    var uploaded = 0L
                    while (true) {
                        val count = input.read(block)
                        if (count < 0) break
                        val reply = data("append_upload", JSONObject().put("upload_id", upload)
                            .put("bytes", Base64.encodeToString(block, 0, count, Base64.NO_WRAP)))
                        uploaded += count
                        assertEquals(uploaded.toString(), reply.getString("byte_length"))
                    }
                    assertEquals(zip.length(), uploaded)
                }
            }
            val finished = measured("finish_upload_whole_read", pid, metrics) {
                data("finish_upload", JSONObject().put("upload_id", upload).put("kind", "archive"))
            }
            digest = finished.getJSONObject("blob").getString("digest")
            val manifest = measured("archive_manifest_whole_read", pid, metrics) {
                data("archive_manifest", JSONObject().put("upload_id", upload))
            }
            metrics.put("manifest", manifest).put("manifest_result", "container_accepted_without_business_import")
            assertEquals(5, manifest.getInt("entry_count"))
            assertEquals(archiveCap - 4096, manifest.getLong("expanded_bytes"))
            val after = data("health")
            assertEquals("original core process survives both whole-read paths", pid, after.getInt("service_pid"))
            assertEquals(health.getString("epoch"), after.getString("epoch"))
            assertEquals("no business row or original receipt changes", baseline, businessSnapshot())
            metrics.put("operation_passed", true)
        } catch (failure: Throwable) {
            primaryFailure = failure
            metrics.put("outcome", "failed").put("failure_type", failure.javaClass.simpleName)
                .put("failure_message", failure.message?.take(1000) ?: JSONObject.NULL)
            throw failure
        } finally {
            try {
                if (connected && upload != null) {
                    val aborted = call("abort_upload", JSONObject().put("upload_id", upload))
                    metrics.put("abort_status", aborted.optString("status"))
                    assertEquals("abort only this fixture upload", "ok", aborted.optString("status"))
                    val state = data("lookup_upload", JSONObject().put("upload_id", upload))
                    assertEquals("aborted", state.getString("state"))
                    assertFalse(File(context.filesDir, "muyon-product-v2/business-v2.sqlite.blobs/staging/$upload").exists())
                    instrumentation.runOnMainSync { client.close() }; connected = false
                    // Normal owner retirement/startup drives the same guarded GC;
                    // no direct file/database deletion or forced core kill.
                    connect(); connected = true
                    data("health")
                    digest?.let { assertFalse("this aborted fixture object is collected", File(context.filesDir,
                        "muyon-product-v2/business-v2.sqlite.blobs/objects/$it").exists()) }
                    baseline?.let { assertEquals("cleanup preserves business/receipt baseline", it, businessSnapshot()) }
                }
                if (primaryFailure == null) metrics.put("outcome", "passed")
            } catch (cleanup: Throwable) {
                metrics.put("outcome", "failed").put("cleanup_failure_type", cleanup.javaClass.simpleName)
                    .put("cleanup_failure_message", cleanup.message?.take(1000) ?: JSONObject.NULL)
                if (primaryFailure != null) primaryFailure.addSuppressed(cleanup) else throw cleanup
            } finally {
                if (connected) instrumentation.runOnMainSync { client.close() }
                val zipRemoved = !zip.exists() || zip.delete()
                metrics.put("fixture_zip_removed", zipRemoved)
                val folder = File(context.getExternalFilesDir(null), "resource-evidence").also { check(it.mkdirs() || it.isDirectory) }
                File(folder, "max-archive-$fixture.json").writeText(metrics.toString(2))
                Log.i("MuyonMaxArchiveResource", metrics.toString())
                println("MAX_ARCHIVE_RESOURCE ${metrics}")
                assertTrue("remove only this test's generated ZIP", zipRemoved)
            }
        }
    }
}
