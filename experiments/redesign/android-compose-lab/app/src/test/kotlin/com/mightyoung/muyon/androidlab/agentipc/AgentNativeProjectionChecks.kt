package com.mightyoung.muyon.androidlab.agentipc

import com.mightyoung.muyon.androidbridge.*
import com.mightyoung.muyon.androidlab.*

/** Can run against fresh actual JVM-profile generated records. Never constructs a controller. */
fun main() {
    val m=AgentReplyMeta(1u,"a".repeat(40),"b".repeat(32),9)
    val i=AgentIntentBinding("original",AgentReadVariant.EQUIPMENT,"c".repeat(40))
    val identity=AgentRunIdentity("d".repeat(32),"e".repeat(32),AgentTaskIdentity("t-4231-1792012800000000000","a-4231-1792012800000000000"))
    val cases=linkedMapOf<String,()->Unit>()
    cases["connect preserves actual phase and native metadata"]={val r=projectAgentReply(AgentConnectReply(m,AgentConnectOutcome.Connected("f".repeat(32),AgentServiceState.CLOSED))) as UiAgentWireReply.Connected;check(r.phase==UiAgentServicePhase.CLOSED && r.meta.revision==9L && r.client.epoch==m.serviceEpoch);check(projectAgentReply(AgentConnectReply(m,AgentConnectOutcome.Busy)) is UiAgentWireReply.Busy)}
    cases["cancelled terminal retains original task and recorded receipt success"]={val summary=AgentRunSummary(i.requestId,i.variant,i.sourceBuildIdentity,identity,AgentTerminal.CANCELLED,AgentReason.CANCELLED,AgentReceiptSummary("receipt-1",AgentReceiptOutcome.RECORDED_SUCCESS));val r=projectAgentReply(AgentSnapshotReply(m,AgentSnapshotOutcome.Snapshot(AgentServiceState.CLOSED,AgentRunSnapshot.Terminal(summary)))) as UiAgentWireReply.Snapshot;val terminal=r.value.run as UiAgentRun.Terminal;check(terminal.summary.terminal==UiAgentTerminal.CANCELLED && terminal.summary.receipt.outcome==UiAgentReceiptOutcome.RECORDED_SUCCESS);check(terminal.intent.sourceBuildIdentity==i.sourceBuildIdentity && terminal.summary.identity.admittedEpoch==identity.admittedServiceEpoch && terminal.summary.identity.actualTask==UiAgentTask("t-4231-1792012800000000000","a-4231-1792012800000000000"))}
    cases["settled no admission stays sealed without synthetic identities"]={val r=projectAgentReply(AgentSnapshotReply(m,AgentSnapshotOutcome.Snapshot(AgentServiceState.CLOSING,AgentRunSnapshot.SettledNoAdmission(AgentNoAdmissionSettlement(i,AgentNoAdmissionReason.QUOTA_EXCEEDED))))) as UiAgentWireReply.Snapshot;check(r.value.run==UiAgentRun.SettledNoAdmission(UiAgentIntent(i.requestId,UiAgentVariant.EQUIPMENT,i.sourceBuildIdentity),UiAgentNoAdmissionReason.QUOTA_EXCEEDED))}
    cases["requested control and close remain acknowledgements not business terminals"]={check(projectAgentReply(AgentControlReply(m,AgentControlOutcome.Requested))==UiAgentWireReply.Ack(UiAgentMeta(1u,m.buildIdentity,m.serviceEpoch,9),UiAgentAck.REQUESTED));check(projectAgentReply(AgentCloseReply(m,AgentCloseOutcome.Closing)) is UiAgentWireReply.Ack);check(projectAgentReply(AgentSnapshotReply(m,AgentSnapshotOutcome.Unresolved)) is UiAgentWireReply.Unresolved)}
    cases["start existing preserves original native run and rejected unit"]={val run=AgentRunSnapshot.QueuedVolatile(i);val r=projectAgentReply(AgentStartReply(m,AgentStartOutcome.Existing(run))) as UiAgentWireReply.Started;check(r.existing && r.run.intent.requestId==i.requestId);check(projectAgentReply(AgentStartReply(m,AgentStartOutcome.Rejected(AgentServiceError.REQUEST_CONFLICT))) is UiAgentWireReply.Rejected)}
    cases.forEach{(name,test)->test();println("PASS B generated projection $name")}
    println("${cases.size}/${cases.size} B generated projection checks passed; metadata only, Android runtime NOT_RUN")
}
