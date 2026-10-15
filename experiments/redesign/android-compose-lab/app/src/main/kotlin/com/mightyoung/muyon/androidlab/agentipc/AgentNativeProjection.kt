package com.mightyoung.muyon.androidlab.agentipc

import com.mightyoung.muyon.androidbridge.*
import com.mightyoung.muyon.androidlab.*

/** One-to-one projection of actual generated records. Kotlin does not decide run outcomes. */
private fun AgentReplyMeta.ui()=UiAgentMeta(protocol,buildIdentity,serviceEpoch,serverSnapshotRevision)
private fun AgentServiceState.ui()=UiAgentServicePhase.valueOf(name)
private fun AgentServiceError.ui()=UiAgentError.valueOf(name)
private fun AgentIntentBinding.ui()=UiAgentIntent(requestId,UiAgentVariant.valueOf(variant.name),sourceBuildIdentity)
private fun AgentRunIdentity.ui()=UiAgentRunIdentity(runId,admittedServiceEpoch,actualTask?.let{UiAgentTask(it.taskId,it.attemptId)})
private fun AgentReceiptSummary.ui()=UiAgentReceipt(opaqueId,UiAgentReceiptOutcome.valueOf(outcome.name))
private fun AgentRunSnapshot.ui():UiAgentRun=when(this) {
    is AgentRunSnapshot.QueuedVolatile -> UiAgentRun.Queued(intent.ui())
    is AgentRunSnapshot.DurablyAdmitted -> UiAgentRun.Admitted(run.intent.ui(),run.identity.ui())
    is AgentRunSnapshot.Running -> UiAgentRun.Running(run.intent.ui(),run.identity.ui())
    is AgentRunSnapshot.Terminal -> with(summary){UiAgentRun.Terminal(UiAgentSummary(UiAgentIntent(requestId,UiAgentVariant.valueOf(variant.name),sourceBuildIdentity),identity.ui(),UiAgentTerminal.valueOf(terminal.name),UiAgentReason.valueOf(reason.name),receipt.ui()))}
    is AgentRunSnapshot.SettledNoAdmission -> UiAgentRun.SettledNoAdmission(settlement.intent.ui(),UiAgentNoAdmissionReason.valueOf(settlement.reason.name))
    is AgentRunSnapshot.Unresolved -> UiAgentRun.Unresolved(observation.intent.ui(),observation.identity?.ui(),observation.receipt.ui())
}
internal fun projectAgentReply(reply:AgentConnectReply):UiAgentWireReply=when(val o=reply.outcome){
    is AgentConnectOutcome.Connected -> UiAgentWireReply.Connected(reply.meta.ui(),UiAgentClientRef(reply.meta.serviceEpoch,o.clientLease),o.serviceState.ui())
    AgentConnectOutcome.Busy -> UiAgentWireReply.Busy(reply.meta.ui())
    is AgentConnectOutcome.Rejected -> UiAgentWireReply.Rejected(reply.meta.ui(),o.error.ui())
}
internal fun projectAgentReply(reply:AgentSnapshotReply):UiAgentWireReply=when(val o=reply.outcome){
    is AgentSnapshotOutcome.Snapshot -> UiAgentWireReply.Snapshot(UiAgentSnapshot(reply.meta.ui(),o.serviceState.ui(),o.run?.ui()))
    AgentSnapshotOutcome.Unresolved -> UiAgentWireReply.Unresolved(reply.meta.ui())
    is AgentSnapshotOutcome.Rejected -> UiAgentWireReply.Rejected(reply.meta.ui(),o.error.ui())
}
internal fun projectAgentReply(reply:AgentStartReply):UiAgentWireReply=when(val o=reply.outcome){
    is AgentStartOutcome.QueuedVolatile -> UiAgentWireReply.Started(reply.meta.ui(),o.snapshot.ui(),false)
    is AgentStartOutcome.Existing -> UiAgentWireReply.Started(reply.meta.ui(),o.snapshot.ui(),true)
    AgentStartOutcome.Busy -> UiAgentWireReply.Busy(reply.meta.ui())
    is AgentStartOutcome.Rejected -> UiAgentWireReply.Rejected(reply.meta.ui(),o.error.ui())
}
internal fun projectAgentReply(reply:AgentControlReply):UiAgentWireReply=when(val o=reply.outcome){
    AgentControlOutcome.Applied -> UiAgentWireReply.Ack(reply.meta.ui(),UiAgentAck.APPLIED)
    AgentControlOutcome.Requested -> UiAgentWireReply.Ack(reply.meta.ui(),UiAgentAck.REQUESTED)
    AgentControlOutcome.AlreadyTerminal -> UiAgentWireReply.Ack(reply.meta.ui(),UiAgentAck.ALREADY_TERMINAL)
    AgentControlOutcome.NotRunning -> UiAgentWireReply.Ack(reply.meta.ui(),UiAgentAck.NOT_RUNNING)
    AgentControlOutcome.NotActive -> UiAgentWireReply.Ack(reply.meta.ui(),UiAgentAck.NOT_ACTIVE)
    is AgentControlOutcome.Rejected -> UiAgentWireReply.Rejected(reply.meta.ui(),o.error.ui())
}
internal fun projectAgentReply(reply:AgentCloseReply):UiAgentWireReply=when(val o=reply.outcome){
    AgentCloseOutcome.Closing -> UiAgentWireReply.Ack(reply.meta.ui(),UiAgentAck.CLOSING)
    AgentCloseOutcome.Closed -> UiAgentWireReply.Ack(reply.meta.ui(),UiAgentAck.CLOSED)
    is AgentCloseOutcome.Rejected -> UiAgentWireReply.Rejected(reply.meta.ui(),o.error.ui())
}


/** Correlation only; this seam never decides native cancellation or a business outcome. */
internal fun agentControlRunId(run:UiAgentRun?,selected:UiAgentIntent?):String? = when(run) {
    is UiAgentRun.Admitted -> run.identity
    is UiAgentRun.Running -> run.identity
    is UiAgentRun.Terminal -> run.summary.identity
    is UiAgentRun.Unresolved -> run.identity
    else -> null
}?.runId
