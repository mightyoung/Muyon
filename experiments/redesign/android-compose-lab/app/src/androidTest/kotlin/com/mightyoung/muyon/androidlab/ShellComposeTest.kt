package com.mightyoung.muyon.androidlab

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import org.junit.Rule
import org.junit.Test

/** Source-only until an explicitly authorized Android test run. No backend fixture. */
class ShellComposeTest {
    @get:Rule val compose = createComposeRule()

    @Test fun draftAndFocusSurviveNavigationAndRailChange() {
        var width by mutableFloatStateOf(899f)
        compose.setContent { MuyonLabShell(windowWidthDp = width) }
        compose.onNodeWithTag("bottom-nav").assertExists()
        compose.onNodeWithTag("assistant-draft").performClick().performTextInput("未发送 e\u0301")
        compose.onNodeWithTag("destination-TASKS").performClick()
        compose.onNodeWithTag("assistant-draft").assertDoesNotExist()
        compose.onNodeWithTag("destination-ASSISTANT").performClick()
        compose.onNodeWithTag("assistant-draft").assert(SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString("未发送 e\u0301"))).assertIsFocused()
        compose.runOnIdle { width = 900f }
        compose.onNodeWithTag("bottom-nav").assertDoesNotExist()
        compose.onNodeWithTag("rail").assertExists()
        compose.onNodeWithTag("assistant-draft").assert(SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString("未发送 e\u0301"))).assertIsFocused()
        compose.onNodeWithTag("port-disconnected").assertExists()
    }
}
