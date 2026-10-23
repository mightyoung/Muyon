package com.mightyoung.muyon.product.ui.publicservices

import java.io.File
import org.json.JSONObject

private var passed = 0
private var failed = 0
private fun checkCase(name: String, body: () -> Unit) {
    try { body(); passed++; println("PASS $name") }
    catch (error: Exception) { failed++; println("FAIL $name: ${error.message}") }
}
private fun rejects(body: () -> Unit) {
    val result = runCatching(body)
    check(result.exceptionOrNull() is IllegalArgumentException) { "expected input rejection, got $result" }
}

fun main(args: Array<String>) {
    checkCase("u64 exact boundaries and legacy refusal") {
        for (raw in listOf("0", "9007199254740993", "9223372036854775808", "18446744073709551615")) {
            check(parseRevision(raw) == raw)
        }
        check(toLegacyRevision("9223372036854775807") == Long.MAX_VALUE)
        check(toLegacyRevision("9223372036854775808") == null)
        check(toLegacyRevision("18446744073709551615") == null)
    }
    checkCase("noncanonical and overflowing revisions rejected") {
        for (raw in listOf("", "01", "-0", "+1", "1.0", "1e2", " 1", "１", "18446744073709551616")) {
            rejects { parseRevision(raw) }
        }
    }
    checkCase("signed time is exact including minimum") {
        for (raw in listOf("0", "-1", "9223372036854775807", "-9223372036854775808")) check(parseUnixMs(raw) == raw)
        for (raw in listOf("", "01", "-0", "+1", " 1", "9223372036854775808", "-9223372036854775809")) rejects { parseUnixMs(raw) }
    }
    checkCase("legacy page conversion is explicit") {
        check(toPublicPageIndex(1) == 0)
        check(toPublicPageIndex(Int.MAX_VALUE) == Int.MAX_VALUE - 1)
        rejects { toPublicPageIndex(0) }; rejects { toPublicPageIndex(-1) }
    }
    val fixture = JSONObject(File(args.single()).readText())
    check(fixture.getInt("contract_major") == 1 && fixture.getInt("schema_major") == 1)
    val cases = fixture.getJSONArray("cases")
    for (i in 0 until cases.length()) {
        val item = cases.getJSONObject(i)
        checkCase("C1 ${item.getString("id")}") {
            if (item.getBoolean("valid")) {
                val decoded = JSONObject(decodePublicValue(item.getString("kind"), item.getString("json")))
                check(decoded.similar(item.getJSONObject("expected")))
            } else rejects { decodePublicValue(item.getString("kind"), item.getString("json")) }
        }
    }
    val vectors = fixture.getJSONArray("legacy_identity_vectors")
    for (i in 0 until vectors.length()) {
        val vector = vectors.getJSONObject(i)
        checkCase("C1 identity ${vector.getString("id")}") {
            val raw = vector.getString("value")
            if (vector.has("byte_length")) check(raw.toByteArray(Charsets.UTF_8).size == vector.getInt("byte_length"))
            // Native validity remains the original owner's concern. No duplicate command validator.
            if (vector.has("valid_public")) {
                if (vector.getBoolean("valid_public")) check(parsePublicId(raw) == raw)
                else rejects { parsePublicId(raw) }
            }
        }
    }
    checkCase("strict transport rejects duplicate nested keys and lenient JSON") {
        val bad = listOf(
            "{\"scope\":{\"workspace_id\":\"w\",\"workspace_id\":\"other\",\"project_id\":null},\"scope_generation\":\"1\",\"account_id\":null}",
            "{\"scope\":{},\"scope\":{}}", "{'scope':{}}", "{scope:{}}", "{\"scope\":{},}",
            "{\"scope\":{}} trailing", "{\"scope\":{},\"scope_generation\":1}",
            "{\"scope\":{\"workspace_id\":\"\\uD800\",\"project_id\":null},\"scope_generation\":\"1\",\"account_id\":null}"
        )
        for (raw in bad) rejects { decodePublicValue("scope", raw) }
        rejects { decodePublicValue("scope", "\"" + "x".repeat(1_048_576) + "\"") }
        rejects { decodePublicValue("unexpected", "{}") }
    }
    checkCase("coverage contradictions and numeric counters are rejected") {
        for (raw in listOf(
            "{\"state\":\"complete\",\"processed\":\"0\",\"total\":null,\"failed_units\":[]}",
            "{\"state\":\"complete\",\"processed\":\"1\",\"total\":\"2\",\"failed_units\":[]}",
            "{\"state\":\"complete\",\"processed\":\"2\",\"total\":\"2\",\"failed_units\":[0]}",
            "{\"state\":\"partial\",\"processed\":\"3\",\"total\":\"2\",\"failed_units\":[]}",
            "{\"state\":\"unknown\",\"processed\":0,\"total\":null,\"failed_units\":[]}"
        )) rejects { decodePublicValue("coverage", raw) }
        val raw = "{\"state\":\"partial\",\"processed\":\"9007199254740993\",\"total\":\"18446744073709551615\",\"failed_units\":[0]}"
        check(JSONObject(decodePublicValue("coverage", raw)).getString("processed") == "9007199254740993")
    }
    checkCase("opaque UTF8 and digest syntax preserve original bytes") {
        check(parsePublicId("甲".repeat(42)) == "甲".repeat(42))
        for (raw in listOf("", "a\u0000b", "甲".repeat(43), "x".repeat(129))) rejects { parsePublicId(raw) }
        check(parsePublicDigest("a".repeat(64)) == "a".repeat(64))
        for (raw in listOf("A".repeat(64), "g".repeat(64), "a".repeat(63))) rejects { parsePublicDigest(raw) }
    }
    checkCase("C1 coverage requires explicit total") {
        rejects { decodePublicValue("coverage", """{"state":"unknown","processed":"0","failed_units":[]}""") }
    }
    checkCase("C1 omitted scope options normalize to null") {
        val scope = JSONObject(decodePublicValue("scope", """{"scope":{"workspace_id":"w"},"scope_generation":"1"}"""))
        check(scope.has("account_id") && scope.isNull("account_id"))
        check(scope.getJSONObject("scope").has("project_id") && scope.getJSONObject("scope").isNull("project_id"))
    }
    checkCase("C1 omitted error options normalize to null") {
        val error = JSONObject(decodePublicValue("error", """{"code":"unknown_outcome","phase":"host_call","retryability":"after_lookup","effect_knowledge":"unknown","safe_message":"unknown"}"""))
        check(error.has("original_intent_id") && error.isNull("original_intent_id"))
        check(error.has("details_ref") && error.isNull("details_ref"))
    }
    planSafetyChecks()
    println("SUMMARY $passed passed / $failed failed; pure JVM only")
    check(failed == 0) { "contract checks failed" }
}

