package com.mightyoung.muyon.product.services.documents

import java.io.File
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

private var passed = 0
private var failed = 0
private fun checkCase(name: String, body: () -> Unit) {
    try { body(); passed++; println("PASS $name") }
    catch (error: Exception) { failed++; println("FAIL $name: ${error.message}") }
}
private fun rejects(body: () -> Unit) {
    check(runCatching(body).exceptionOrNull() is IllegalArgumentException) { "expected explicit input rejection" }
}
private fun strictUtf8(bytes: ByteArray): String = Charsets.UTF_8.newDecoder()
    .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
    .decode(ByteBuffer.wrap(bytes)).toString()
private fun hex(raw: String): String {
    require(raw.length % 2 == 0 && raw.all { it in "0123456789abcdef" })
    return strictUtf8(ByteArray(raw.length / 2) { raw.substring(it * 2, it * 2 + 2).toInt(16).toByte() })
}
private fun nullableHex(raw: String): String? = if (raw == "-") null else hex(raw)
private fun uint(raw: String, max: Long): Long {
    require(raw.matches(Regex("0|[1-9][0-9]{0,9}")))
    return raw.toLong().also { require(it <= max) }
}
private fun bool(raw: String): Boolean = when (raw) {
    "true" -> true
    "false" -> false
    else -> throw IllegalArgumentException("noncanonical boolean")
}
private data class WireDescriptor(val model: String, val tokenizer: String, val dimensions: Long, val chunk: String) {
    fun project(): VectorDescriptor {
        require(dimensions <= Int.MAX_VALUE.toLong()) { "outside JVM Int domain" }
        return VectorDescriptor(model, tokenizer, dimensions.toInt(), chunk)
    }
    fun positiveIntDomain() = dimensions in 1..Int.MAX_VALUE.toLong()
}
private fun descriptor(c: List<String>, start: Int): WireDescriptor =
    WireDescriptor(hex(c[start]), hex(c[start + 1]), uint(c[start + 2], 4294967295L), hex(c[start + 3]))
private data class DCase(val id: String, val index: WireDescriptor, val query: WireDescriptor, val expected: Boolean, val supported: Boolean)
private data class CCase(val id: String, val document: String?, val result: String?, val model: WireDescriptor?,
    val documentValid: Boolean, val resultValid: Boolean, val descriptorValid: Boolean, val supported: Boolean,
    val rustCandidate: Boolean, val jvmCandidate: Boolean)
private data class Values(val base: WireDescriptor, val whitespace: List<Int>, val descriptors: List<DCase>, val candidates: List<CCase>)

/** Strict owner test data reader, NOT a production wire codec. */
private fun readValues(bytes: ByteArray): Values {
    try {
        val raw = strictUtf8(bytes)
        require(raw.endsWith('\n') && '\r' !in raw)
        val rows = raw.removeSuffix("\n").split('\n').map { it.split('\t') }
        require(rows.first() == listOf("H", "muyon.public-pipeline-values", "1", "1", "2", "true", "false", "false", "shape_only_not_trusted_resolution", "81", "28", "25"))
        require(rows.size == 136 && rows[1].size == 5 && rows[1][0] == "B")
        val base = descriptor(rows[1], 1)
        val whitespace = ArrayList<Int>()
        val descriptors = ArrayList<DCase>()
        val candidates = ArrayList<CCase>()
        val ids = HashSet<String>()
        for ((position, c) in rows.drop(2).withIndex()) {
            when {
                position < 25 -> {
                    require(c.size == 2 && c[0] == "W")
                    val point = uint(c[1], 0x10ffff).toInt()
                    require(point !in 0xd800..0xdfff && point !in whitespace); whitespace.add(point)
                }
                position < 106 -> {
                    require(c.size == 12 && c[0] == "D" && c[1].isNotEmpty() && ids.add(c[1]))
                    val d = DCase(c[1], descriptor(c, 2), descriptor(c, 6), bool(c[10]), bool(c[11]))
                    require(d.supported == (d.index.positiveIntDomain() && d.query.positiveIntDomain()))
                    descriptors.add(d)
                }
                else -> {
                    require(c.size == 14 && c[0] == "C" && c[1].isNotEmpty() && ids.add(c[1]))
                    val modelColumns = c.subList(4, 8)
                    require(modelColumns.all { it == "-" } || modelColumns.none { it == "-" })
                    val model = if (modelColumns.all { it == "-" }) null else descriptor(c, 4)
                    val v = CCase(c[1], nullableHex(c[2]), nullableHex(c[3]), model,
                        bool(c[8]), bool(c[9]), bool(c[10]), bool(c[11]), bool(c[12]), bool(c[13]))
                    require(v.supported == (model?.positiveIntDomain() == true))
                    require(v.rustCandidate == (v.documentValid && v.resultValid && v.descriptorValid))
                    require(v.jvmCandidate == (v.rustCandidate && v.supported))
                    candidates.add(v)
                }
            }
        }
        require(whitespace.size == 25 && descriptors.size == 81 && candidates.size == 28)
        return Values(base, whitespace, descriptors, candidates)
    } catch (error: Exception) { throw IllegalArgumentException("invalid fixed test projection", error) }
}

