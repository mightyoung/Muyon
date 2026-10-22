package com.mightyoung.muyon.product.agents.setup

import java.nio.ByteBuffer
import java.security.MessageDigest

fun runPersistenceChecks(): Int {
    var passed = 0
    fun test(name: String, body: () -> Unit) { body(); passed++; println("PASS persistence: $name") }
    fun rejects(body: () -> Unit) { check(runCatching(body).exceptionOrNull() is IllegalArgumentException) }
    fun draft() = BotSetupDraft("old-account/project", "original-id").apply {
        editName("论文助手📚"); next(); editPurpose("整理文献"); next(); editRole("用户角色")
    }
    fun encode(d: BotSetupDraft, stored: Long = 9) = d.exportDraft(stored, d.snapshot().revision)
    // Re-signing is deliberate: the checksum detects corruption, semantic validation must also reject bad schema/data.
    fun seal(payload: ByteArray) = payload + MessageDigest.getInstance("SHA-256").digest(payload)
    test("roundtrip preserves edits and locks; host scope and memory CAS start fresh") {
        val d = draft(); d.next(); d.cancel()
        val restored = BotSetupDraft.restoreDraft(encode(d, 900), "new-account/project", "new-id")
        check(restored.storedRevision == 900L)
        val s = restored.draft.snapshot()
        check(s.scope == "new-account/project" && s.draftId == "new-id")
        check(s.revision == 0L && s.name.revision == 0L && s.purpose.revision == 0L && s.role.revision == 0L)
        check(s.step == SetupStep.NAME && !s.cancelled)
        check(s.name.value == "论文助手📚" && s.purpose.value == "整理文献" && s.role.value == "用户角色")
        check(s.name.userLocked && s.purpose.userLocked && s.role.userLocked)
        rejects { restored.draft.exportDraft(901, 900) }
        restored.draft.editName("新名称")
        check(restored.draft.snapshot().revision == 1L)
    }
    test("template origin survives without transient suggestion or capabilities") {
        val d = BotSetupDraft("old", "id").apply {
            editName("文献助手"); next(); editPurpose("文献"); next()
        }
        val token = d.requestSuggestions()
        check(d.receiveSuggestions(token, LocalSetupTemplates.suggest(token)))
        check(d.acceptRoleSuggestion(token))
        val cap = CapabilityOption("paper-overview", "1", true, "ok", "papers", "overview")
        d.offerChoices(listOf(cap), listOf(MaterialOption("private-file", "old", true)))
        d.selectChoices(setOf(cap.id), setOf("private-file"))
        val pending = d.requestSuggestions()
        val bytes = encode(d)
        val restored = BotSetupDraft.restoreDraft(bytes, "new").draft
        check(restored.snapshot().role.origin == FieldOrigin.TEMPLATE && !restored.snapshot().role.userLocked)
        check(restored.snapshot().suggestion == null)
        check(restored.choices().capabilities.isEmpty() && restored.choices().selectedMaterialIds.isEmpty())
        check(!restored.receiveSuggestions(pending, LocalSetupTemplates.suggest(pending)))
        restored.next(); restored.next(); restored.next()
        check(restored.preview().roleTemplateSource == TemplateSource("paper-organizer", 1))
        check(!restored.preview().canCreate && !restored.preview().canStart)
        val raw = bytes.toString(Charsets.ISO_8859_1)
        check("private-file" !in raw && "paper-overview" !in raw && token.requestId !in raw)
    }
    test("empty and partially entered drafts roundtrip") {
        val empty = BotSetupDraft.restoreDraft(encode(BotSetupDraft("s")), "host").draft
        check(empty.snapshot().name.value.isEmpty() && !empty.snapshot().name.userLocked)
        rejects { empty.next() }
        val named = BotSetupDraft("s").apply { editName("仅名称") }
        val restored = BotSetupDraft.restoreDraft(encode(named), "host").draft
        check(restored.snapshot().name.value == "仅名称" && restored.snapshot().purpose.value.isEmpty())
        check(restored.snapshot().creation.status == CreationStatus.NOT_REQUESTED)
    }
    test("export refuses stale CAS, invalid stored revision and all unresolved creation states") {
        val d = draft()
        rejects { d.exportDraft(1, d.snapshot().revision - 1) }
        rejects { encode(d, -1) }
        d.next(); d.observePendingCreation("never-persist-this-intent", d.snapshot().revision)
        rejects { encode(d) }
        d.observeCreationResult("never-persist-this-intent", CreationStatus.UNKNOWN)
        rejects { encode(d) }
        d.observeCreationResult("never-persist-this-intent", CreationStatus.CREATED, "agent-id")
        rejects { encode(d) }
    }
    test("schema, truncation, trailing bytes, checksum damage and oversized input reject") {
        val bytes = encode(draft())
        val payload = bytes.copyOf(bytes.size - 32)
        rejects { BotSetupDraft.restoreDraft(ByteArray(32769), "host") }
        for (size in 0 until bytes.size) rejects { BotSetupDraft.restoreDraft(bytes.copyOf(size), "host") }
        rejects { BotSetupDraft.restoreDraft(bytes + 0, "host") }
        val damaged = bytes.copyOf(); damaged[25] = (damaged[25].toInt() xor 1).toByte()
        rejects { BotSetupDraft.restoreDraft(damaged, "host") }
        val future = payload.copyOf(); ByteBuffer.wrap(future).putInt(4, 2)
        rejects { BotSetupDraft.restoreDraft(seal(future), "host") }
        val negativeRevision = payload.copyOf(); ByteBuffer.wrap(negativeRevision).putLong(8, -1)
        rejects { BotSetupDraft.restoreDraft(seal(negativeRevision), "host") }
        rejects { BotSetupDraft.restoreDraft(seal(payload + 0), "host") }
        rejects { BotSetupDraft.restoreDraft(bytes, " ") }
    }
    test("rechecks semantic limits, flags, template provenance and malformed UTF8") {
        val bytes = encode(draft())
        val payload = bytes.copyOf(bytes.size - 32)
        // Format: magic+schema+storedRevision (16), name origin+lock (2), byte length (4), UTF8.
        for (flag in listOf(2, 255)) {
            val invalid = payload.copyOf(); invalid[17] = flag.toByte()
            rejects { BotSetupDraft.restoreDraft(seal(invalid), "host") }
        }
        val badOrigin = payload.copyOf(); badOrigin[16] = 1
        rejects { BotSetupDraft.restoreDraft(seal(badOrigin), "host") }
        val unlocked = payload.copyOf(); unlocked[17] = 0
        rejects { BotSetupDraft.restoreDraft(seal(unlocked), "host") }
        val badUtf8 = payload.copyOf(); badUtf8[22] = 0xFF.toByte()
        rejects { BotSetupDraft.restoreDraft(seal(badUtf8), "host") }
        val oversize = payload.copyOf(); ByteBuffer.wrap(oversize).putInt(18, Int.MAX_VALUE)
        rejects { BotSetupDraft.restoreDraft(seal(oversize), "host") }
        val badProvenance = payload.copyOf(); badProvenance[badProvenance.lastIndex] = 1
        rejects { BotSetupDraft.restoreDraft(seal(badProvenance), "host") }
    }
    return passed
}
