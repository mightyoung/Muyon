package muyon.bridgechecks

import com.mightyoung.muyon.androidbridge.*
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest

/** Real generated shipping Object invocation; never an Android Binder probe. */
object ServiceProbe {
    private const val requestId = "read_1"
    private const val assertion = "AGENT_SERVICE_JVM_RED: admitted run must complete the registered physical read"

    private fun meta(value: AgentReplyMeta, source: String, epoch: String? = null) {
        check(value.protocol == 1u && value.buildIdentity == source)
        check(value.serviceEpoch.matches(Regex("[0-9a-f]{32}")) && value.serverSnapshotRevision >= 0)
        if (epoch != null) check(value.serviceEpoch == epoch)
    }

    @JvmStatic fun main(args: Array<String>) {
        check(args.size == 4 && args[0] == "service-jvm-red")
        val source = args[1]
        check(source.matches(Regex("[0-9a-f]{40}")))
        val library = Path.of(args[2]).toRealPath()
        val work = Path.of(args[3]).toRealPath()
        System.setProperty("uniffi.component.muyon_android_contract_bridge.libraryOverride", library.toString())
        check(System.getProperty("os.name") == "Linux")
        BridgeProbe.verifyInfo(source)
        check(Files.readString(Path.of("/proc/self/maps")).contains(library.toString()))
        val hash = MessageDigest.getInstance("SHA-256").digest(Files.readAllBytes(library))
            .joinToString("") { "%02x".format(it.toInt() and 255) }
        println("AGENT_SERVICE_JVM_MAPPED source=$source sha256=$hash")
        val privateRoot = Files.createTempDirectory(work, "service-root-").toRealPath()
        val controller = AgentServiceController(AgentServiceConfig(1u, privateRoot.toString()))
        var summary: AgentRunSummary? = null
        try {
            // Same sole backend waiter path used by the Service, before admission.
            val initialized = controller.awaitSettled()
            meta(initialized.meta, source)
            val ready = initialized.outcome as? AgentSnapshotOutcome.Snapshot
            check(ready != null && ready.serviceState == AgentServiceState.INITIALIZING && ready.run == null)
            check(initialized.meta.serverSnapshotRevision == 0L)
            val connected = controller.connect(AgentConnectRequest(1u, "b".repeat(32)))
            meta(connected.meta, source, initialized.meta.serviceEpoch)
            val lease = connected.outcome as? AgentConnectOutcome.Connected
            check(lease != null && lease.serviceState == AgentServiceState.INITIALIZING)
            check(lease.clientLease.matches(Regex("[0-9a-f]{32}")))
            val client = AgentClientRef(1u, connected.meta.serviceEpoch, lease.clientLease)
            val visible = controller.setVisibility(AgentVisibilityRequest(client, 1L, true))
            meta(visible.meta, source, client.expectedServiceEpoch)
            check(visible.outcome == AgentControlOutcome.Applied)
            val started = controller.startRun(AgentStartRequest(client, requestId, AgentReadVariant.EQUIPMENT))
            meta(started.meta, source, client.expectedServiceEpoch)
            val refused = started.outcome as? AgentStartOutcome.Rejected
            val knownRefusal = refused?.error == AgentServiceError.INTERNAL_FAILURE
            check(knownRefusal || started.outcome is AgentStartOutcome.QueuedVolatile) {
                "AGENT_SERVICE_JVM_REACH: known actual controller admission seam"
            }
            val settled = controller.awaitSettled()
            val current = controller.current(client)
            meta(settled.meta, source, client.expectedServiceEpoch)
            meta(current.meta, source, client.expectedServiceEpoch)
            check(current == settled)
            val snapshot = current.outcome as? AgentSnapshotOutcome.Snapshot
            check(snapshot != null)
            summary = (snapshot.run as? AgentRunSnapshot.Terminal)?.summary
            val run = AgentRunRef(requestId, AgentReadVariant.EQUIPMENT, summary?.identity?.runId)
            val status = controller.status(AgentStatusRequest(client, run))
            val looked = controller.lookup(AgentLookupRequest(client, AgentLookupKey.RequestId(requestId)))
            meta(status.meta, source, client.expectedServiceEpoch)
            meta(looked.meta, source, client.expectedServiceEpoch)
            check(status == current && looked == current)
            if (knownRefusal) {
                check(snapshot.serviceState == AgentServiceState.INITIALIZING && snapshot.run == null)
                check(current.meta.serverSnapshotRevision == 0L)
                println("AGENT_SERVICE_JVM_STUB_REACHED request=read_1 code=internal_failure")
            }
        } finally {
            // Keep explicit lifecycle calls reachable even when the positive fails.
            // Stub refusal has no admitted worker; cleanup failure remains INVALID.
            controller.retireService()
            controller.awaitSettled()
            controller.destroy()
        }
        check(summary?.terminal == AgentTerminal.COMPLETED) { assertion }
        val result = checkNotNull(summary)
        check(result.requestId == requestId && result.variant == AgentReadVariant.EQUIPMENT)
        check(result.sourceBuildIdentity == source && result.identity.actualTask != null)
        check(result.receipt.outcome == AgentReceiptOutcome.RECORDED_SUCCESS && result.receipt.opaqueId != null)
        check(result.reason == AgentReason.NONE)
        println("AGENT_SERVICE_JVM_PASS settled_read_summary")
    }
}
