package com.mightyoung.muyon.product.services.documents

/** Offline declared values only; this is not a resolved model or search capability. */
data class VectorDescriptor(
    val modelVersion: String,
    val tokenizerVersion: String,
    val dimensions: Int,
    val chunkVersion: String,
)

/** Candidate fields, not an existing storage schema, ResultRef or permission grant. */
data class LegacyIndexEntry(
    val documentId: String?,
    val resultId: String?,
    val model: VectorDescriptor?,
)

@Suppress("UNUSED_PARAMETER")
fun validateCompatibility(index: VectorDescriptor, query: VectorDescriptor): Boolean = false

@Suppress("UNUSED_PARAMETER")
fun hasPublicReferenceCandidate(entry: LegacyIndexEntry): Boolean = false
