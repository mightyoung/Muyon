package com.mightyoung.muyon.product.chat.persistence

import org.json.JSONObject
import org.json.JSONTokener
import com.mightyoung.muyon.product.agents.setup.BotSetupDraft
import java.util.Base64
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.charset.CodingErrorAction
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.Path
import java.nio.file.StandardCopyOption.ATOMIC_MOVE
import java.nio.file.StandardCopyOption.REPLACE_EXISTING
import java.nio.file.StandardOpenOption.CREATE
import java.nio.file.StandardOpenOption.READ
import java.nio.file.StandardOpenOption.WRITE
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/** Stable-owner claims supplied ONLY by a future verified host resolver, never a lease.
 * This storage value is not ownership proof. Production resolver is currently absent. */
data class DraftStoreOwner(val accountId: String, val workspaceId: String, val conversationId: String, val projectId: String?)
data class DraftStoreReceipt(val owner: DraftStoreOwner, val draftId: String, val storedRevision: Long, val digest: String, val exportedMemoryRevision: Long? = null)
data class DraftStoreRecord(val owner: DraftStoreOwner, val draftId: String, val storedRevision: Long, val archive: ByteArray, val digest: String) {
    fun receipt() = DraftStoreReceipt(owner, draftId, storedRevision, digest)
}
sealed interface DraftStoreRead {
    data object Missing : DraftStoreRead
    data class Found(val record: DraftStoreRecord) : DraftStoreRead
    data class Rejected(val code: String) : DraftStoreRead
}
sealed interface DraftStoreWrite {
    data class Committed(val receipt: DraftStoreReceipt) : DraftStoreWrite
    data class Rejected(val code: String) : DraftStoreWrite
    /** Publication/durability uncertain: use this exact version/digest, never auto-retry. */
    data class Unknown(val attempt: DraftStoreReceipt) : DraftStoreWrite
}
enum class DraftStoreStage { BEFORE_TEMP_WRITE, BEFORE_MOVE, AFTER_MOVE }
private class InvalidDraft(val code: String) : RuntimeException()

/** Local file primitive, not currently connected to Service or any actual account.
 * Requires an existing, already durable app-private root and verified owner on EVERY call.
 * Host must durably create the namespace (including parent-directory fsync) before use. */