private val snapshot = SnapshotRef("snapshot:1", "9007199254740993")
private val answer = AnswerRef("answer:1", "1")
private val request = PresentationRequest("request:1", answer, snapshot, "supplement", "1", "capability:1")
private val source = SourceBinding("result:1", "doc:1", "9007199254740993", "a".repeat(64), "0", "4", 0)
private fun context() = ValidationContext(snapshot, "1", setOf("action:1"), mapOf("source:1" to source), true, true)
private fun message(id: String = "root", content: String = "answer", children: List<String> = emptyList()) =
    Node(id, ComponentType.MessageBlock, Props.Message(content, answer), emptyList(), children, emptyList())
private fun plan(nodes: List<Node> = listOf(message())) = UIPlan(1, "surface:1", "1", snapshot, nodes.first().id, nodes)
private fun rejected(p: UIPlan, c: ValidationContext = context()) {
    val result = validatePlan(request, p, c)
    check(result.decision == Decision.TextOnly && result.plan == null)
}
private fun planSafetyChecks() {
    checkCase("valid plan preserves original answer and immutable host copies") {
        val nodes = mutableListOf(message())
        val actions = mutableSetOf("action:1")
        val sources = mutableMapOf("source:1" to source)
        val result = validatePlan(request, plan(nodes), context().copy(allowedActions = actions, sources = sources))
        check(result.decision == Decision.Supplement)
        val validated = checkNotNull(result.plan)
        nodes.clear(); actions.clear(); sources.clear()
        check(validated.plan.nodes.size == 1 && validated.context.allowedActions == setOf("action:1"))
        check(validated.context.sources["source:1"] == source)
        check((validated.plan.nodes.single().typedProps as Props.Message).answerRef == answer)
        check(runCatching { (validated.plan.nodes as MutableList<Node>).clear() }.isFailure)
    }
    checkCase("schema snapshot source and action mismatches degrade") {
        rejected(plan().copy(schemaVersion = 2))
        rejected(plan().copy(snapshotRef = snapshot.copy(revision = "2")))
        rejected(plan(listOf(message().copy(eventBindings = listOf(EventBinding(EventKind.DomainRequest, "action:wrong"))))))
        rejected(plan(listOf(message().copy(eventBindings = listOf(EventBinding(EventKind.DomainRequest, "action:1"))))), context().copy(actionAllowed = false))
        rejected(plan(listOf(Node("root", ComponentType.SourceCard, Props.Source(source, "甲A", "cited"), emptyList(), emptyList(), emptyList()))), context().copy(sources = emptyMap()))
        rejected(plan(), context().copy(readAllowed = false))
        rejected(plan(listOf(message().copy(typedProps = Props.Message("answer", answer.copy(revision = "2"))))))
    }
    checkCase("node count limit has a reachable positive boundary") {
        val nodes = (0 until 256).map { i -> message("n$i", children = if (i < 32) ((i * 8 + 1)..minOf(i * 8 + 8, 255)).filter { it < 256 }.map { "n$it" } else emptyList()) }
        check(validatePlan(request, plan(nodes), context()).plan != null)
        rejected(plan(nodes + message("extra")))
    }
    checkCase("depth child count cycle orphan and duplicate boundaries") {
        fun chain(n: Int) = (0 until n).map { i -> message("n$i", children = if (i + 1 < n) listOf("n${i+1}") else emptyList()) }
        check(validatePlan(request, plan(chain(16)), context()).plan != null)
        rejected(plan(chain(17)))
        val children = (1..32).map { "n$it" }
        check(validatePlan(request, plan(listOf(message(children = children)) + children.map { message(it) }), context()).plan != null)
        rejected(plan(listOf(message(children = children + "extra")) + children.map { message(it) } + message("extra")))
        rejected(plan(listOf(message(children = listOf("root")))))
        rejected(plan(listOf(message(children = listOf("missing")))))
        rejected(plan(listOf(message(), message())))
        rejected(plan(listOf(message(), message("orphan"))))
    }
    checkCase("shared subgraphs cannot amplify presentation instances") {
        fun level(n: Int) = (0 until 16).map { "l${n}n$it" }
        val nodes = listOf(message("root", children = level(1))) +
            (1..15).flatMap { n -> level(n).map { id -> message(id, "x", if (n == 15) emptyList() else level(n + 1)) } }
        check(nodes.size == 241)
        rejected(plan(nodes))
    }
    checkCase("UTF8 text limit counts bytes without truncation") {
        check(validatePlan(request, plan(listOf(message(content = "x".repeat(65536)))), context()).plan != null)
        rejected(plan(listOf(message(content = "x".repeat(65537)))))
        rejected(plan(listOf(message(content = "甲".repeat(21846)))))
    }
    checkCase("source interval uses bytes and exact host binding") {
        val node = Node("root", ComponentType.SourceCard, Props.Source(source, "甲A", "unassessed"), listOf("source:1"), emptyList(), emptyList())
        check(validatePlan(request, plan(listOf(node)), context()).plan != null)
        val short = source.copy(endByte = "2")
        rejected(plan(listOf(node.copy(typedProps = Props.Source(short, "甲", "cited")))), context().copy(sources = mapOf("source:1" to short)))
        rejected(plan(listOf(node.copy(typedProps = Props.Source(source.copy(pageIndex = -1), "甲A", "cited")))))
        rejected(plan(listOf(node.copy(typedProps = Props.Source(source, "甲A", "trusted")))))
        rejected(plan(listOf(node.copy(bindingRefs = listOf("missing")))))
    }
    checkCase("props mismatch and malformed collection relationships rejected") {
        rejected(plan(listOf(message().copy(typedProps = Props.Choice(listOf("o"), emptySet(), null)))))
        val form = Node("root", ComponentType.FormCard, Props.Form(listOf("f"), mapOf("f" to "text"), mapOf("f" to "v"), emptyMap()), emptyList(), emptyList(), emptyList())
        check(validatePlan(request, plan(listOf(form)), context()).plan != null)
        rejected(plan(listOf(form.copy(typedProps = Props.Form(listOf("f"), mapOf("wrong" to "text"), emptyMap(), emptyMap())))))
        rejected(plan(listOf(form.copy(typedProps = Props.Form(listOf("f"), mapOf("f" to "script"), emptyMap(), emptyMap())))))
        rejected(plan(listOf(form.copy(typedProps = Props.Form(listOf("f"), mapOf("f" to "text"), mapOf("unknown" to "value"), emptyMap())))))
        val results = Node("root", ComponentType.ResultList, Props.Results(listOf("a"), listOf("label"), listOf(source)), emptyList(), emptyList(), emptyList())
        check(validatePlan(request, plan(listOf(results)), context()).plan != null)
        rejected(plan(listOf(results.copy(typedProps = Props.Results(listOf("a"), emptyList(), listOf(source))))))
        rejected(plan(listOf(results.copy(typedProps = Props.Results(listOf("a", "a"), listOf("a", "b"), listOf(source, source))))))
    }
    checkCase("unresolved trusted objects never become trusted presentation") {
        for ((kind, props) in listOf(
            ComponentType.ConfirmationCard to Props.Confirmation("prepared:1"),
            ComponentType.ReceiptCard to Props.Receipt("intent:1", "receipt:1"),
            ComponentType.AttachmentCard to Props.Attachment("doc:1", listOf("coverage:1")),
            ComponentType.DraftArtifactCard to Props.DraftArtifact("draft:1", "content", "saved")
        )) rejected(plan(listOf(Node("root", kind, props, emptyList(), emptyList(), emptyList()))))
        val progress = Node("root", ComponentType.TaskProgressCard, Props.Progress("job:1", "parse", "0", null), emptyList(), emptyList(), emptyList())
        check(validatePlan(request, plan(listOf(progress)), context()).plan != null)
        rejected(plan(listOf(progress.copy(typedProps = Props.Progress("job:1", "parse", "3", "2")))))
    }
    checkCase("raw unknown component action and approved fields degrade without dispatch") {
        val raw = """{"schemaVersion":1,"surfaceId":"surface:1","planRevision":"1","snapshotRef":{"id":"snapshot:1","revision":"9007199254740993"},"root":"root","nodes":[{"id":"root","componentType":"MessageBlock","typedProps":{"text":"answer","answerRef":{"id":"answer:1","revision":"1"}},"bindingRefs":[],"children":[],"eventBindings":[]}]}"""
        check(validateEncodedPlan(request, raw, context()).plan != null)
        val malformed = listOf(raw.replace("MessageBlock", "Script"), raw.replace(""""text":"answer"""", """"text":"answer","approved":true"""), raw.replace(""""eventBindings":[]""", """"eventBindings":[{"eventKind":"DomainRequest","actionRef":"unknown"}]"""), raw.dropLast(2))
        // The production validator has no command port; rejection cannot issue a command.
        for (bad in malformed) check(validateEncodedPlan(request, bad, context()).decision == Decision.TextOnly)
    }
}
