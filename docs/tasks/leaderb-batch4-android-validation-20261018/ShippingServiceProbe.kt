package muyon.shippingverification

import com.mightyoung.muyon.androidbridge.*
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest

/** Exercises the generated shipping Object on Linux. No Android platform claim. */
object ShippingServiceProbe {
    private fun expect(value: Boolean, name: String) = check(value) { "SERVICE_SHIPPING_ASSERT:$name" }
    private fun hash(path: Path) = MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(path))
        .joinToString("") { "%02x".format(it.toInt() and 255) }
    private fun tree(root: Path): Map<String, String> = Files.walk(root).use { paths ->
        paths.filter { Files.isRegularFile(it) }.toList().associate { root.relativize(it).toString() to hash(it) }
    }
    private fun metadata(meta: AgentReplyMeta, source: String, epoch: String? = null) {
        expect(meta.protocol == 1u && meta.buildIdentity == source, "source_protocol")
        expect(meta.serviceEpoch.matches(Regex("[0-9a-f]{32}")) && meta.serverSnapshotRevision >= 0, "metadata_shape")
        if (epoch != null) expect(meta.serviceEpoch == epoch, "epoch_correlation")
    }
    private fun connect(c: AgentServiceController, source: String): AgentClientRef {
        val initialized = c.awaitSettled()
        metadata(initialized.meta, source)
        val ready = initialized.outcome as? AgentSnapshotOutcome.Snapshot
        expect(ready?.serviceState == AgentServiceState.READY, "joined_ready")
        val connection = c.connect(AgentConnectRequest(1u, "b".repeat(32)))
        metadata(connection.meta, source, initialized.meta.serviceEpoch)
        val lease = connection.outcome as? AgentConnectOutcome.Connected
        expect(lease != null && lease.serviceState == AgentServiceState.READY, "real_client_lease")
        return AgentClientRef(1u, connection.meta.serviceEpoch, checkNotNull(lease).clientLease)
    }
    private fun retire(c: AgentServiceController, work: Path) {
        try {
            val close = c.retireService()
            expect(close.outcome == AgentCloseOutcome.Closing || close.outcome == AgentCloseOutcome.Closed, "retire_requested")
            val contenderRoot = Files.createTempDirectory(work, "slot-contender-").toRealPath()
            val contender = runCatching { AgentServiceController(AgentServiceConfig(1u, contenderRoot.toString())) }
            contender.getOrNull()?.let { unexpected ->
                unexpected.retireService(); unexpected.awaitSettled(); unexpected.destroy()
            }
            expect(contender.exceptionOrNull() is AgentServiceSetupException.Busy, "slot_held_until_join")
            val closed = c.awaitSettled().outcome as? AgentSnapshotOutcome.Snapshot
            expect(closed?.serviceState == AgentServiceState.CLOSED, "joined_closed")
            expect(c.retireService().outcome == AgentCloseOutcome.Closed, "retire_idempotent")
        } finally { c.destroy() }
    }
    @JvmStatic fun main(args: Array<String>) {
        expect(args.size == 3, "args")
        val source = args[0]
        expect(source.matches(Regex("[0-9a-f]{40}")), "source_shape")
        val library = Path.of(args[1]).toRealPath()
        val work = Path.of(args[2]).toRealPath()
        System.setProperty("uniffi.component.muyon_android_contract_bridge.libraryOverride", library.toString())
        expect(System.getProperty("os.name") == "Linux", "linux_only")
        val bridge = bridgeInfo()
        expect(bridge.buildIdentity == source && bridge.protocol == 1u, "real_handshake")
        expect(Files.readString(Path.of("/proc/self/maps")).contains(library.toString()), "real_mapped_library")
        println("SERVICE_SHIPPING_MAPPED source=$source sha256=${hash(library)}")
        val records = mutableListOf<String>()
        for (variant in AgentReadVariant.entries) {
            val root = Files.createTempDirectory(work, "root-${variant.name.lowercase()}-").toRealPath()
            val controller = AgentServiceController(AgentServiceConfig(1u, root.toString()))
            var original: AgentRunSummary? = null
            try {
                val client = connect(controller, source)
                val hidden = controller.startRun(AgentStartRequest(client, "read_1", variant)).outcome as? AgentStartOutcome.Rejected
                expect(hidden?.error == AgentServiceError.CLIENT_NOT_VISIBLE, "hidden_client_rejected")
                val stale = AgentClientRef(1u, if (client.expectedServiceEpoch == "0".repeat(32)) "1".repeat(32) else "0".repeat(32), client.clientLease)
                val staleCurrent = controller.current(stale).outcome as? AgentSnapshotOutcome.Rejected
                expect(staleCurrent?.error == AgentServiceError.EPOCH_MISMATCH, "stale_epoch_rejected")
                val wrongLease = AgentClientRef(1u, client.expectedServiceEpoch, if (client.clientLease == "0".repeat(32)) "1".repeat(32) else "0".repeat(32))
                val absent = controller.current(wrongLease).outcome as? AgentSnapshotOutcome.Rejected
                expect(absent?.error == AgentServiceError.CLIENT_UNAVAILABLE, "unknown_lease_rejected")
                expect(controller.setVisibility(AgentVisibilityRequest(client, 1L, true)).outcome == AgentControlOutcome.Applied, "visible_applied")
                val start = controller.startRun(AgentStartRequest(client, "read_1", variant))
                metadata(start.meta, source, client.expectedServiceEpoch)
                expect(start.outcome is AgentStartOutcome.QueuedVolatile, "actual_admission")
                val joined = controller.awaitSettled()
                metadata(joined.meta, source, client.expectedServiceEpoch)
                val snapshot = joined.outcome as? AgentSnapshotOutcome.Snapshot
                val summary = (snapshot?.run as? AgentRunSnapshot.Terminal)?.summary
                expect(snapshot?.serviceState == AgentServiceState.READY && summary != null, "joined_terminal")
                val done = checkNotNull(summary)
                expect(done.terminal == AgentTerminal.COMPLETED && done.reason == AgentReason.NONE, "completed_read")
                expect(done.requestId == "read_1" && done.variant == variant && done.sourceBuildIdentity == source, "intent_binding")
                expect(done.identity.admittedServiceEpoch == client.expectedServiceEpoch && done.identity.actualTask != null, "actual_task_binding")
                expect(done.receipt.outcome == AgentReceiptOutcome.RECORDED_SUCCESS && done.receipt.opaqueId != null, "original_success_receipt")
                val before = tree(root)
                val again = controller.startRun(AgentStartRequest(client, "read_1", variant)).outcome as? AgentStartOutcome.Existing
                expect(again?.snapshot == snapshot.run, "duplicate_is_existing")
                val sibling = AgentReadVariant.entries.first { it != variant }
                val conflict = controller.startRun(AgentStartRequest(client, "read_1", sibling)).outcome as? AgentStartOutcome.Rejected
                expect(conflict?.error == AgentServiceError.REQUEST_CONFLICT, "changed_variant_conflicts")
                val run = AgentRunRef("read_1", variant, done.identity.runId)
                expect(controller.status(AgentStatusRequest(client, run)) == joined, "status_no_replay")
                expect(controller.lookup(AgentLookupRequest(client, AgentLookupKey.RequestId("read_1"))) == joined, "request_lookup_no_replay")
                expect(controller.lookup(AgentLookupRequest(client, AgentLookupKey.RunId(done.identity.runId))) == joined, "run_lookup_no_replay")
                expect(controller.current(client) == joined && tree(root) == before, "reconciliation_bytes_unchanged")
                records += listOf(variant.name, root.toString(), done.identity.runId, client.expectedServiceEpoch,
                    done.identity.actualTask!!.taskId, done.identity.actualTask!!.attemptId, done.receipt.opaqueId!!).joinToString("\t")
                original = done
            } finally { retire(controller, work) }
            val beforeRestore = tree(root)
            val restored = AgentServiceController(AgentServiceConfig(1u, root.toString()))
            try {
                val freshClient = connect(restored, source)
                val done = checkNotNull(original)
                expect(freshClient.expectedServiceEpoch != done.identity.admittedServiceEpoch, "restored_new_epoch")
                val looked = restored.lookup(AgentLookupRequest(freshClient, AgentLookupKey.RequestId("read_1"))).outcome as? AgentSnapshotOutcome.Snapshot
                expect((looked?.run as? AgentRunSnapshot.Terminal)?.summary == done, "restore_original_terminal")
                expect(tree(root) == beforeRestore, "restore_no_execution_bytes")
            } finally { retire(restored, work) }
            println("SERVICE_SHIPPING_PASS variant=${variant.name} completed_original_receipt_dedup_epoch_visibility_restore")
        }
        Files.write(work.resolve("runs.tsv"), records)
        println("SERVICE_SHIPPING_ALL_PASS variants=4 Android_ART_Binder_UID_fsync_kill_rebind=NOT_RUN")
    }
}
