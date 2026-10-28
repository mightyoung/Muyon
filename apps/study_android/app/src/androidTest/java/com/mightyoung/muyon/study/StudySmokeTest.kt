package com.mightyoung.muyon.study
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import org.junit.Rule
import org.junit.Test
import org.junit.Assert.*
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import uniffi.muyon_study.StudyEngine

class StudySmokeTest {
    @get:Rule val compose=createAndroidComposeRule<MainActivity>()
    @Test fun create_task_survives_activity_recreation(){
        compose.waitUntil(20000){compose.onAllNodesWithText("待办").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithText("待办").performClick()
        compose.onNodeWithText("任务内容").performTextInput("离线持久化验证")
        compose.onNodeWithText("保存",useUnmergedTree=true).performClick()
        compose.waitUntil(10000){compose.onAllNodesWithText("离线持久化验证").fetchSemanticsNodes().isNotEmpty()}
        compose.activityRule.scenario.recreate()
        compose.waitUntil(15000){compose.onAllNodesWithText("离线持久化验证").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithText("离线持久化验证").assertExists()
    }
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
}
