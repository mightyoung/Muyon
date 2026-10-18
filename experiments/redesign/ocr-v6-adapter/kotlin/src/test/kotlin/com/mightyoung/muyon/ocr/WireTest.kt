package com.mightyoung.muyon.ocr

import kotlinx.serialization.json.Json
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class WireTest {
    @Test fun rust_request_and_kotlin_result_have_identical_wire_geometry() {
        val r=OcrWire.decodeRequest(File("fixtures/request.json").readText())
        assertEquals(200,r.width);assertEquals(1000L,r.expiresAtMs)
        val line=OcrLine("合计 123.45",listOf(Point(20.0,10.0),Point(180.0,10.0),Point(180.0,40.0),Point(20.0,40.0)),.95,null)
        val page=PlatformPage(r.jobId,r.rasterDigest,r.modelVersion,r.parametersVersion,r.width,r.height,listOf(line))
        assertEquals(Json.parseToJsonElement(File("fixtures/platform-page.json").readText()),Json.parseToJsonElement(OcrWire.encodePage(page)))
    }
    @Test fun malformed_and_oversized_request_are_controlled_errors() {
        for(text in listOf("{}","x".repeat(65537),File("fixtures/request.json").readText().replace("\"width\": 200","\"width\": -1"))) {
            try { OcrWire.decodeRequest(text);fail("bad request") } catch(e:OcrFailure) {assertEquals(OcrError.INVALID_REQUEST,e.code)}
        }
    }
}
