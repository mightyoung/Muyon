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
    println("SUMMARY $passed passed / $failed failed; pure JVM only")
    check(failed == 0) { "contract checks failed" }
}