class HostDraftStore(root: Path, private val fault: (DraftStoreStage) -> Unit = {}) {
    private val root = root.toAbsolutePath().normalize()
    companion object {
        private const val MAX_BYTES = 65536
        private val processLocks = ConcurrentHashMap<Path, Any>()
    }
    private fun reject(code: String): Nothing = throw InvalidDraft(code)
    private fun ownerJson(owner: DraftStoreOwner): JSONObject {
        listOfNotNull(owner.accountId, owner.workspaceId, owner.conversationId, owner.projectId).forEach {
            if (it.isBlank() || it.length > 1024 || it.any { c -> c.isISOControl() }) reject("draft_owner_invalid")
        }
        return JSONObject().put("account_id", owner.accountId).put("workspace_id", owner.workspaceId)
            .put("conversation_id", owner.conversationId).put("project_id", owner.projectId ?: JSONObject.NULL)
    }
    private fun checkedId(id: String) {
        if (try { UUID.fromString(id).toString() != id } catch (_: IllegalArgumentException) { true }) reject("draft_identity_invalid")
    }
    private fun sha(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    private fun utf8(text: String): ByteArray {
        val encoded = Charsets.UTF_8.newEncoder().onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT).encode(java.nio.CharBuffer.wrap(text))
        return ByteArray(encoded.remaining()).also { encoded.get(it) }
    }
    private fun document(owner: DraftStoreOwner, id: String, revision: Long, archive: ByteArray): JSONObject {
        checkedId(id)
        if (revision < 0 || archive.size > 32768) reject("draft_data_invalid")
        // Fixed reviewed canonical codec validates an edit-only archive; never reflect
        // or reimplement reducer fields/locks/creation state. This scope only validates,
        // it is NOT a restored production owner or permission grant.
        val validationScope = ownerJson(owner).toString()
        val parsed = BotSetupDraft.restoreDraft(archive, validationScope, id)
        if (parsed.storedRevision != revision) reject("draft_revision_mismatch")
        return JSONObject().put("schema_version", 1).put("owner", ownerJson(owner)).put("draft_id", id).put("stored_revision", revision)
            .put("archive_base64", Base64.getEncoder().encodeToString(archive))
    }
    private fun file(owner: DraftStoreOwner, id: String): Path {
        checkedId(id)
        return root.resolve(sha(utf8(ownerJson(owner).toString())) + "-" + id + ".json")
    }
    private fun <T> locked(block: () -> T): T = synchronized(processLocks.computeIfAbsent(root) { Any() }) {
        if (Files.isSymbolicLink(root)) reject("draft_storage_invalid")
        if (!Files.isDirectory(root, NOFOLLOW_LINKS)) reject("draft_storage_root_unavailable")
        val lock = root.resolve(".draft-store.lock")
        if (Files.isSymbolicLink(lock)) reject("draft_storage_invalid")
        FileChannel.open(lock, CREATE, WRITE).use { channel -> channel.lock().use { block() } }
    }
    private fun exact(value: JSONObject, fields: Set<String>) {
        if (value.keys().asSequence().toSet() != fields) reject("draft_schema_invalid")
    }
    private fun string(value: JSONObject, field: String) = value.opt(field) as? String ?: reject("draft_schema_invalid")
    private fun number(value: JSONObject, field: String): Long = when (val item = value.opt(field)) {
        is Int -> item.toLong()
        is Long -> item
        else -> reject("draft_schema_invalid")
    }
    private fun readLocked(owner: DraftStoreOwner, id: String): DraftStoreRecord? {
        val path = file(owner, id)
        if (!Files.exists(path, NOFOLLOW_LINKS)) return null
        if (Files.isSymbolicLink(path) || !Files.isRegularFile(path, NOFOLLOW_LINKS)) reject("draft_storage_invalid")
        val bytes = Files.newInputStream(path).use { input ->
            val out = ByteArrayOutputStream(); val buffer = ByteArray(4096)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (out.size() + count > MAX_BYTES) reject("draft_size_invalid")
                out.write(buffer, 0, count)
            }
            out.toByteArray()
        }
        val raw = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
        if (raw.contains('\u0000')) reject("draft_schema_invalid")
        val parser = JSONTokener(raw)
        val json = parser.nextValue() as? JSONObject ?: reject("draft_schema_invalid")
        if (parser.nextClean() != '\u0000') reject("draft_schema_invalid")
        exact(json, setOf("schema_version", "owner", "draft_id", "stored_revision", "archive_base64", "digest"))
        if (number(json, "schema_version") != 1L) reject("draft_schema_unsupported")
        val storedOwner = json.getJSONObject("owner")
        exact(storedOwner, setOf("account_id", "workspace_id", "conversation_id", "project_id"))
        val project = storedOwner.opt("project_id")
        if (project !== JSONObject.NULL && project !is String) reject("draft_schema_invalid")
        if (DraftStoreOwner(string(storedOwner, "account_id"), string(storedOwner, "workspace_id"),
                string(storedOwner, "conversation_id"), project as? String) != owner || string(json, "draft_id") != id) reject("draft_owner_mismatch")
        val encoded = string(json, "archive_base64")
        if (encoded.length > 43692) reject("draft_size_invalid")
        val archive = Base64.getDecoder().decode(encoded)
        if (Base64.getEncoder().encodeToString(archive) != encoded) reject("draft_schema_invalid")
        val revision = number(json, "stored_revision")
        val digest = sha(utf8(document(owner, id, revision, archive).toString()))
        if (string(json, "digest") != digest) reject("draft_integrity_invalid")
        return DraftStoreRecord(owner, id, revision, archive, digest)
    }
    fun read(owner: DraftStoreOwner, id: String, minimumStoredRevision: Long?): DraftStoreRead = try {
        if (minimumStoredRevision != null && minimumStoredRevision < 0) reject("draft_revision_invalid")
        locked {
            val record = readLocked(owner, id)
            if ((record == null && minimumStoredRevision != null) || (record != null && minimumStoredRevision != null && record.storedRevision < minimumStoredRevision))
                reject("draft_rollback_refused")
            record?.let { DraftStoreRead.Found(it) } ?: DraftStoreRead.Missing
        }
    } catch (failure: InvalidDraft) { DraftStoreRead.Rejected(failure.code)
    } catch (_: Exception) { DraftStoreRead.Rejected("draft_storage_unavailable") }

    fun save(owner: DraftStoreOwner, id: String, expectedStoredRevision: Long?, exportedMemoryRevision: Long, archive: ByteArray): DraftStoreWrite {
        if (archive.size > 32768 || exportedMemoryRevision < 0) return DraftStoreWrite.Rejected("draft_data_invalid")
        val frozenArchive = archive.copyOf()
        var publishing: DraftStoreReceipt? = null
        var temporary: Path? = null
        return try {
            locked {
                val old = readLocked(owner, id)
                if (old?.storedRevision != expectedStoredRevision) reject("draft_revision_mismatch")
                if (old?.storedRevision == Long.MAX_VALUE) reject("draft_revision_exhausted")
                val revision = Math.addExact(old?.storedRevision ?: 0L, 1L)
                val json = document(owner, id, revision, frozenArchive)
                val digest = sha(utf8(json.toString()))
                val bytes = utf8(json.put("digest", digest).toString())
                if (bytes.size > MAX_BYTES) reject("draft_size_invalid")
                fault(DraftStoreStage.BEFORE_TEMP_WRITE)
                val stage = Files.createTempFile(root, ".draft-stage-", ".tmp").also { temporary = it }
                FileChannel.open(stage, WRITE).use { channel ->
                    val buffer = ByteBuffer.wrap(bytes)
                    while (buffer.hasRemaining()) channel.write(buffer)
                    channel.force(true)
                }
                fault(DraftStoreStage.BEFORE_MOVE)
                publishing = DraftStoreReceipt(owner, id, revision, digest, exportedMemoryRevision)
                Files.move(stage, file(owner, id), ATOMIC_MOVE, REPLACE_EXISTING)
                fault(DraftStoreStage.AFTER_MOVE)
                FileChannel.open(root, READ).use { it.force(true) }
                DraftStoreWrite.Committed(checkNotNull(publishing))
            }
        } catch (failure: InvalidDraft) { DraftStoreWrite.Rejected(failure.code)
        } catch (_: Exception) { publishing?.let { DraftStoreWrite.Unknown(it) } ?: DraftStoreWrite.Rejected("draft_storage_unavailable")
        } finally { temporary?.let { runCatching { Files.deleteIfExists(it) } } }
    }
    /** Confirms only the captured original version/digest after an uncertain write. */
    fun recoverReceipt(attempt: DraftStoreReceipt, minimumStoredRevision: Long?): DraftStoreWrite = try {
        if (minimumStoredRevision != null && (minimumStoredRevision < 0 || attempt.storedRevision < minimumStoredRevision)) reject("draft_rollback_refused")
        locked {
            val record = readLocked(attempt.owner, attempt.draftId)
            if (record?.receipt() != attempt.copy(exportedMemoryRevision = null)) reject("draft_original_outcome_unavailable")
            FileChannel.open(file(attempt.owner, attempt.draftId), WRITE).use { it.force(true) }
            FileChannel.open(root, READ).use { it.force(true) }
            DraftStoreWrite.Committed(attempt)
        }
    } catch (failure: InvalidDraft) { DraftStoreWrite.Rejected(failure.code)
    } catch (_: Exception) { DraftStoreWrite.Unknown(attempt) }
}
