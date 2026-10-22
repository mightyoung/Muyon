package com.mightyoung.muyon.product.chat.persistence

import java.nio.file.Files
import java.nio.file.Path
import org.json.JSONObject
import com.mightyoung.muyon.product.agents.setup.BotSetupDraft

private val ownerA = DraftStoreOwner("synthetic-account-a", "workspace", "conversation", "project")
private val draftId = "cfd9db13-78ca-4004-bdd7-e822117bf730"
private fun archive(revision: Long, name: String = "草稿"): ByteArray {
    val draft = BotSetupDraft("synthetic-scope", draftId)
    draft.editName(name); draft.editPurpose("合成测试"); draft.editRole("本地角色")
    return draft.exportDraft(revision, draft.snapshot().revision)
}

fun main(args: Array<String>) {
    if (args.isNotEmpty()) {
        val stage = args.getOrNull(2)
        val store = HostDraftStore(Path.of(args[1])) { point ->
            if (point.name == stage) Runtime.getRuntime().halt(31)
        }
        val result = store.save(ownerA, draftId, args.getOrNull(3)?.toLong() ?: 1L, 3, archive((args.getOrNull(3)?.toLong() ?: 1L) + 1, "child"))
        if (args[0] == "race") println(if (result is DraftStoreWrite.Committed) "committed" else "conflict")
        return
    }
    val root = Files.createTempDirectory("muyon-draft-store-test")
    fun store() = HostDraftStore(root)
    fun found(): DraftStoreRecord = (store().read(ownerA, draftId, null) as DraftStoreRead.Found).record
    fun child(mode: String, stage: String = "", expected: Long = 1): Process = ProcessBuilder(
        System.getProperty("java.home") + "/bin/java", "-cp", System.getProperty("java.class.path"),
        "com.mightyoung.muyon.product.chat.persistence.HostDraftStoreChecksKt", mode, root.toString(), stage, expected.toString()
    ).redirectErrorStream(true).start()
    try {
        check(HostDraftStore(root.resolve("absent")).save(ownerA, draftId, null, 3, archive(1)) is DraftStoreWrite.Rejected)
        check(!Files.exists(root.resolve("absent")))
        check(store().read(ownerA, draftId, null) is DraftStoreRead.Missing)
        check(store().read(ownerA, draftId, 0) is DraftStoreRead.Rejected) // real anchored0 is not an absence sentinel
        val first = store().save(ownerA, draftId, null, 3, archive(1)) as DraftStoreWrite.Committed
        check(first.receipt.exportedMemoryRevision == 3L)
        check(first.receipt.storedRevision == 1L && found().archive.contentEquals(archive(1)))
        check(store().save(ownerA, draftId, null, 3, archive(1)) is DraftStoreWrite.Rejected)
        check(store().save(ownerA, draftId, 0, 3, archive(1)) is DraftStoreWrite.Rejected)
        check(store().read(ownerA.copy(accountId = "synthetic-other"), draftId, null) is DraftStoreRead.Missing)
        check(store().save(ownerA, draftId, 1, 3, ByteArray(32769)) is DraftStoreWrite.Rejected)
        check(found().storedRevision == 1L)
        // Two actual JVMs compete using the same displayed stored revision.
        val p1 = child("race"); val p2 = child("race")
        val lines = listOf(p1.inputStream.bufferedReader().readText().trim(), p2.inputStream.bufferedReader().readText().trim())
        check(p1.waitFor() == 0 && p2.waitFor() == 0)
        check(lines.sorted() == listOf("committed", "conflict")) { lines.toString() }
        check(found().storedRevision == 2L)
        check(store().recoverReceipt(first.receipt, 2) is DraftStoreWrite.Rejected) // newer is not original
        val current = found()
        check(store().recoverReceipt(current.receipt(), 2) is DraftStoreWrite.Committed)
        // A failed write before publication cannot report saved or change the old record.
        val writeFailure = HostDraftStore(root) { if (it == DraftStoreStage.BEFORE_TEMP_WRITE) throw java.io.IOException("synthetic") }
        check(writeFailure.save(ownerA, draftId, 2, 3, archive(3)) is DraftStoreWrite.Rejected)
        check(found().storedRevision == 2L)
        val before = HostDraftStore(root) { if (it == DraftStoreStage.BEFORE_MOVE) throw java.io.IOException("synthetic") }
        check(before.save(ownerA, draftId, 2, 3, archive(3)) is DraftStoreWrite.Rejected)
        check(found().storedRevision == 2L)
        val after = HostDraftStore(root) { if (it == DraftStoreStage.AFTER_MOVE) throw java.io.IOException("synthetic") }
        val uncertain = after.save(ownerA, draftId, 2, 3, archive(3)) as DraftStoreWrite.Unknown
        check(uncertain.attempt.storedRevision == 3L)
        check(store().recoverReceipt(uncertain.attempt, 3) is DraftStoreWrite.Committed)
        val path = Files.list(root).use { it.filter { item -> item.fileName.toString().endsWith(".json") }.findFirst().orElseThrow() }
        val original = Files.readString(path)
        Files.writeString(path, original + "garbage")
        check(store().read(ownerA, draftId, null) is DraftStoreRead.Rejected)
        Files.writeString(path, original + "\u0000garbage")
        check(store().read(ownerA, draftId, null) is DraftStoreRead.Rejected)
        Files.writeString(path, original + "{}")
        check(store().read(ownerA, draftId, null) is DraftStoreRead.Rejected)
        Files.writeString(path, "broken")
        check(store().read(ownerA, draftId, null) is DraftStoreRead.Rejected)
        check(store().save(ownerA, draftId, 3, 3, archive(4)) is DraftStoreWrite.Rejected)
        Files.writeString(path, JSONObject(original).put("schema_version", 0).toString())
        check(store().read(ownerA, draftId, null) is DraftStoreRead.Rejected)
        Files.writeString(path, JSONObject(original).put("creation_intent", "forbidden").toString())
        check(store().read(ownerA, draftId, null) is DraftStoreRead.Rejected)
        val wrongOwner = JSONObject(original)
        wrongOwner.getJSONObject("owner").put("account_id", "other")
        Files.writeString(path, wrongOwner.toString())
        check(store().read(ownerA, draftId, null) is DraftStoreRead.Rejected)
        Files.writeString(path, "x".repeat(65537))
        check(store().read(ownerA, draftId, null) is DraftStoreRead.Rejected)
        fun frame(revision: Long): String {
            val json = JSONObject().put("schema_version", 1).put("owner", JSONObject().put("account_id", ownerA.accountId).put("workspace_id", ownerA.workspaceId)
                .put("conversation_id", ownerA.conversationId).put("project_id", ownerA.projectId)).put("draft_id", draftId).put("stored_revision", revision)
                .put("archive_base64", java.util.Base64.getEncoder().encodeToString(archive(revision)))
            val digest = java.security.MessageDigest.getInstance("SHA-256").digest(json.toString().toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
            return json.put("digest", digest).toString()
        }
        Files.writeString(path, frame(1))
        check(found().storedRevision == 1L) // structurally valid old archive, not just corruption
        check(store().read(ownerA, draftId, 3) is DraftStoreRead.Rejected)
        check(store().save(ownerA, draftId, 3, 3, archive(4)) is DraftStoreWrite.Rejected)
        Files.writeString(path, frame(0))
        check(found().storedRevision == 0L)
        Files.writeString(path, frame(Long.MAX_VALUE))
        check(found().storedRevision == Long.MAX_VALUE)
        check((store().save(ownerA, draftId, Long.MAX_VALUE, 3, archive(Long.MAX_VALUE)) as DraftStoreWrite.Rejected).code == "draft_revision_exhausted")
        check(found().storedRevision == Long.MAX_VALUE)
        Files.writeString(path, original)
        check(found().storedRevision == 3L)
        // Process death before atomic publication leaves the previous committed bytes intact.
        val crash = child("crash", "BEFORE_MOVE", 3)
        check(crash.waitFor() == 31)
        check(found().storedRevision == 3L)
        val crashAfter = child("crash", "AFTER_MOVE", 3)
        check(crashAfter.waitFor() == 31)
        check(found().storedRevision == 4L && BotSetupDraft.restoreDraft(found().archive, "synthetic-current-owner", draftId).draft.snapshot().name.value == "child")
        check(store().recoverReceipt(found().receipt(), 4) is DraftStoreWrite.Committed)
        check(!original.contains("credential") && !original.contains("intent") && !original.contains("session"))
        println("PASS draft store: restart/OS-process CAS/wrong owner/disk fault/unknown exact receipt/corrupt/schema/bounds/no authority fields")
    } finally { Files.walk(root).use { it.sorted(Comparator.reverseOrder()).forEach(Files::deleteIfExists) } }
}
