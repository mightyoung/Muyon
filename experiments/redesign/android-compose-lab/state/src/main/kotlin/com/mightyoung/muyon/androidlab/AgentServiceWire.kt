package com.mightyoung.muyon.androidlab

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException

/** Private, closed IPC projection. No dynamic operation, business body or native objects. */
enum class UiAgentLocalStatus { INITIALIZING, UNAVAILABLE, BUSY, INVALID_REQUEST }
enum class UiAgentError { UNSUPPORTED_PROTOCOL, INVALID_ROOT, INVALID_REQUEST_ID, INVALID_IDENTITY, INVALID_GENERATION, EPOCH_MISMATCH, CLIENT_UNAVAILABLE, CLIENT_NOT_VISIBLE, REQUEST_CONFLICT, BUSY, CLOSED, TARGET_UNAVAILABLE, RECOVERY_REQUIRED, BUDGET_EXCEEDED, INTERNAL_FAILURE }
enum class UiAgentAck { APPLIED, REQUESTED, ALREADY_TERMINAL, NOT_RUNNING, NOT_ACTIVE, CLOSING, CLOSED }
sealed interface UiAgentWireReply {
    data class Local(val status: UiAgentLocalStatus): UiAgentWireReply
    data class Connected(val meta: UiAgentMeta, val client: UiAgentClientRef, val phase: UiAgentServicePhase): UiAgentWireReply
    data class Snapshot(val value: UiAgentSnapshot): UiAgentWireReply
    data class Started(val meta: UiAgentMeta, val run: UiAgentRun, val existing: Boolean): UiAgentWireReply
    data class Ack(val meta: UiAgentMeta, val value: UiAgentAck): UiAgentWireReply
    data class Rejected(val meta: UiAgentMeta, val error: UiAgentError): UiAgentWireReply
    data class Unresolved(val meta: UiAgentMeta): UiAgentWireReply
    data class Busy(val meta: UiAgentMeta): UiAgentWireReply
}
object AgentServiceWire {
    const val MAX_PAYLOAD_BYTES = 7680 // Actual Android Parcel including overhead is separately capped at 8KiB.
    private const val MAGIC = 0x4d594131
    private const val VERSION = 1
    fun encode(reply: UiAgentWireReply, expectedBuild: String): ByteArray? {
        if (!valid(reply, expectedBuild)) return null
        return try {
            val buffer = ByteArrayOutputStream()
            DataOutputStream(buffer).use { out ->
                out.writeInt(MAGIC); out.writeByte(VERSION)
                when (reply) {
                    is UiAgentWireReply.Local -> { out.writeByte(0); out.word(reply.status.name) }
                    is UiAgentWireReply.Connected -> { out.writeByte(1); out.meta(reply.meta); out.word(reply.client.epoch); out.word(reply.client.lease); out.word(reply.phase.name) }
                    is UiAgentWireReply.Snapshot -> { out.writeByte(2); out.meta(reply.value.meta); out.word(reply.value.phase.name); out.run(reply.value.run) }
                    is UiAgentWireReply.Started -> { out.writeByte(3); out.meta(reply.meta); out.writeBoolean(reply.existing); out.run(reply.run) }
                    is UiAgentWireReply.Ack -> { out.writeByte(4); out.meta(reply.meta); out.word(reply.value.name) }
                    is UiAgentWireReply.Rejected -> { out.writeByte(5); out.meta(reply.meta); out.word(reply.error.name) }
                    is UiAgentWireReply.Unresolved -> { out.writeByte(6); out.meta(reply.meta) }
                    is UiAgentWireReply.Busy -> { out.writeByte(7); out.meta(reply.meta) }
                }
            }
            buffer.toByteArray().takeIf { it.size <= MAX_PAYLOAD_BYTES }
        } catch (_: IllegalArgumentException) { null }
    }
    fun decode(bytes: ByteArray, expectedBuild: String): UiAgentWireReply? {
        if (bytes.size > MAX_PAYLOAD_BYTES) return null
        return try {
            val input = DataInputStream(ByteArrayInputStream(bytes))
            if (input.readInt() != MAGIC || input.readUnsignedByte() != VERSION) return null
            val reply = when (input.readUnsignedByte()) {
                0 -> UiAgentWireReply.Local(enumValueOf(input.word()))
                1 -> { val m=input.meta(); UiAgentWireReply.Connected(m,UiAgentClientRef(input.word(),input.word()),enumValueOf(input.word())) }
                2 -> { val m=input.meta(); val phase=enumValueOf<UiAgentServicePhase>(input.word()); UiAgentWireReply.Snapshot(UiAgentSnapshot(m,phase,input.run())) }
                3 -> { val m=input.meta(); val existing=input.flag(); UiAgentWireReply.Started(m,input.run() ?: return null,existing) }
                4 -> UiAgentWireReply.Ack(input.meta(),enumValueOf(input.word()))
                5 -> UiAgentWireReply.Rejected(input.meta(),enumValueOf(input.word()))
                6 -> UiAgentWireReply.Unresolved(input.meta())
                7 -> UiAgentWireReply.Busy(input.meta())
                else -> return null
            }
            reply.takeIf { input.available()==0 && valid(it,expectedBuild) }
        } catch (_: IOException) { null } catch (_: IllegalArgumentException) { null }
    }
    private fun valid(reply: UiAgentWireReply, build: String): Boolean {
        fun meta(m:UiAgentMeta)=validAgentSnapshot(UiAgentSnapshot(m,UiAgentServicePhase.INITIALIZING,null),build)
        return when(reply) {
            is UiAgentWireReply.Local -> true
            is UiAgentWireReply.Connected -> meta(reply.meta) && reply.client.epoch==reply.meta.serviceEpoch && Regex("[0-9a-f]{32}").matches(reply.client.lease)
            is UiAgentWireReply.Snapshot -> validAgentSnapshot(reply.value,build)
            is UiAgentWireReply.Started -> validAgentSnapshot(UiAgentSnapshot(reply.meta,UiAgentServicePhase.INITIALIZING,reply.run),build) && (reply.existing || reply.run is UiAgentRun.Queued)
            is UiAgentWireReply.Ack -> meta(reply.meta)
            is UiAgentWireReply.Rejected -> meta(reply.meta)
            is UiAgentWireReply.Unresolved -> meta(reply.meta)
            is UiAgentWireReply.Busy -> meta(reply.meta)
        }
    }
    private fun DataOutputStream.word(value:String) { require(value.length<=128 && value.all { it.code in 0x20..0x7e }); writeUTF(value) }
    private fun DataInputStream.word():String = readUTF().also { require(it.length<=128 && it.all { ch -> ch.code in 0x20..0x7e }) }
    private fun DataInputStream.flag():Boolean = when(readUnsignedByte()) { 0 -> false; 1 -> true; else -> throw IllegalArgumentException("invalid_flag") }
    private fun DataOutputStream.meta(m:UiAgentMeta) { writeInt(m.protocol.toInt()); word(m.buildIdentity); word(m.serviceEpoch); writeLong(m.revision) }
    private fun DataInputStream.meta()=UiAgentMeta(readInt().toUInt(),word(),word(),readLong())
    private fun DataOutputStream.intent(i:UiAgentIntent) { word(i.requestId); word(i.variant.name); word(i.sourceBuildIdentity) }
    private fun DataInputStream.intent()=UiAgentIntent(word(),enumValueOf(word()),word())
    private fun DataOutputStream.identity(i:UiAgentRunIdentity) { word(i.runId);word(i.admittedEpoch);writeBoolean(i.actualTask!=null);i.actualTask?.let { word(it.taskId);word(it.attemptId) } }
    private fun DataInputStream.identity()=UiAgentRunIdentity(word(),word(),if(flag())UiAgentTask(word(),word()) else null)
    private fun DataOutputStream.receipt(r:UiAgentReceipt) { writeBoolean(r.opaqueId!=null);r.opaqueId?.let{word(it)};word(r.outcome.name) }
    private fun DataInputStream.receipt()=UiAgentReceipt(if(flag())word() else null,enumValueOf(word()))
    private fun DataOutputStream.run(r:UiAgentRun?) {
        when(r) {
            null -> writeByte(0)
            is UiAgentRun.Queued -> {writeByte(1);intent(r.intent)}
            is UiAgentRun.Admitted -> {writeByte(2);intent(r.intent);identity(r.identity)}
            is UiAgentRun.Running -> {writeByte(3);intent(r.intent);identity(r.identity)}
            is UiAgentRun.Terminal -> {writeByte(4);with(r.summary){intent(intent);identity(identity);word(terminal.name);word(reason.name);receipt(receipt)}}
            is UiAgentRun.SettledNoAdmission -> {writeByte(5);intent(r.intent);word(r.reason.name)}
            is UiAgentRun.Unresolved -> {writeByte(6);intent(r.intent);writeBoolean(r.identity!=null);r.identity?.let{identity(it)};receipt(r.receipt)}
        }
    }
    private fun DataInputStream.run():UiAgentRun? = when(readUnsignedByte()) {
        0 -> null
        1 -> UiAgentRun.Queued(intent())
        2 -> UiAgentRun.Admitted(intent(),identity())
        3 -> UiAgentRun.Running(intent(),identity())
        4 -> UiAgentRun.Terminal(UiAgentSummary(intent(),identity(),enumValueOf(word()),enumValueOf(word()),receipt()))
        5 -> UiAgentRun.SettledNoAdmission(intent(),enumValueOf(word()))
        6 -> UiAgentRun.Unresolved(intent(),if(flag())identity() else null,receipt())
        else -> throw IllegalArgumentException("invalid_shape")
    }
}
