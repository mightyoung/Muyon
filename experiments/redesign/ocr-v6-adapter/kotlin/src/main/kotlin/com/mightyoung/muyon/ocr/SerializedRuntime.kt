package com.mightyoung.muyon.ocr

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Serializes native use/release and makes release idempotent, including a failed release. */
internal class SerializedRuntime(private val run:suspend (ByteArray,Int,Int)->List<OcrLine>,private val release:suspend ()->Unit):OcrRuntime {
    private val lock=Mutex()
    private var closed=false
    override suspend fun recognize(image:ByteArray,width:Int,height:Int):List<OcrLine> = lock.withLock {
        if(closed) throw OcrFailure(OcrError.INFERENCE_FAILED)
        run(image,width,height)
    }
    override suspend fun close() = lock.withLock {
        if(!closed) { closed=true;release() }
    }
}
