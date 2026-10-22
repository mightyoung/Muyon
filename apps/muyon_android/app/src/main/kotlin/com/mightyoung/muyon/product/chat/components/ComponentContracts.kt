package com.mightyoung.muyon.product.chat.components

import java.security.MessageDigest
import java.util.Collections

/** Host supplied context, never inferred from model text or a display name. */
data class ComponentScope(
    val workspaceId: String, val conversationId: String, val projectId: String?,
    val agentId: String, val generation: Long
) {
    init {
        require(listOfNotNull(workspaceId, conversationId, projectId, agentId).all { it.isNotBlank() && it.length <= 1024 })
        require(generation >= 0)
    }
}

enum class ComponentKind { TEXT, NATIVE_CHOICES, SOURCE_LIST, TASK, RECEIPT }
data class SourceRef(val sourceId: String, val revision: Long, val page: Int)
sealed interface ComponentAction {
    data class LocalEdit(val field: String) : ComponentAction
    data class OpenSource(val source: SourceRef) : ComponentAction
    data class ComposeMessage(val text: String) : ComponentAction
    data object SubmitLocal : ComponentAction
    data object RequestHostAction : ComponentAction
}
data class NamedAction(val id: String, val label: String, val action: ComponentAction)
class ChatComponent internal constructor(
    val scope: ComponentScope, val id: String, val messageId: String, val revision: Long,
    val kind: ComponentKind, val text: String, val actions: Map<String, NamedAction>
)

/** Already-parsed values only. JSON transport, rendering and IPC remain with the host. */
object ComponentDecoder {
    fun decode(raw: Map<String, Any?>, scope: ComponentScope): ChatComponent {
        exactKeys(raw, setOf("schema_version", "component_id", "message_id", "kind", "revision", "text", "actions"))
        require(raw["schema_version"] is Int || raw["schema_version"] is Long)
        require(integer(raw["schema_version"]) == 1L) { "unsupported schema version" }
        val kind = when (raw["kind"]) {
            "text" -> ComponentKind.TEXT
            "native_choices" -> ComponentKind.NATIVE_CHOICES
            "source_list" -> ComponentKind.SOURCE_LIST
            "task" -> ComponentKind.TASK
            "receipt" -> ComponentKind.RECEIPT
            else -> throw IllegalArgumentException("unsupported component kind")
        }
        val entries = raw["actions"] as? List<*> ?: throw IllegalArgumentException("actions must be a list")
        require(entries.size <= 32)
        val actions = LinkedHashMap<String, NamedAction>()
        entries.forEach { entry ->
            val fields = entry as? Map<*, *> ?: throw IllegalArgumentException("invalid action")
            val base = setOf("action_id", "type", "label")
            val action = when (fields["type"]) {
                "local_edit" -> {
                    exactKeys(fields, base + "field")
                    ComponentAction.LocalEdit(checkedId(string(fields, "field", 128)))
                }
                "open_source" -> {
                    exactKeys(fields, base + setOf("source_id", "source_revision", "page"))
                    val page = integer(fields["page"])
                    require(page in 1..1_000_000)
                    ComponentAction.OpenSource(SourceRef(checkedId(string(fields, "source_id", 128)), integer(fields["source_revision"]), page.toInt()))
                }
                "compose_message" -> {
                    exactKeys(fields, base + "text")
                    ComponentAction.ComposeMessage(string(fields, "text", 4096))
                }
                "submit_local" -> { exactKeys(fields, base); ComponentAction.SubmitLocal }
                "request_host_action" -> { exactKeys(fields, base); ComponentAction.RequestHostAction }
                else -> throw IllegalArgumentException("unsupported action")
            }
            val id = checkedId(string(fields, "action_id", 128))
            require(id !in actions) { "duplicate action id" }
            actions[id] = NamedAction(id, string(fields, "label", 256), action)
        }
        require(kind != ComponentKind.TEXT || actions.isEmpty()) { "text blocks are read only" }
        return ChatComponent(scope, checkedId(string(raw, "component_id", 128)), checkedId(string(raw, "message_id", 128)),
            integer(raw["revision"]), kind, string(raw, "text", 4096), frozenMap(actions))
    }
    private fun exactKeys(fields: Map<*, *>, expected: Set<String>) { require(fields.keys == expected) { "unexpected or missing fields" } }
    private fun string(fields: Map<*, *>, key: String, limit: Int): String {
        val value = fields[key] as? String ?: throw IllegalArgumentException("invalid $key")
        require(value.isNotBlank() && value.length <= limit && wellFormedUnicode(value)); return value
    }
    private fun integer(value: Any?): Long {
        val number = when (value) { is Int -> value.toLong(); is Long -> value; else -> throw IllegalArgumentException("integer required") }
        require(number >= 0); return number
    }
}

