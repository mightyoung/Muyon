package com.mightyoung.muyon.product.agents.setup

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest

/** Storage CAS belongs to the host. This revision is never installed as the reducer revision. */
data class RestoredBotSetupDraft(val draft: BotSetupDraft, val storedRevision: Long)

internal data class ArchivedSetupEdits(val storedRevision: Long, val name: DraftField,
    val purpose: DraftField, val role: DraftField, val template: TemplateSource?)

/**
 * Strict binary edit-only schema v1. Not an Agent, authority or authenticated envelope.
 * SHA256 detects corruption, not malicious rewrites with a recomputed digest. Host must isolate
 * account/project files, reject rollback and block restore while any creation intent is unresolved.
 */
internal object SetupDraftArchive {
    private const val MAGIC = 0x4D594244 // MYBD
    private const val VERSION = 1
    private const val MAX_BYTES = 32768
    private const val HASH_BYTES = 32

    private fun validateField(field: DraftField, max: Int, role: Boolean = false) {
        validateSetupText(field.value, max, required = field.value.isNotEmpty())
        require(field.revision == 0L) // Field revisions are deliberately excluded from storage.
        if (field.value.isEmpty()) {
            require(field.origin == FieldOrigin.USER && !field.userLocked)
        } else if (field.origin == FieldOrigin.USER) {
            require(field.userLocked)
        } else {
            require(role && !field.userLocked)
        }
    }
    private fun validate(edits: ArchivedSetupEdits) {
        require(edits.storedRevision >= 0)
        validateField(edits.name, 60)
        validateField(edits.purpose, 8000)
        validateField(edits.role, 160, role = true)
        if (edits.role.origin == FieldOrigin.TEMPLATE) {
            require(edits.template != null && LocalSetupTemplates.matches(edits.template, edits.role.value))
        } else require(edits.template == null)
    }
    fun encode(edits: ArchivedSetupEdits): ByteArray {
        validate(edits)
        val bytes = ByteArrayOutputStream()
        DataOutputStream(bytes).use { output ->
            fun text(value: String) {
                val encoded = value.toByteArray(Charsets.UTF_8)
                output.writeInt(encoded.size); output.write(encoded)
            }
            fun field(value: DraftField) {
                output.writeByte(if (value.origin == FieldOrigin.USER) 0 else 1)
                output.writeByte(if (value.userLocked) 1 else 0)
                text(value.value)
            }
            output.writeInt(MAGIC); output.writeInt(VERSION); output.writeLong(edits.storedRevision)
            field(edits.name); field(edits.purpose); field(edits.role)
            output.writeByte(if (edits.template == null) 0 else 1)
            edits.template?.let { text(it.id); output.writeInt(it.version) }
        }
        val payload = bytes.toByteArray()
        require(payload.size + HASH_BYTES <= MAX_BYTES)
        return payload + MessageDigest.getInstance("SHA-256").digest(payload)
    }
    fun decode(bytes: ByteArray): ArchivedSetupEdits {
        require(bytes.size in (16 + 3 * 6 + 1 + HASH_BYTES)..MAX_BYTES)
        // Work on one bounded snapshot even if a caller later mutates its input buffer.
        val snapshot = bytes.copyOf()
        val payload = snapshot.copyOf(snapshot.size - HASH_BYTES)
        require(MessageDigest.isEqual(MessageDigest.getInstance("SHA-256").digest(payload),
            snapshot.copyOfRange(payload.size, snapshot.size))) { "草稿校验失败" }
        try {
            DataInputStream(ByteArrayInputStream(payload)).use { input ->
                fun flag(): Int = input.readUnsignedByte().also { require(it in 0..1) }
                fun text(maxUnits: Int): String {
                    val length = input.readInt()
                    require(length in 0..(maxUnits * 3) && length <= input.available())
                    val encoded = ByteArray(length).also { input.readFully(it) }
                    return Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                        .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(encoded)).toString()
                }
                fun field(max: Int): DraftField {
                    val origin = if (flag() == 0) FieldOrigin.USER else FieldOrigin.TEMPLATE
                    val locked = flag() == 1
                    return DraftField(text(max), origin, 0, locked)
                }
                require(input.readInt() == MAGIC && input.readInt() == VERSION) { "不支持的草稿格式" }
                val storedRevision = input.readLong()
                val name = field(60); val purpose = field(8000); val role = field(160)
                val template = if (flag() == 1) TemplateSource(text(64), input.readInt()) else null
                require(input.available() == 0) { "草稿包含未知字段或尾随内容" }
                return ArchivedSetupEdits(storedRevision, name, purpose, role, template).also(::validate)
            }
        } catch (failure: IllegalArgumentException) {
            throw failure
        } catch (failure: Exception) {
            throw IllegalArgumentException("草稿残缺或编码无效", failure)
        }
    }
}
