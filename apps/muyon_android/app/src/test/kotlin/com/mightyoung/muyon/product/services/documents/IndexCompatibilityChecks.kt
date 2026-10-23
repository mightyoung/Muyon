package com.mightyoung.muyon.product.services.documents

import java.io.File

// Test specification only until the existing compiler is available. Values come
// from the Rust synthetic fixture, not a second model/catalog definition.
fun main(args: Array<String>) {
    val fixture = File(args.single()).readText()
    fun field(name: String): String = requireNotNull(
        Regex("\"$name\"\\s*:\\s*\"([^\"]+)\"").find(fixture)
    ).groupValues[1]
    val dimensions = requireNotNull(Regex("\"dimensions\"\\s*:\\s*(\\d+)").find(fixture)).groupValues[1].toInt()
    val descriptor = VectorDescriptor(field("model_version"), field("tokenizer_version"), dimensions, field("chunk_version"))
    check(validateCompatibility(descriptor, descriptor))
    for (other in listOf(
        descriptor.copy(modelVersion = "different"),
        descriptor.copy(tokenizerVersion = "different"),
        descriptor.copy(dimensions = dimensions / 2),
        descriptor.copy(chunkVersion = "different"),
    )) check(!validateCompatibility(descriptor, other))
    check(!isPubliclyResolvable(LegacyIndexEntry(null, null, null)))
    check(!isPubliclyResolvable(LegacyIndexEntry("doc", null, descriptor)))
    check(!isPubliclyResolvable(LegacyIndexEntry(null, "result", descriptor)))
    check(!isPubliclyResolvable(LegacyIndexEntry("doc", "result", null)))
    // These pure checks cannot attest that a host has authorized/resolved an entry
    // or that an actual engine/query adapter makes zero calls; those remain gates.
    println("Index compatibility synthetic checks passed; production host/engine NOT_RUN.")
}
