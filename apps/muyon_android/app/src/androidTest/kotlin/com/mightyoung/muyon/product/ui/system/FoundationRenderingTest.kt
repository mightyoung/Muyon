package com.mightyoung.muyon.product.ui.system

import android.graphics.Bitmap
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** Real Compose rendering capture target. Generic labels are component examples, never business records. */
class FoundationRenderingTest {
    @get:Rule val compose = createComposeRule()

    private fun render(dark: Boolean, scale: Float) {
        compose.setContent {
            val density = LocalDensity.current.density
            CompositionLocalProvider(LocalDensity provides Density(density, scale)) {
                FoundationTheme(dark = dark, reduceMotion = true) {
                    Column(Modifier.fillMaxSize().background(LocalFoundationPalette.current.background)
                        .testTag("foundation-gallery").verticalScroll(rememberScrollState()).padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        FoundationButton("Primary", null)
                        FoundationButton("Loading", null, state = ActionState.Loading, stateLabel = "Processing")
                        FoundationButton("Unknown", null, state = ActionState.Unknown, stateLabel = "Check original receipt")
                        FoundationTextField("Local draft", null, "Name")
                        FoundationSelection("Local selection", true, null)
                        FoundationTag("Component example")
                        FoundationFeedback(FeedbackKind.Error, "Load failed", "Retain existing content")
                        FoundationFeedback(FeedbackKind.Unknown, "Unknown result", "Query original receipt before retry")
                        FoundationFeedback(FeedbackKind.Partial, "Partly complete", "Total unknown")
                        FoundationFeedback(FeedbackKind.Loading, "Processing", "No completion estimate")
                        FoundationEmptyState("No content", "Choose a supported local file")
                    }
                }
            }
        }
        val folder = File(InstrumentationRegistry.getInstrumentation().targetContext.getExternalFilesDir(null), "foundation-rendering")
        assertTrue(folder.isDirectory || folder.mkdirs())
        val mode = if (dark) "dark" else "light"
        val tag = compose.onNodeWithTag("foundation-gallery")
        val top = tag.captureToImage()
        File(folder, "$mode-$scale-top.png").outputStream().use { assertTrue(top.asAndroidBitmap().compress(Bitmap.CompressFormat.PNG, 100, it)) }
        compose.onNodeWithText("No content").performScrollTo().assertIsDisplayed()
        val bottom = tag.captureToImage()
        File(folder, "$mode-$scale-bottom.png").outputStream().use { assertTrue(bottom.asAndroidBitmap().compress(Bitmap.CompressFormat.PNG, 100, it)) }
    }

    @Test fun lightNormal() = render(false, 1f)
    @Test fun lightLarge() = render(false, 2f)
    @Test fun darkNormal() = render(true, 1f)
    @Test fun darkLarge() = render(true, 2f)
}
