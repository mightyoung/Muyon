package com.mightyoung.muyon.study.adapters

import java.io.InputStream
import java.io.OutputStream

internal object BoundedCopy {
    fun copy(input: InputStream, output: OutputStream, limit: Long, declaredSize: Long = -1): Long {
        require(limit >= 0)
        if(declaredSize > limit) throw ProviderException("响应超过大小限制")
        var total = 0L
        val buffer = ByteArray(8192)
        while(true) {
            val count = input.read(buffer)
            if(count < 0) return total
            if(count == 0) continue
            if(count.toLong() > limit - total) throw ProviderException("响应超过大小限制")
            output.write(buffer, 0, count); total += count
        }
    }
}
