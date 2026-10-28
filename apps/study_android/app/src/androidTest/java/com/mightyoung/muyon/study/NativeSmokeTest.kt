package com.mightyoung.muyon.study
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import org.junit.Rule
import org.junit.Test
import org.junit.Assert.*
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import uniffi.muyon_study.StudyEngine

class NativeSmokeTest {
    @Test fun real_native_bridge_imports_mem_and_preserves_attempt(){
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val file=java.io.File(context.cacheDir,"smoke-${System.nanoTime()}.sqlite")
        val engine=StudyEngine.open(file.absolutePath)
        fun call(input:JSONObject):JSONObject{val r=JSONObject(engine.request(input.toString()));assertTrue(r.optString("error"),r.getBoolean("ok"));return r.getJSONObject("data")}
        org.junit.Assume.assumeTrue("Personal question fixture is not supplied",context.assets.list("")?.contains("mem-papers.json")==true)
        val papers=org.json.JSONArray(context.assets.open("mem-papers.json").bufferedReader().use{it.readText()})
        assertEquals(7,call(obj("op" to "import_papers","papers" to papers)).getInt("imported"))
        val a=call(obj("op" to "start_attempt","paper" to "gz2024","mode" to "practice","now" to System.currentTimeMillis()))
        call(obj("op" to "answer","attempt" to a.getString("id"),"question" to "gz2024-q1","value" to "A","index" to 0))
        engine.close()
        val reopened=StudyEngine.open(file.absolutePath)
        val state=JSONObject(reopened.request(obj("op" to "snapshot").toString())).getJSONObject("data")
        assertEquals("A",state.getJSONArray("attempts").getJSONObject(0).getJSONObject("answers").getString("gz2024-q1"))
        reopened.close()
    }
    @Test fun offline_model_is_bundled_with_real_weights(){
        val c=InstrumentationRegistry.getInstrumentation().targetContext
        java.util.zip.ZipInputStream(c.assets.open("model.zip")).use{z->
            var found=false;while(true){val e=z.nextEntry?:break;if(e.name.endsWith("am/final.mdl")){assertTrue(e.size>1000000||e.size<0);found=true;break}};assertTrue(found)
        }
    }

    @Test fun bundled_chinese_model_loads_in_vosk_runtime(){
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val speech=com.mightyoung.muyon.study.adapters.OfflineSpeech(context)
        try {
            val unpack=speech.javaClass.getDeclaredMethod("unpack").apply{isAccessible=true}
            val model=unpack.invoke(speech) as java.io.File
            org.vosk.Model(model.absolutePath).use { assertTrue(java.io.File(model,"am/final.mdl").length()>1000000) }
        } finally { speech.close() }
    }
}
