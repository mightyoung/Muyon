package com.mightyoung.muyon.product.agentipc

import android.app.ActivityManager
import android.content.*
import android.os.*
import com.mightyoung.muyon.product.BuildConfig
import java.io.InputStream
import java.security.MessageDigest
import java.util.zip.ZipFile
import androidx.test.platform.app.InstrumentationRegistry
import com.mightyoung.muyon.product.agents.setup.BotSetupDraft
import com.mightyoung.muyon.product.chat.persistence.*
import com.mightyoung.muyon.productbridge.LocalDraftPrepareRequest
import com.mightyoung.muyon.productbridge.ProductCore
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/** Device-only acceptance. No FakePort, ABI stub, model, credential or user DB.
 * Bind ONLY debug fixture, whose inherited Service calls actual generated native APIs. */
class BotNativeServiceAcceptanceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val conversation = UUID.randomUUID().toString()
    private val replies = LinkedBlockingQueue<Bundle>()
    private var dead = CountDownLatch(1)
    private var service: Messenger? = null
    private var connection: ServiceConnection? = null
    private var session = ""
    private var epoch = ""
    private var generation = 0L
    private var project: String? = null
    private val reply = Messenger(object : Handler(Looper.getMainLooper()) {
        override fun handleMessage(message: Message) { replies.put(Bundle(message.data)) }
    })
    private fun call(method: String, payload: JSONObject = JSONObject()): JSONObject {
        val id = UUID.randomUUID().toString()
        service!!.send(Message.obtain().apply {
            replyTo = reply
            data = Bundle().apply { putString("request_id", id); putString("method", method)
                putString("payload", payload.toString()); putString("session", session); putString("epoch", epoch) }
        })
        val result = checkNotNull(replies.poll(20, TimeUnit.SECONDS)) { "Service timeout: $method; outcome UNKNOWN, no retry" }
        val response = JSONObject(checkNotNull(result.getString("response")))
        assertEquals(id, response.getString("request_id"))
        return response
    }
    private fun data(method: String, payload: JSONObject = JSONObject()): JSONObject = call(method, payload).let {
        assertEquals(it.toString(), "ok", it.getString("status")); it.getJSONObject("data")
    }
    private fun connect() {
        val connected = CountDownLatch(1)
        val disconnected = CountDownLatch(1)
        dead = disconnected
        val actual = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName, binder: IBinder) { service = Messenger(binder); connected.countDown() }
            override fun onServiceDisconnected(name: ComponentName) {
                service = null
                context.unbindService(this) // do not leave AUTO_CREATE binding to restart the dead fixture
                connection = null
                disconnected.countDown()
            }
        }
        connection = actual
        instrumentation.runOnMainSync {
            assertTrue(context.bindService(Intent(context, BotNativeAcceptanceService::class.java), actual, Context.BIND_AUTO_CREATE))
        }
        assertTrue("debug fixture did not bind", connected.await(15, TimeUnit.SECONDS))
        val info = data("connect"); session = info.getString("session"); epoch = info.getString("epoch")
        assertEquals("bot-native-acceptance", info.getString("workspace"))
        if (!info.getBoolean("initialized")) data("initialize") else data("health")
        recordInstalledIdentity(data("health"))
        generation = data("chat_scope", JSONObject().put("project_id", project ?: JSONObject.NULL)).getLong("scope_generation")
    }
    /** Evidence from actual loaded native health and installed APK, never fixture constants.
     * Host must independently compare the logged APK/library hashes to sealed build inputs. */
    private fun recordInstalledIdentity(health: JSONObject) {
        assertTrue("unsealed APK source", BuildConfig.MUYON_SOURCE.matches(Regex("[0-9a-f]{40}:[0-9a-f]{64}")))
        assertEquals(BuildConfig.MUYON_SOURCE, health.getString("build_id"))
        assertFalse(health.getBoolean("synthetic"))
        assertEquals("bot-native-acceptance", health.getString("workspace"))
        fun hash(input: InputStream): String = input.use {
            val digest = MessageDigest.getInstance("SHA-256")
            val bytes = ByteArray(65_536)
            while (true) { val count = it.read(bytes); if (count < 0) break; digest.update(bytes, 0, count) }
            digest.digest().joinToString("") { byte -> "%02x".format(byte) }
        }
        val installed = File(context.applicationInfo.sourceDir)
        val natives = JSONObject()
        ZipFile(installed).use { zip ->
            for (abi in listOf("arm64-v8a", "x86_64")) for (library in listOf("libmuyon_android_product.so", "libmuyon_local_embedding.so")) {
                val path = "lib/$abi/$library"
                natives.put(path, hash(zip.getInputStream(checkNotNull(zip.getEntry(path)))))
            }
        }
        android.util.Log.i("BotNativeAcceptance", JSONObject().put("health", health)
            .put("installed_apk_sha256", hash(installed.inputStream())).put("packaged_native_sha256", natives).toString())
    }
    private fun operation(action: String, previous: JSONObject? = null, value: String? = null, expected: Long? = null): JSONObject {
        val op = JSONObject().put("action", action)
        if (previous != null) {
            op.put("local_draft_id", previous.getString("local_draft_id"))
            if (action != "read") op.put("expected_local_revision", expected ?: previous.getLong("local_revision"))
        }
        value?.let { op.put("value", it) }
        return data("chat_setup_draft", JSONObject().put("conversation_id", conversation)
            .put("project_id", project ?: JSONObject.NULL).put("scope_generation", generation).put("operation", op))
    }
    private fun killOnlyFixture() {
        if (service == null) return
        val pid = data("health").getInt("service_pid")
        assertNotEquals(Process.myPid(), pid)
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        assertTrue(manager.runningAppProcesses.any { it.pid == pid && it.processName == context.packageName + ":bot_native_acceptance" })
        Process.killProcess(pid)
        assertTrue("fixture process death not observed", dead.await(15, TimeUnit.SECONDS))
        connection?.let { c -> instrumentation.runOnMainSync { context.unbindService(c) } }
        connection = null
    }
    @After fun stopFixture() { killOnlyFixture() }

    @Test fun realServiceSaveCasCancelAndProcessLossRestore() {
        connect()
        // A real synthetic project through existing local review/confirm, no execution/model gateway.
        project = "bot-acceptance-${UUID.randomUUID()}"
        val plan = data("prepare", JSONObject().put("expected_revision", "0").put("operation", JSONObject()
            .put("operation", "project_create").put("project_id", project).put("name", "Synthetic Bot acceptance")))
        assertEquals("committed", data("confirm", JSONObject().put("plan_id", plan.getString("plan_id"))).getString("status"))
        generation = data("chat_scope", JSONObject().put("project_id", project)).getLong("scope_generation")
        var view = operation("open")
        assertEquals("local_workspace", view.getString("persistent_owner_status"))
        view = operation("edit_name", view, "Synthetic saved Bot")
        val stale = operation("edit_name", view, "MUST NOT APPLY", view.getLong("local_revision") - 1)
        assertEquals("setup_revision_mismatch", stale.getString("error"))
        view = operation("save", view)
        assertTrue(view.getBoolean("saved")); assertEquals("1", view.getString("stored_revision"))
        val original = view.getJSONObject("original_save_outcome").getString("attempt_id")
        val duplicate = operation("save", view)
        assertEquals("setup_operation_unavailable", duplicate.getString("error"))
        val cancelled = operation("cancel", view)
        assertTrue(cancelled.getBoolean("cancelled")); assertFalse(cancelled.getBoolean("saved"))
        val resumed = operation("resume", cancelled)
        assertEquals("Synthetic saved Bot", resumed.getString("name"))
        val oldGeneration = generation
        generation = data("chat_scope", JSONObject().put("project_id", JSONObject.NULL)).getLong("scope_generation")
        val staleScope = data("chat_setup_draft", JSONObject().put("conversation_id", conversation).put("project_id", project)
            .put("scope_generation", oldGeneration).put("operation", JSONObject().put("action", "open")))
        assertEquals("setup_scope_unavailable", staleScope.getString("error"))
        killOnlyFixture()
        connect()
        var cold = operation("open")
        assertFalse(cold.getBoolean("saved")); assertEquals("", cold.getString("name"))
        assertEquals(original, cold.getString("original_save_attempt_id"))
        cold = operation("query_original_save", cold)
        val history = cold.getJSONObject("original_save_outcome")
        assertTrue(history.getBoolean("cold_recovered")); assertFalse(history.getBoolean("acknowledges_current_editor"))
        assertFalse(cold.getBoolean("saved")); assertTrue(cold.getBoolean("can_restore"))
        cold = operation("restore", cold)
        assertEquals("Synthetic saved Bot", cold.getString("name"))
        assertFalse(cold.getBoolean("can_create")); assertFalse(cold.getBoolean("can_start"))
        assertTrue(cold.isNull("actual_micro_cny")); assertTrue(cold.isNull("reserved_micro_cny"))
    }

    @Test fun realNativePreparedOriginalIsDiscoveredAndExplicitlyFencedByService() {
        // Set up actual durable original before the Service starts; no synthetic reply or port.
        val root = File(context.filesDir, "bot-native-acceptance-fixture")
        val lease = DraftViewLease("bot-native-acceptance", conversation, null, UUID.randomUUID().toString(), 1)
        lateinit var prepared: PreparedLocalSave
        ProductCore.open(root.absolutePath, lease.workspaceId, UUID.randomUUID().toString(), !File(root, "business-v2.sqlite").isFile).use { core ->
            val record = NativeLocalDraftCodec.resolve(JSONObject(core.localDraftResolve(conversation, null)), lease).record
            val draft = BotSetupDraft("synthetic setup scope", record.draftId)
            draft.editName("Prepared only; never dispatch on recovery")
            prepared = HostDraftSaveState(record, draft, lease).prepare(draft, lease, 1)
            fun request(generation: String = record.registryGeneration.toString(), revision: String = "0") = LocalDraftPrepareRequest(
                conversation, null, record.namespaceId, record.draftId, generation, revision, prepared.attemptId,
                prepared.exportedMemoryRevision.toString(), "1", prepared.archive)
            val first = JSONObject(core.localDraftPrepareSave(request()))
            val duplicate = JSONObject(core.localDraftPrepareSave(request()))
            assertEquals(NativeLocalDraftCodec.prepared(first, lease, prepared), NativeLocalDraftCodec.prepared(duplicate, lease, prepared))
            try { core.localDraftPrepareSave(request((record.registryGeneration + 1).toString())); fail("stale generation accepted") }
            catch (_: com.mightyoung.muyon.productbridge.ProductException) { }
            try { core.localDraftPrepareSave(request(revision = "1")); fail("stale stored revision accepted") }
            catch (_: com.mightyoung.muyon.productbridge.ProductException) { }
        }
        connect()
        var cold = operation("open")
        assertEquals("unknown", cold.getString("persistence_status"))
        assertEquals(prepared.attemptId, cold.getString("original_save_attempt_id"))
        assertFalse(cold.getBoolean("can_save")); assertFalse(cold.getBoolean("can_restore"))
        cold = operation("query_original_save", cold)
        val outcome = cold.getJSONObject("original_save_outcome")
        assertEquals("not_committed_local_storage", outcome.getString("status"))
        assertTrue(outcome.getBoolean("cold_recovered")); assertFalse(cold.getBoolean("saved"))
        killOnlyFixture()
        ProductCore.open(root.absolutePath, lease.workspaceId, UUID.randomUUID().toString(), false).use { core ->
            try {
                val r = prepared.record
                core.localDraftSave(conversation, null, r.namespaceId, r.draftId, r.registryGeneration.toString(), "0",
                    prepared.attemptId, prepared.exportedMemoryRevision.toString(), prepared.archive)
                fail("late save after original outcome fence accepted")
            } catch (_: com.mightyoung.muyon.productbridge.ProductException) { }
        }
    }
    @Test fun committedNativeReplyDiscardedIsRecoveredOnlyAsOriginalHistory() {
        val root = File(context.filesDir, "bot-native-acceptance-fixture")
        val lease = DraftViewLease("bot-native-acceptance", conversation, null, UUID.randomUUID().toString(), 1)
        lateinit var original: PreparedLocalSave
        ProductCore.open(root.absolutePath, lease.workspaceId, UUID.randomUUID().toString(), !File(root, "business-v2.sqlite").isFile).use { core ->
            val record = NativeLocalDraftCodec.resolve(JSONObject(core.localDraftResolve(conversation, null)), lease).record
            val draft = BotSetupDraft("synthetic lost receipt", record.draftId)
            draft.editName("Durable edits; lost delivery")
            original = HostDraftSaveState(record, draft, lease).prepare(draft, lease, 1)
            core.localDraftPrepareSave(LocalDraftPrepareRequest(conversation, null, record.namespaceId, record.draftId,
                record.registryGeneration.toString(), "0", original.attemptId, original.exportedMemoryRevision.toString(), "1", original.archive))
            fun save() = JSONObject(core.localDraftSave(conversation, null, record.namespaceId, record.draftId,
                record.registryGeneration.toString(), "0", original.attemptId, original.exportedMemoryRevision.toString(), original.archive))
            val committed = save() // Delivery is discarded; native state itself is genuinely committed.
            assertEquals(LocalSavePhase.COMMITTED, NativeLocalDraftCodec.outcome(committed, lease, NativeLocalDraftCodec.fromExport(original)).phase)
            assertEquals(LocalSavePhase.COMMITTED, NativeLocalDraftCodec.outcome(save(), lease, NativeLocalDraftCodec.fromExport(original)).phase)
            try { core.localDraftLookupSave(UUID.randomUUID().toString(), null, record.namespaceId, record.draftId, original.attemptId); fail("foreign conversation accepted") }
            catch (_: com.mightyoung.muyon.productbridge.ProductException) { }
        }
        connect()
        var cold = operation("open")
        assertEquals("unknown", cold.getString("persistence_status"))
        assertEquals(original.attemptId, cold.getString("original_save_attempt_id"))
        assertFalse(cold.getBoolean("can_save")); assertFalse(cold.getBoolean("saved"))
        cold = operation("query_original_save", cold)
        val receipt = cold.getJSONObject("original_save_outcome")
        assertEquals("committed_local_storage", receipt.getString("status"))
        assertTrue(receipt.getBoolean("cold_recovered")); assertFalse(receipt.getBoolean("acknowledges_current_editor"))
        assertEquals("", cold.getString("name"))
        cold = operation("restore", cold)
        assertEquals("Durable edits; lost delivery", cold.getString("name"))
        assertFalse(cold.getBoolean("can_create")); assertFalse(cold.getBoolean("can_start"))
    }

}
