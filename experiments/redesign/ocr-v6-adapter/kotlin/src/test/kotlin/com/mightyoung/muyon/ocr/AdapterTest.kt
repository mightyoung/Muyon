package com.mightyoung.muyon.ocr

import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.security.MessageDigest

class AdapterTest {
    private val image = byteArrayOf(1,2,3)
    private fun sha(b: ByteArray) = MessageDigest.getInstance("SHA-256").digest(b).joinToString("") { "%02x".format(it) }
    private fun request() = ExecutionRequest("job-1", sha(image), 200, 100, TINY_VERSION, PARAMETERS_VERSION, 1000)
    private val model = byteArrayOf(4,5,6)
    private fun assets() = listOf(Asset("det",3,sha(model)),Asset("rec",3,sha(model)),Asset("dict",3,sha(model)))
    private class Runtime : OcrRuntime {
        var closes=0; var calls=0; var afterRun: () -> Unit = {}; var fail=false
        override suspend fun recognize(image: ByteArray, width: Int, height: Int): List<OcrLine> {
            calls++;afterRun();if(fail) error("runtime failure")
            return listOf(OcrLine("Total 123.45",listOf(Point(1.0,2.0),Point(100.0,2.0),Point(100.0,30.0),Point(1.0,30.0)),0.9,null))
        }
        override suspend fun close() { closes++ }
    }
    private fun adapter(runtime: Runtime, clock: () -> Long = { 1 }, open: (String) -> java.io.InputStream = { ByteArrayInputStream(model) }, factory: suspend () -> OcrRuntime = { runtime }) =
        OcrExecutor(assets(), open, factory, clock)
    private suspend fun errorCode(expected: OcrError, block: suspend () -> Unit) {
        try { block(); fail("Expected $expected") } catch(e: OcrFailure) { assertEquals(expected,e.code);assertEquals(expected.name,e.message);assertNull(e.cause) }
    }
    @Test fun returns_det_rec_envelope_and_releases_once() = runBlocking {
        val rt=Runtime(); val page=adapter(rt).execute(request(),image,26,Cancellation())
        assertEquals("job-1",page.jobId);assertEquals(TINY_VERSION,page.modelVersion)
        assertEquals("Total 123.45",page.lines.single().text)
        assertNull(page.lines.single().detectionConfidence);assertEquals(1,rt.calls);assertEquals(1,rt.closes)
    }
    @Test fun api24_and_25_never_load_native_runtime() = runBlocking {
        for (sdk in listOf(24,25)) {
            val rt=Runtime();var loads=0
            errorCode(OcrError.UNSUPPORTED_PLATFORM) { adapter(rt,factory={loads++;rt}).execute(request(),image,sdk,Cancellation()) }
            assertEquals(0,loads);assertEquals(0,rt.calls)
        }
    }
    @Test fun cancelled_before_load_and_during_inference_never_return_success() = runBlocking {
        val rt=Runtime(); val c=Cancellation();c.cancel()
        errorCode(OcrError.CANCELLED) { adapter(rt).execute(request(),image,26,c) };assertEquals(0,rt.calls)
        val c2=Cancellation();rt.afterRun={c2.cancel()}
        errorCode(OcrError.CANCELLED) { adapter(rt).execute(request(),image,26,c2) };assertEquals(1,rt.closes)
    }
    @Test fun timeout_after_native_run_discards_result_and_releases() = runBlocking {
        val rt=Runtime();var now=1L;rt.afterRun={now=1000}
        errorCode(OcrError.TIMEOUT) { adapter(rt,clock={now}).execute(request(),image,26,Cancellation()) };assertEquals(1,rt.closes)
    }
    @Test fun corrupt_or_missing_models_fail_before_factory() = runBlocking {
        val rt=Runtime();var loads=0
        errorCode(OcrError.MODEL_CORRUPT) { adapter(rt,open={ByteArrayInputStream(byteArrayOf(9,9,9))},factory={loads++;rt}).execute(request(),image,26,Cancellation()) }
        errorCode(OcrError.MODEL_MISSING) { adapter(rt,open={throw java.io.FileNotFoundException()},factory={loads++;rt}).execute(request(),image,26,Cancellation()) }
        assertEquals(0,loads)
    }
    @Test fun wrong_raster_model_and_budget_fail_before_factory() = runBlocking {
        val rt=Runtime();var loads=0
        val ex=adapter(rt,factory={loads++;rt})
        for(r in listOf(request().copy(rasterDigest="bad"),request().copy(modelVersion="v5"),request().copy(width=0),request().copy(height=100000))) {
            errorCode(OcrError.INVALID_REQUEST) { ex.execute(r,image,26,Cancellation()) }
        }
        assertEquals(0,loads)
    }
    @Test fun repeated_jobs_and_runtime_failure_release_all_sessions() = runBlocking {
        val rt=Runtime();val ex=adapter(rt)
        repeat(20) { ex.execute(request(),image,26,Cancellation()) }
        rt.fail=true
        errorCode(OcrError.INFERENCE_FAILED) { ex.execute(request(),image,26,Cancellation()) }
        assertEquals(21,rt.closes)
    }
    @Test fun coroutine_cancel_during_factory_still_releases_created_session() = runBlocking {
        val rt=Runtime();val loading=CompletableDeferred<Unit>();val resume=CompletableDeferred<Unit>()
        val ex=adapter(rt,factory={
            // A native allocator may finish despite parent cancellation.
            withContext(NonCancellable) { loading.complete(Unit);resume.await() };rt
        })
        val job=launch { ex.execute(request(),image,26,Cancellation()) }
        loading.await();job.cancel();resume.complete(Unit);job.join()
        assertEquals(0,rt.calls);assertEquals(1,rt.closes)
    }
    @Test fun native_linkage_errors_are_controlled_and_do_not_expose_loader_text() = runBlocking {
        val rt=Runtime()
        errorCode(OcrError.INFERENCE_FAILED) {
            adapter(rt,factory={throw UnsatisfiedLinkError("private-loader-path")}).execute(request(),image,26,Cancellation())
        }
        rt.afterRun={throw ExceptionInInitializerError("private-loader-path")}
        errorCode(OcrError.INFERENCE_FAILED) { adapter(rt).execute(request(),image,26,Cancellation()) }
        assertEquals(1,rt.closes)
    }
    @Test fun invalid_runtime_geometry_is_not_emitted() = runBlocking {
        val rt=object: OcrRuntime {
            var closed=false
            override suspend fun recognize(image:ByteArray,width:Int,height:Int)=listOf(OcrLine("x",List(4){Point(Double.NaN,0.0)},1.0,null))
            override suspend fun close() { closed=true }
        }
        val ex=OcrExecutor(assets(),{ByteArrayInputStream(model)},{rt},{1})
        errorCode(OcrError.INVALID_RESULT) { ex.execute(request(),image,26,Cancellation()) }
        assertTrue(rt.closed)
    }
}

class LifetimeTest {
    @Test fun repeated_release_is_idempotent_and_use_after_close_is_rejected() = runBlocking {
        var releases=0
        val session=SerializedRuntime({_,_,_->emptyList()},{releases++})
        session.close();session.close();assertEquals(1,releases)
        try { session.recognize(byteArrayOf(1),1,1);fail("closed") } catch(e:OcrFailure) {assertEquals(OcrError.INFERENCE_FAILED,e.code)}
    }
}
