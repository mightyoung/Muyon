package com.mightyoung.muyon.study

import android.os.Bundle
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import uniffi.muyon_study.StudyEngine

/** Black-box accessibility actions avoid coupling application checks to Compose's frame clock. */
class StudySmokeTest {
    private val instrumentation get()=InstrumentationRegistry.getInstrumentation()
    private fun node(predicate:(AccessibilityNodeInfo)->Boolean):AccessibilityNodeInfo? {
        val root=instrumentation.uiAutomation.rootInActiveWindow?:return null
        val pending=java.util.ArrayDeque<AccessibilityNodeInfo>();pending.add(root)
        while(pending.isNotEmpty()){
            val n=pending.removeFirst();if(predicate(n))return n
            for(i in 0 until n.childCount)n.getChild(i)?.let{pending.add(it)}
        }
        return null
    }
    private fun waitNode(predicate:(AccessibilityNodeInfo)->Boolean):AccessibilityNodeInfo {
        val deadline=android.os.SystemClock.uptimeMillis()+60000
        while(android.os.SystemClock.uptimeMillis()<deadline){node(predicate)?.let{return it};Thread.sleep(150)}
        error("UI element was not available within 60 seconds")
    }
    private fun click(text:String){
        var n:AccessibilityNodeInfo?=waitNode{it.text?.toString()==text}
        while(n!=null&&!n.isClickable)n=n.parent
        assertNotNull("Clickable $text",n);assertTrue(n!!.performAction(AccessibilityNodeInfo.ACTION_CLICK))
    }
    private fun snapshot():JSONObject {
        val c=instrumentation.targetContext
        val engine=StudyEngine.open(java.io.File(c.filesDir,"study-v1.sqlite").absolutePath)
        try{val r=JSONObject(engine.request(obj("op" to "snapshot").toString()));assertTrue(r.optString("error"),r.getBoolean("ok"));return r.getJSONObject("data")}finally{engine.close()}
    }
    @Test fun create_task_survives_activity_recreation(){
        val title="UI_SMOKE_${System.nanoTime()}"
        ActivityScenario.launch(MainActivity::class.java).use{scenario->
            click("待办")
            val field=waitNode{it.isEditable}
            assertTrue(field.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,Bundle().apply{putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,title)}))
            click("保存")
            val deadline=android.os.SystemClock.uptimeMillis()+60000
            while(snapshot().items("tasks").none{it.optString("title")==title}&&android.os.SystemClock.uptimeMillis()<deadline)Thread.sleep(150)
            assertTrue(snapshot().items("tasks").any{it.optString("title")==title})
            scenario.recreate()
            waitNode{it.text?.toString()=="待办"}
            assertTrue(snapshot().items("tasks").any{it.optString("title")==title})
        }
    }
}