sealed interface ActionProposal {
    data class ComposeDraft(val text: String) : ActionProposal
    data class OpenSource(val source: SourceRef) : ActionProposal
    data object TrustedHostReviewRequired : ActionProposal
}
data class SubmissionIdentity(
    val scope: ComponentScope, val componentId: String, val messageId: String,
    val componentRevision: Long, val stateRevision: Long, val attemptId: String,
    val actionId: String, val intentId: String, val paramsDigest: String
)
enum class PendingPhase { PENDING, UNKNOWN, CANCEL_REQUESTED }
data class PendingSubmission(val identity: SubmissionIdentity, val values: Map<String, String>, val phase: PendingPhase)
/** Only NewPending represents a newly recorded LOCAL submission, never permission for IPC. */
sealed interface SubmitDecision {
    val submission: PendingSubmission
    data class NewPending(override val submission: PendingSubmission) : SubmitDecision
    data class ExistingPending(override val submission: PendingSubmission) : SubmitDecision
    data class LookupOriginal(override val submission: PendingSubmission) : SubmitDecision
    data class HistoricalReceipt(override val submission: PendingSubmission, val receipt: OriginalReceipt) : SubmitDecision
}
enum class ReceiptStatus { COMMITTED, REJECTED, CANCELLED, NOT_SUBMITTED, UNKNOWN }
/** Only a trusted host adapter may provide observations. This is not an authorization token. */
data class OriginalReceipt(
    val protocolVersion: Int, val identity: SubmissionIdentity, val status: ReceiptStatus,
    val receiptRef: String?, val committed: Boolean, val occurredAt: String,
    val heldMicroCny: Long?, val actualMicroCny: Long?
)
sealed interface Recovery {
    data object None : Recovery
    data class LookupOriginal(val identity: SubmissionIdentity) : Recovery
    /** Historical fact, never a claim about the current business record. */
    data class HistoricalReceipt(val receipt: OriginalReceipt) : Recovery
}
data class ComponentSnapshot(
    val scope: ComponentScope, val componentId: String, val messageId: String,
    val componentRevision: Long, val stateRevision: Long, val attemptId: String,
    val attempts: List<String>, val draft: Map<String, String>, val committed: Map<String, String>,
    val pending: PendingSubmission?, val lastSubmission: PendingSubmission?,
    val history: List<OriginalReceipt>, val heldMicroCny: Long?, val actualMicroCny: Long?
)

/** Offline reducer. Synchronized transitions; persistence-before-dispatch is the host's duty. */
class ComponentLedger private constructor(private val component: ChatComponent, initial: ComponentSnapshot) {
    private var state = freeze(initial)
    constructor(component: ChatComponent, attemptId: String) : this(component, ComponentSnapshot(
        component.scope, component.id, component.messageId, component.revision, 0, checkedId(attemptId),
        listOf(attemptId), emptyMap(), emptyMap(), null, null, emptyList(), null, null
    ))

    @Synchronized fun snapshot(): ComponentSnapshot = freeze(state)

    @Synchronized fun edit(scope: ComponentScope, componentRevision: Long, expectedRevision: Long, actionId: String, value: String) {
        checkContext(scope, componentRevision)
        require(expectedRevision == state.stateRevision && state.pending == null && state.lastSubmission == null) { "stale or locked draft" }
        val action = component.actions[actionId]?.action as? ComponentAction.LocalEdit ?: throw IllegalArgumentException("not a local edit")
        require(value.length <= 4096 && wellFormedUnicode(value))
        state = freeze(state.copy(stateRevision = nextRevision(), draft = state.draft + (action.field to value)))
    }

    @Synchronized fun propose(scope: ComponentScope, revision: Long, actionId: String): ActionProposal {
        checkContext(scope, revision)
        return when (val action = component.actions[actionId]?.action) {
            is ComponentAction.ComposeMessage -> ActionProposal.ComposeDraft(action.text)
            is ComponentAction.OpenSource -> ActionProposal.OpenSource(action.source)
            ComponentAction.RequestHostAction -> ActionProposal.TrustedHostReviewRequired
            else -> throw IllegalArgumentException("not a proposal")
        }
    }

