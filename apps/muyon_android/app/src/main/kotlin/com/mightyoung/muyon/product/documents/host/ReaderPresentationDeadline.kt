package com.mightyoung.muyon.product.documents.host

/** Native relative deadlines anchored to monotonic REQUEST START, never response
 * arrival. Checks don't touch native idle/grant/absolute deadline. Not a grant. */
internal class ReaderPresentationDeadline private constructor(val expiresAtMillis: Long,
    val renewAtMillis: Long, private val checkAtMillis: Long) {
    fun isExpired(nowMillis: Long): Boolean = nowMillis >= expiresAtMillis
    fun renewalDue(nowMillis: Long): Boolean = nowMillis >= renewAtMillis
    fun nextWakeAtMillis(nowMillis: Long): Long = minOf(checkAtMillis, renewAtMillis).coerceAtLeast(nowMillis)
    fun checked(requestStartedMillis: Long, validForMillis: Long, checkAfterMillis: Long): ReaderPresentationDeadline {
        val next = fromNative(requestStartedMillis, validForMillis, checkAfterMillis)
        // A check cannot lengthen the existing frame's deadline, even if a bad
        // native projection claims a longer lease. Only a genuine new ticket can.
        return ReaderPresentationDeadline(minOf(expiresAtMillis, next.expiresAtMillis),
            minOf(renewAtMillis, next.renewAtMillis), next.checkAtMillis)
    }
    companion object {
        fun fromNative(requestStartedMillis: Long, validForMillis: Long, checkAfterMillis: Long): ReaderPresentationDeadline {
            require(requestStartedMillis >= 0 && validForMillis in 1..30_000 && checkAfterMillis in 1..minOf(1_000, validForMillis))
            val expires = Math.addExact(requestStartedMillis, validForMillis)
            // Budget for the <=2s native challenge/sampling/handoff, instead of
            // scheduling at the 30s maximum. Tiny remaining grants renew NOW.
            val renew = Math.addExact(requestStartedMillis, (validForMillis - 2_000).coerceAtLeast(0))
            return ReaderPresentationDeadline(expires, renew, Math.addExact(requestStartedMillis, checkAfterMillis))
        }
    }
}
