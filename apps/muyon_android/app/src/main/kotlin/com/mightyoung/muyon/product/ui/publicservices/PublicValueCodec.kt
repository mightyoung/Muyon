package com.mightyoung.muyon.product.ui.publicservices

fun parseRevision(raw: String): String = throw IllegalArgumentException("unavailable: $raw")
fun parseUnixMs(raw: String): String = throw IllegalArgumentException("unavailable: $raw")
fun toLegacyRevision(raw: String): Long? = throw IllegalArgumentException("unavailable: $raw")
fun toPublicPageIndex(page: Int): Int = throw IllegalArgumentException("unavailable: $page")
fun parsePublicId(raw: String): String = throw IllegalArgumentException("unavailable: $raw")
fun parsePublicDigest(raw: String): String = throw IllegalArgumentException("unavailable: $raw")
fun decodePublicValue(kind: String, raw: String): String = throw IllegalArgumentException("unavailable: $kind $raw")
