package com.mightyoung.muyon.ocr

import android.content.Context
import android.graphics.BitmapFactory
import android.os.Build
import android.os.SystemClock
import com.paddle.ocr.PaddleOCR
import com.paddle.ocr.PaddleOCRConfig
import com.paddle.ocr.EngineConfig
import com.paddle.ocr.util.OpenCVUtils

/** Service-side platform construction seam. No task, file grant, persistence or index authority. */
object OfficialOcrAdapter {
    private const val DET="ocr-v6/tiny/det/inference.onnx"
    private const val REC="ocr-v6/tiny/rec/inference.onnx"
    private const val DICT="ocr-v6/tiny/rec/inference.yml"
    private val assets=listOf(
        Asset(DET,1780590,"193bab7a04fca699a6c82e6abb5b81bdb28177f0abd4062552b04908dafb19f8"),
        Asset(REC,4462639,"9ef676d6ed3c88256a2d92c640c44f25b0c40947e111b14b8be8f594091563e6"),
        Asset(DICT,55571,"66170210bad538e83fff3c4a3867e547d6bf20b50d64b20347c4b913f3034ea1"),
    )
    fun forService(context:Context): OcrExecutor {
        val app=context.applicationContext
        return OcrExecutor(assets,{app.assets.open(it)}, {
            // This factory is unreachable through execute() on API24/25; no eager native initialization.
            check(Build.VERSION.SDK_INT>=26)
            if(!OpenCVUtils.init(app)) throw OcrFailure(OcrError.INFERENCE_FAILED)
            officialRuntime(PaddleOCR.create(app,PaddleOCRConfig(),EngineConfig(numThreads=2),DET,REC,DICT))
        },{SystemClock.elapsedRealtime()})
    }
}

/** The shared tested owner handles repeated release; Android code only decodes/maps. */
private fun officialRuntime(paddle:PaddleOCR): OcrRuntime = SerializedRuntime({image,width,height ->
    val bounds=BitmapFactory.Options().apply {inJustDecodeBounds=true}
    BitmapFactory.decodeByteArray(image,0,image.size,bounds)
    // W1 must supply orientation-normalized PNG pixels; no implicit EXIF/PDF transforms here.
    if(bounds.outWidth!=width || bounds.outHeight!=height || bounds.outMimeType!="image/png")
        throw OcrFailure(OcrError.INVALID_REQUEST)
    paddle.recognize(image).results.map { line ->
        OcrLine(line.text,line.box.points.map { Point(it.x.toDouble(),it.y.toDouble()) },line.confidence.toDouble(),null)
    }
},{paddle.release()})