fun main(args: Array<String>) {
    val bytes = File(args.single()).readBytes()
    val values = readValues(bytes)
    val base = values.base.project()
    var dTyped = 0; var dOutside = 0; var cTyped = 0; var cOutside = 0
    for (v in values.descriptors) checkCase("D ${v.id}") {
        if (v.index.dimensions > Int.MAX_VALUE || v.query.dimensions > Int.MAX_VALUE) {
            if (v.index.dimensions > Int.MAX_VALUE) rejects { v.index.project() }
            if (v.query.dimensions > Int.MAX_VALUE) rejects { v.query.project() }
            dOutside++; println("DOMAIN_REFUSAL D ${v.id}; no typed compatibility call / no truncation")
        } else {
            dTyped++
            check(validateCompatibility(v.index.project(), v.query.project()) == v.expected) { "expected ${v.expected}" }
        }
    }
    for (point in values.whitespace) checkCase("W U+%04X".format(point)) {
        val version = String(Character.toChars(point))
        val d = base.copy(modelVersion = version)
        check(!validateCompatibility(d, d))
    }
    for (v in values.candidates) checkCase("C ${v.id}") {
        // Probe each declared value rule independently as well as their combination.
        check(hasPublicReferenceCandidate(LegacyIndexEntry(v.document, "result", base)) == v.documentValid) { "document shape" }
        check(hasPublicReferenceCandidate(LegacyIndexEntry("doc", v.result, base)) == v.resultValid) { "result shape" }
        val m = v.model
        if (m != null && m.dimensions > Int.MAX_VALUE) {
            rejects { m.project() }
            cOutside++; println("DOMAIN_REFUSAL C ${v.id}; no typed candidate call / no truncation")
        } else {
            cTyped++
            val projected = m?.project()
            check((projected != null && validateCompatibility(projected, projected)) == v.descriptorValid) { "descriptor shape" }
            check(hasPublicReferenceCandidate(LegacyIndexEntry(v.document, v.result, projected)) == v.jvmCandidate) { "candidate shape only" }
        }
    }
    checkCase("legacy four missing-field counterexamples remain shape rejections") {
        for (entry in listOf(LegacyIndexEntry(null, null, null), LegacyIndexEntry("doc", null, base),
            LegacyIndexEntry(null, "result", base), LegacyIndexEntry("doc", "result", null))) check(!hasPublicReferenceCandidate(entry))
    }
    checkCase("native negative Int dimensions are invalid on either side") {
        for (n in listOf(-1, Int.MIN_VALUE)) {
            val bad = base.copy(dimensions = n)
            check(!validateCompatibility(bad, bad)); check(!validateCompatibility(bad, base)); check(!validateCompatibility(base, bad))
            check(!hasPublicReferenceCandidate(LegacyIndexEntry("doc", "result", bad)))
        }
    }
    projectionRejections(bytes)
    println("COVERAGE D typed=$dTyped outsideInt=$dOutside /81; C combinedTyped=$cTyped outsideInt=$cOutside /28; W=25")
    println("SUMMARY $passed passed / $failed failed; offline compatibility/shape only; trusted host/Android/engine NOT_RUN")
    check(failed == 0) { "offline value checks failed" }
}

private fun projectionRejections(bytes: ByteArray) {
    val raw = strictUtf8(bytes)
    fun changed(line: Int, column: Int, value: String): ByteArray {
        val rows = raw.removeSuffix("\n").split('\n').map { it.split('\t').toMutableList() }.toMutableList()
        rows[line][column] = value
        return (rows.joinToString("\n") { it.joinToString("\t") } + "\n").toByteArray()
    }
    checkCase("projection refuses incompatible version and semantic markers") {
        for ((column, value) in listOf(1 to "other", 2 to "2", 3 to "2", 4 to "1", 5 to "false", 6 to "true", 7 to "true", 8 to "trusted", 9 to "80", 10 to "27", 11 to "24"))
            rejects { readValues(changed(0, column, value)) }
    }
    checkCase("projection refuses missing extra reordered and duplicate records") {
        val lines = raw.removeSuffix("\n").split('\n')
        for (bad in listOf(raw + "\n", lines.dropLast(1).joinToString("\n") + "\n", raw + lines.last() + "\n",
            lines.toMutableList().also { it[28] = it[27] }.joinToString("\n") + "\n",
            lines.toMutableList().also { it[3] = it[2] }.joinToString("\n") + "\n")) rejects { readValues(bad.toByteArray()) }
        rejects { readValues(changed(27, 0, "C")) }
        rejects { readValues(changed(27, 1, "")) }
        rejects { readValues(changed(27, 2, "-")) }
    }
    checkCase("projection refuses noncanonical numbers booleans and partial null model") {
        for (bad in listOf("-0", "-1", "01", "1.0", "1e0", "4294967296", "2147483648x")) rejects { readValues(changed(27, 4, bad)) }
        rejects { readValues(changed(27, 10, "True")) }
        rejects { readValues(changed(27, 11, "false")) }
        rejects { readValues(changed(108, 4, "-")) }
    }
    checkCase("projection refuses damaged UTF8 and noncanonical hex without replacement") {
        for (bad in listOf("a", "GG", "C2A0", "c0af", "eda080", "f4908080")) rejects { readValues(changed(27, 2, bad)) }
        rejects { readValues(byteArrayOf(0xc0.toByte(), 0xaf.toByte())) }
        rejects { readValues(raw.replace("\n", "\r\n").toByteArray()) }
        rejects { readValues(raw.dropLast(1).toByteArray()) }
    }
    checkCase("projection distinguishes null empty and literal hyphen") {
        check(nullableHex("-") == null); check(nullableHex("") == ""); check(nullableHex("2d") == "-")
        check(hex("00") == "\u0000"); check(hex("e794b2") == "甲")
    }
}