    @Synchronized fun submit(scope: ComponentScope, componentRevision: Long, expectedRevision: Long, actionId: String, intentId: String): SubmitDecision {
        checkContext(scope, componentRevision)
        require(component.actions[actionId]?.action == ComponentAction.SubmitLocal) { "only local submission supported" }
        state.lastSubmission?.let { original ->
            require(original.identity.actionId == actionId)
            require(expectedRevision == state.stateRevision || expectedRevision == original.identity.stateRevision)
            val pending = state.pending
            return when {
                pending == null -> SubmitDecision.HistoricalReceipt(original, state.history.single { it.identity == original.identity })
                pending.phase == PendingPhase.PENDING -> SubmitDecision.ExistingPending(pending)
                else -> SubmitDecision.LookupOriginal(pending)
            }
        }
        require(state.pending == null && expectedRevision == state.stateRevision) { "stale revision" }
        checkedId(intentId)
        require(state.history.none { it.identity.intentId == intentId }) { "intent already used" }
        val identity = SubmissionIdentity(scope, component.id, component.messageId, component.revision,
            state.stateRevision, state.attemptId, actionId, intentId, digest(state.draft))
        val pending = PendingSubmission(identity, frozenMap(state.draft), PendingPhase.PENDING)
        state = freeze(state.copy(stateRevision = nextRevision(), pending = pending, lastSubmission = pending))
        return SubmitDecision.NewPending(pending)
    }

    /**
     * Record local cancellation intent for exactly the captured pending operation and CAS revision.
     * A current-revision duplicate is idempotent; stale callbacks are rejected, never rebound.
     * This does not dispatch remote cancellation, establish success, or authorize rollback.
     */
    @Synchronized fun requestCancel(
        scope: ComponentScope, pendingIdentity: SubmissionIdentity, expectedRevision: Long
    ): PendingSubmission {
        checkContext(scope, pendingIdentity.componentRevision)
        val pending = state.pending ?: throw IllegalArgumentException("no pending request")
        require(pending.identity == pendingIdentity) { "cancel identity mismatch" }
        require(expectedRevision == state.stateRevision) { "stale cancel revision" }
        if (pending.phase == PendingPhase.CANCEL_REQUESTED) return pending
        val requested = pending.copy(phase = PendingPhase.CANCEL_REQUESTED)
        state = freeze(state.copy(stateRevision = nextRevision(), pending = requested))
        return requested
    }

    @Synchronized fun observe(scope: ComponentScope, receipt: OriginalReceipt) {
        checkContext(scope, component.revision)
        val original = state.lastSubmission ?: throw IllegalArgumentException("no original identity")
        require(receipt.identity == original.identity && receipt.protocolVersion == 1) { "receipt identity mismatch" }
        require(receipt.occurredAt.isNotBlank() && receipt.occurredAt.length <= 128)
        require(receipt.heldMicroCny == null || receipt.heldMicroCny >= 0)
        require(receipt.actualMicroCny == null || receipt.actualMicroCny >= 0)
        if (receipt.status == ReceiptStatus.COMMITTED) {
            require(receipt.committed && !receipt.receiptRef.isNullOrBlank() && receipt.receiptRef.length <= 1024)
        } else require(!receipt.committed && receipt.receiptRef == null)
        val existing = state.history.find { it.identity == receipt.identity }
        if (existing != null) { require(existing == receipt) { "terminal history is immutable" }; return }
        require(state.pending != null)
        if (receipt.status == ReceiptStatus.UNKNOWN) {
            state = freeze(state.copy(stateRevision = nextRevision(),
                pending = state.pending!!.copy(phase = PendingPhase.UNKNOWN),
                heldMicroCny = receipt.heldMicroCny ?: state.heldMicroCny,
                actualMicroCny = receipt.actualMicroCny ?: state.actualMicroCny))
        } else {
            state = freeze(state.copy(stateRevision = nextRevision(), pending = null,
                committed = if (receipt.committed) original.values else state.committed,
                history = state.history + receipt,
                heldMicroCny = receipt.heldMicroCny ?: state.heldMicroCny,
                actualMicroCny = receipt.actualMicroCny ?: state.actualMicroCny))
        }
    }

    @Synchronized fun recovery(scope: ComponentScope): Recovery {
        checkContext(scope, component.revision)
        state.pending?.let { return Recovery.LookupOriginal(it.identity) }
        val identity = state.lastSubmission?.identity ?: return Recovery.None
        return Recovery.HistoricalReceipt(state.history.single { it.identity == identity })
    }

    @Synchronized fun redo(scope: ComponentScope, newAttemptId: String) {
        checkContext(scope, component.revision)
        checkedId(newAttemptId)
        require(state.pending == null && state.lastSubmission != null)
        require(newAttemptId !in state.attempts)
        state = freeze(state.copy(stateRevision = nextRevision(), attemptId = newAttemptId,
            attempts = state.attempts + newAttemptId, lastSubmission = null))
    }

    private fun checkContext(scope: ComponentScope, revision: Long) {
        require(scope == component.scope && revision == component.revision) { "scope or component revision mismatch" }
    }
    private fun nextRevision(): Long { require(state.stateRevision < Long.MAX_VALUE); return state.stateRevision + 1 }

