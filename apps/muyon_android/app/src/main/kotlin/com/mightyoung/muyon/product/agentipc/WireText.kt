package com.mightyoung.muyon.product.agentipc

import org.json.JSONArray
import org.json.JSONObject

/** Reject malformed Java strings before a UniFFI object handle is cloned. */
internal fun wellFormedUtf16(value: String): Boolean {
    var index = 0
    while (index < value.length) {
        val char = value[index]
        if (char.isHighSurrogate()) {
            if (index + 1 >= value.length || !value[index + 1].isLowSurrogate()) return false
            index += 2
        } else {
            if (char.isLowSurrogate()) return false
            index++
        }
    }
    return true
}

/** Check parsed values as well as raw JSON: an ASCII \u escape can decode to
 * an invalid surrogate. A valid pair stays unchanged for Rust normalization. */
internal fun validWireJson(value: Any?, depth: Int = 0): Boolean {
    if (depth > 64) return false
    return when (value) {
        is String -> wellFormedUtf16(value)
        is JSONObject -> value.keys().asSequence().all { wellFormedUtf16(it) && validWireJson(value.opt(it), depth + 1) }
        is JSONArray -> (0 until value.length()).all { validWireJson(value.opt(it), depth + 1) }
        else -> true
    }
}
