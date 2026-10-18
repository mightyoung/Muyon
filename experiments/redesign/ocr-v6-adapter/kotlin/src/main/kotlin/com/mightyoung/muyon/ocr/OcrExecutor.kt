package com.mightyoung.muyon.ocr

import java.io.InputStream
import java.io.FileNotFoundException
import java.security.MessageDigest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
const val TINY_VERSION = "PP-OCRv6_tiny-det-2ba1506c-rec-2612ab37"
const val PARAMETERS_VERSION = "ppocr-android-dab3fe35-defaults-v1"
data class ExecutionRequest(val jobId:String,val rasterDigest:String,val width:Int,val height:Int,val modelVersion:String,val parametersVersion:String,val expiresAtMs:Long)
data class Point(val x:Double,val y:Double)
data class OcrLine(val text:String,val quad:List<Point>,val recognitionConfidence:Double,val detectionConfidence:Double?)
data class PlatformPage(val jobId:String,val rasterDigest:String,val modelVersion:String,val parametersVersion:String,val width:Int,val height:Int,val lines:List<OcrLine>)
data class Asset(val path:String,val bytes:Long,val sha256:String)
enum class OcrError { UNSUPPORTED_PLATFORM, CANCELLED, TIMEOUT, MODEL_MISSING, MODEL_CORRUPT, INVALID_REQUEST, INVALID_RESULT, INFERENCE_FAILED }
class OcrFailure(val code:OcrError): Exception(code.name)
class Cancellation { @Volatile private var cancelled=false; fun cancel() {cancelled=true}; fun isCancelled()=cancelled }
interface OcrRuntime { suspend fun recognize(image:ByteArray,width:Int,height:Int):List<OcrLine>; suspend fun close() }
class OcrExecutor internal constructor(private val assets:List<Asset>,private val open:(String)->InputStream,private val factory:suspend ()->OcrRuntime,private val clock:()->Long) {
    /** Called from the private Android Service worker, never from a UI command. */
    suspend fun execute(r:ExecutionRequest,image:ByteArray,sdk:Int,cancellation:Cancellation):PlatformPage {
        if (sdk < 26) throw OcrFailure(OcrError.UNSUPPORTED_PLATFORM)
        if (r.jobId.isEmpty() || r.jobId.length > 128 || r.modelVersion != TINY_VERSION ||
            r.parametersVersion != PARAMETERS_VERSION || r.width !in 1..4096 || r.height !in 1..4096 ||
            r.width.toLong()*r.height > 16_000_000 || image.isEmpty() || image.size > 32*1024*1024 ||
            sha(image) != r.rasterDigest) throw OcrFailure(OcrError.INVALID_REQUEST)
        checkActive(r,cancellation)
        for (asset in assets) {
            checkActive(r,cancellation)
            val digest=MessageDigest.getInstance("SHA-256")
            var count=0L
            try {
                open(asset.path).use { stream ->
                    val buffer=ByteArray(64*1024)
                    while(true) {
                        checkActive(r,cancellation)
                        val read=stream.read(buffer)
                        if(read < 0) break
                        count+=read
                        if(count>asset.bytes) throw OcrFailure(OcrError.MODEL_CORRUPT)
                        digest.update(buffer,0,read)
                    }
                }
            } catch(e: FileNotFoundException) { throw OcrFailure(OcrError.MODEL_MISSING) }
            catch(e: OcrFailure) { throw e }
            catch(e: java.io.IOException) { throw OcrFailure(OcrError.MODEL_CORRUPT) }
            if(count!=asset.bytes || hex(digest.digest())!=asset.sha256) throw OcrFailure(OcrError.MODEL_CORRUPT)
        }
        checkActive(r,cancellation)
        try {
            val runtime=withContext(NonCancellable) { factory() }
            val lines=try {
                checkActive(r,cancellation)
                runtime.recognize(image,r.width,r.height).also {
                    checkActive(r,cancellation)
                    if(it.size>3000 || it.sumOf { line -> line.text.toByteArray(Charsets.UTF_8).size.toLong() }>1_048_576 || it.any { line -> !validLine(line,r.width,r.height) })
                        throw OcrFailure(OcrError.INVALID_RESULT)
                }
            } finally { withContext(NonCancellable) { runtime.close() } }
            checkActive(r,cancellation)
            return PlatformPage(r.jobId,r.rasterDigest,r.modelVersion,r.parametersVersion,r.width,r.height,lines)
        } catch(e: CancellationException) { throw e }
        catch(e: OcrFailure) { throw e }
        catch(e: Exception) { throw OcrFailure(OcrError.INFERENCE_FAILED) }
    }
    private suspend fun checkActive(r:ExecutionRequest,c:Cancellation) {
        currentCoroutineContext().ensureActive()
        if(c.isCancelled()) throw OcrFailure(OcrError.CANCELLED)
        if(clock()>=r.expiresAtMs) throw OcrFailure(OcrError.TIMEOUT)
    }
}
internal fun hex(bytes:ByteArray)=bytes.joinToString("") { "%02x".format(it) }
internal fun sha(bytes:ByteArray)=hex(MessageDigest.getInstance("SHA-256").digest(bytes))
internal fun validLine(line:OcrLine,width:Int,height:Int):Boolean {
    fun confidence(v:Double)=v.isFinite() && v in 0.0..1.0
    if(line.text.toByteArray(Charsets.UTF_8).size>65_536 || !confidence(line.recognitionConfidence) ||
        line.detectionConfidence?.let { !confidence(it) }==true || line.quad.size!=4) return false
    if(line.quad.any { !it.x.isFinite() || !it.y.isFinite() || it.x<0 || it.x>width || it.y<0 || it.y>height }) return false
    val crosses=(0..3).map { i ->
        val a=line.quad[i];val b=line.quad[(i+1)%4];val c=line.quad[(i+2)%4]
        (b.x-a.x)*(c.y-b.y)-(b.y-a.y)*(c.x-b.x)
    }
    return crosses.all { it>1e-9 } || crosses.all { it< -1e-9 }

}