    companion object {
        /** Trusted durable host state only; rebind/remount needs a separately reviewed host adapter. */
        fun restore(component: ChatComponent, snapshot: ComponentSnapshot): ComponentLedger {
            require(snapshot.scope == component.scope && snapshot.componentId == component.id &&
                snapshot.messageId == component.messageId && snapshot.componentRevision == component.revision)
            require(snapshot.stateRevision >= 0 && snapshot.attemptId in snapshot.attempts)
            require(snapshot.attempts.distinct().size == snapshot.attempts.size)
            snapshot.attempts.forEach(::checkedId)
            val editableFields = component.actions.values.mapNotNull { (it.action as? ComponentAction.LocalEdit)?.field }.toSet()
            fun checkValues(values: Map<String, String>) {
                require(values.size <= 32 && values.keys.all { it in editableFields } && values.values.all { it.length <= 4096 && wellFormedUnicode(it) })
            }
            checkValues(snapshot.draft); checkValues(snapshot.committed)
            require(snapshot.heldMicroCny == null || snapshot.heldMicroCny >= 0)
            require(snapshot.actualMicroCny == null || snapshot.actualMicroCny >= 0)
            fun checkIdentity(id: SubmissionIdentity) {
                require(id.scope == component.scope && id.componentId == component.id && id.messageId == component.messageId &&
                    id.componentRevision == component.revision && id.stateRevision >= 0 && id.stateRevision < snapshot.stateRevision &&
                    id.attemptId in snapshot.attempts && component.actions[id.actionId]?.action == ComponentAction.SubmitLocal)
                checkedId(id.intentId)
                require(id.paramsDigest.matches(Regex("[0-9a-f]{64}")))
            }
            require(snapshot.history.map { it.identity.intentId }.distinct().size == snapshot.history.size)
            snapshot.history.forEach { receipt ->
                checkIdentity(receipt.identity)
                require(receipt.protocolVersion == 1 && receipt.status != ReceiptStatus.UNKNOWN)
                require(receipt.occurredAt.isNotBlank() && receipt.occurredAt.length <= 128)
                require(receipt.heldMicroCny == null || receipt.heldMicroCny >= 0)
                require(receipt.actualMicroCny == null || receipt.actualMicroCny >= 0)
                require(if (receipt.status == ReceiptStatus.COMMITTED) receipt.committed && !receipt.receiptRef.isNullOrBlank() && receipt.receiptRef.length <= 1024
                    else !receipt.committed && receipt.receiptRef == null)
            }
            val lastCommit = snapshot.history.lastOrNull { it.committed }
            require(if (lastCommit == null) snapshot.committed.isEmpty() else digest(snapshot.committed) == lastCommit.identity.paramsDigest)
            val last = snapshot.lastSubmission
            if (last == null) require(snapshot.pending == null) else {
                checkIdentity(last.identity); checkValues(last.values)
                require(last.identity.attemptId == snapshot.attemptId && last.identity.paramsDigest == digest(last.values) && last.values == snapshot.draft)
                require(snapshot.history.none { it.identity.intentId == last.identity.intentId && it.identity != last.identity })
                val receipt = snapshot.history.singleOrNull { it.identity == last.identity }
                if (snapshot.pending == null) require(receipt != null) else {
                    require(snapshot.pending.identity == last.identity && snapshot.pending.values == last.values && receipt == null)
                }
            }
            return ComponentLedger(component, snapshot)
        }
        private fun freeze(s: ComponentSnapshot) = s.copy(
            attempts = Collections.unmodifiableList(s.attempts.toList()), draft = frozenMap(s.draft), committed = frozenMap(s.committed),
            pending = s.pending?.copy(values = frozenMap(s.pending.values)),
            lastSubmission = s.lastSubmission?.copy(values = frozenMap(s.lastSubmission.values)),
            history = Collections.unmodifiableList(s.history.toList())
        )
    }
}
private fun checkedId(value: String): String {
    require(value.matches(Regex("[A-Za-z0-9_.-]{1,128}"))) { "invalid stable id" }; return value
}
private fun <K, V> frozenMap(map: Map<K, V>): Map<K, V> = Collections.unmodifiableMap(LinkedHashMap(map))
private fun digest(values: Map<String, String>): String {
    val canonical = values.toSortedMap().entries.joinToString("") { "${it.key.length}:${it.key}${it.value.length}:${it.value}" }
    return MessageDigest.getInstance("SHA-256").digest(canonical.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
}

/** Reject lone UTF-16 surrogates before UTF-8 hashing can replace them with the same byte. */
private fun wellFormedUnicode(value: String): Boolean {
    var index = 0
    while (index < value.length) {
        val char = value[index++]
        if (Character.isHighSurrogate(char)) {
            if (index == value.length || !Character.isLowSurrogate(value[index++])) return false
        } else if (Character.isLowSurrogate(char)) return false
    }
    return true
}
