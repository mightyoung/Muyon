package com.mightyoung.muyon.ocr

import kotlinx.serialization.json.*

/** Transport codec only. Source/grant checks remain exclusively in the Rust task owner. */
object OcrWire {
    fun decodeRequest(text:String):ExecutionRequest {
        try {
            require(text.toByteArray(Charsets.UTF_8).size<=65536)
            val root=Json.parseToJsonElement(text).jsonObject
            require(root.keys==setOf("jobId","document","raster","modelVersion","parametersVersion","expiresAtMs"))
            val raster=root.getValue("raster").jsonObject
            require(raster.keys==setOf("digest","pageIndex","width","height","exifOrientation","sourceWidth","sourceHeight","coordinateSpace","rasterToSource"))
            val document=root.getValue("document").jsonObject
            require(document.keys==setOf("scope","documentId","revision","sourceDigest","blobRef"))
            val width=raster.getValue("width").jsonPrimitive.int
            val height=raster.getValue("height").jsonPrimitive.int
            require(width in 1..4096 && height in 1..4096 && width.toLong()*height<=16_000_000)
            return ExecutionRequest(root.getValue("jobId").jsonPrimitive.content,
                raster.getValue("digest").jsonPrimitive.content,width,height,
                root.getValue("modelVersion").jsonPrimitive.content,
                root.getValue("parametersVersion").jsonPrimitive.content,
                root.getValue("expiresAtMs").jsonPrimitive.long)
        } catch(e:Exception) { throw OcrFailure(OcrError.INVALID_REQUEST) }
    }
    fun encodePage(page:PlatformPage):String {
        // Arrays, not {x,y} objects: this is the Rust [[f64;2];4] wire representation.
        return buildJsonObject {
            put("jobId",page.jobId);put("rasterDigest",page.rasterDigest)
            put("modelVersion",page.modelVersion);put("parametersVersion",page.parametersVersion)
            put("width",page.width);put("height",page.height)
            putJsonArray("lines") {
                page.lines.forEach { line -> addJsonObject {
                    put("text",line.text);put("recognitionConfidence",line.recognitionConfidence)
                    put("detectionConfidence",line.detectionConfidence?.let(::JsonPrimitive) ?: JsonNull)
                    putJsonArray("quad") { line.quad.forEach { p -> add(buildJsonArray {add(p.x);add(p.y)}) } }
                } }
            }
        }.toString()
    }
}
