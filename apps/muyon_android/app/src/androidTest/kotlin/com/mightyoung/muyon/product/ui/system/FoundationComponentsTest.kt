package com.mightyoung.muyon.product.ui.system

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.Modifier
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class FoundationComponentsTest {
    @get:Rule val compose = createComposeRule()

    @Test fun unresolvedActionsCannotInvokeHost() {
        var calls = 0
        compose.setContent {
            FoundationTheme {
                Column {
                    FoundationButton("Disabled", { calls++ }, state = ActionState.Disabled, stateLabel = "Unavailable")
                    FoundationButton("Loading", { calls++ }, state = ActionState.Loading, stateLabel = "Working")
                    FoundationButton("Unknown", { calls++ }, state = ActionState.Unknown, stateLabel = "Query original receipt")
                    FoundationButton("Missing", null)
                }
            }
        }
        listOf("Disabled", "Loading", "Unknown", "Missing").forEach {
            compose.onNodeWithText(it).assertIsNotEnabled()
        }
        compose.runOnIdle { assertEquals(0, calls) }
    }

    @Test fun selectionEditsLocalValueAndExposesCheckedState() {
        compose.setContent {
            var selected by remember { mutableStateOf(false) }
            FoundationTheme { FoundationSelection("Local selection", selected, { selected = it }) }
        }
        compose.onNodeWithText("Local selection").assertIsOff().performClick().assertIsOn()
    }

    @Test fun largeTextKeepsErrorAndUnknownDistinctAndExistingContentVisible() {
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(1f, 2f)) {
                FoundationTheme(dark = true) {
                    Column(Modifier.verticalScroll(rememberScrollState())) {
                        FoundationTag("Existing content")
                        FoundationFeedback(FeedbackKind.Error, "Load failed", "Existing content retained")
                        FoundationFeedback(FeedbackKind.Unknown, "Result unknown", "Query original intent receipt")
                        FoundationTextField("Draft", null, "Name", state = ActionState.Error, supportingText = "Required field")
                    }
                }
            }
        }
        listOf("Existing content", "Load failed", "Result unknown", "Required field").forEach {
            compose.onNodeWithText(it).performScrollTo().assertIsDisplayed()
        }
    }

    @Test fun loadingFieldRetainsDraftAndCannotEdit() {
        var value = "Original draft"
        compose.setContent {
            FoundationTheme {
                FoundationTextField(value, { value = it }, "Name", state = ActionState.Loading, supportingText = "Working")
            }
        }
        compose.onNodeWithText("Original draft").assertIsNotEnabled()
        compose.runOnIdle { assertEquals("Original draft", value) }
    }

    @Test fun menuSelectionIsExplicitAndDismissesThroughHost() {
        var chosen: String? = null
        compose.setContent {
            var expanded by remember { mutableStateOf(true) }
            FoundationTheme {
                FoundationMenu(expanded, listOf(FoundationMenuItem("local", "Local choice")), {
                    chosen = it; expanded = false
                }, { expanded = false })
            }
        }
        compose.onNodeWithText("Local choice").performClick()
        compose.runOnIdle { assertEquals("local", chosen) }
        compose.onNodeWithText("Local choice").assertDoesNotExist()
    }

    @Test fun dialogCancelUsesDismissAndUnavailableConfirmIsDisabled() {
        compose.setContent {
            var open by remember { mutableStateOf(true) }
            FoundationTheme {
                if (open) FoundationDialog("Component dialog", { open = false }, "Confirm", null, "Cancel") {
                    FoundationTag("Local draft remains with host")
                }
            }
        }
        compose.onNodeWithText("Confirm").assertIsNotEnabled()
        compose.onNodeWithText("Cancel").performClick()
        compose.onNodeWithText("Component dialog").assertDoesNotExist()
    }
}
