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
}
