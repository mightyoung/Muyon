package com.mightyoung.muyon.study.adapters

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import org.junit.Assert.*
import org.junit.Test

class BoundedCopyTest {
    @Test fun acceptsExactLimitWithoutClosingCallerOutput() {
        val out = ByteArrayOutputStream()
        assertEquals(4L, BoundedCopy.copy(ByteArrayInputStream(byteArrayOf(1,2,3,4)), out, 4))
        assertArrayEquals(byteArrayOf(1,2,3,4), out.toByteArray())
    }
    @Test fun rejectsDeclaredOversizeBeforeWritingAndUndeclaredOverflow() {
        val out = ByteArrayOutputStream()
        try { BoundedCopy.copy(ByteArrayInputStream(byteArrayOf(1)), out, 4, 5); fail() } catch (_: ProviderException) { }
        assertEquals(0, out.size())
        try { BoundedCopy.copy(ByteArrayInputStream(ByteArray(8193)), out, 8192); fail() } catch (_: ProviderException) { }
        assertEquals(8192, out.size())
    }
}
