package com.mightyoung.muyon.androidlab

import android.os.Handler
import android.os.Looper
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.assertTextContains
import org.junit.Rule
import org.junit.Test

/** Source-only UI wiring checks with an explicitly synthetic port; not native/runtime evidence. */
class DiagnosticComposeTest {
    @get:Rule val compose = createComposeRule()
    private fun coordinator(native: DiagnosticNativePort): RustDiagnosticCoordinator {
        val handler = Handler(Looper.getMainLooper())
        return createRustDiagnosticCoordinator(native) { deliver -> handler.post { deliver() } }
    }
    @Test fun missingLibraryStaysSeparateFromDisconnectedBusinessControls() {
        val diagnostics = coordinator(object : DiagnosticNativePort {
            override fun bridgeInfo(): UiBridgeInfo = throw DiagnosticNativeFailure(DiagnosticError.NATIVE_LOAD)
            override fun validateBundledContract(request: UiDiagnosticRequest): UiDiagnosticReport = error("not ready")
        })
        compose.setContent { MuyonLabShell(diagnostics = diagnostics) }
        compose.onNodeWithTag("assistant-draft").performTextInput("未发送内容")
        compose.onNodeWithTag("destination-SETTINGS").performClick()
        compose.onNodeWithTag("open-rust-diagnostic").performScrollTo().performClick()
        compose.onNodeWithTag("rust-variant-EQUIPMENT").assertIsNotEnabled()
        compose.onNodeWithTag("rust-diagnostic-handshake").performClick()
        compose.waitUntil(5_000) { compose.onAllNodesWithTag("rust-diagnostic-unavailable").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("rust-diagnostic-close").performScrollTo().performClick()
        compose.onNodeWithTag("destination-ASSISTANT").performClick()
        compose.onNodeWithTag("send-unavailable").assertIsNotEnabled()
        compose.onNodeWithTag("assistant-draft").assertTextContains("未发送内容")
    }
    @Test fun syntheticDiagnosticCompletionDoesNotBecomeChatOrEnableModel() {
        val build = "a".repeat(40)
        val diagnostics = coordinator(object : DiagnosticNativePort {
            override fun bridgeInfo() = UiBridgeInfo(1u, build, UiDiagnosticCapability.BUNDLED_DECLARATION_VALIDATION, false,false,false,false,false)
            override fun validateBundledContract(request: UiDiagnosticRequest) = UiDiagnosticReport(1u,request.requestId,build,request.variant,"synthetic-ui-test",1uL,2u,1u,1u,1u)
        })
        compose.setContent { MuyonLabShell(diagnostics = diagnostics) }
        compose.onNodeWithTag("destination-SETTINGS").performClick()
        compose.onNodeWithTag("open-rust-diagnostic").performScrollTo().performClick()
        compose.onNodeWithTag("rust-diagnostic-handshake").performClick()
        compose.waitUntil(5_000) { compose.onAllNodesWithTag("rust-diagnostic-ready").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("rust-variant-EQUIPMENT").performScrollTo().performClick()
        compose.waitUntil(5_000) { compose.onAllNodesWithTag("rust-diagnostic-result").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("rust-diagnostic-close").performScrollTo().performClick()
        compose.onNodeWithTag("destination-ASSISTANT").performClick()
        compose.onNodeWithTag("chat-note-1").assertDoesNotExist()
        compose.onNodeWithTag("send-unavailable").assertIsNotEnabled()
        compose.onNodeWithTag("input-options").performClick()
        compose.onNodeWithTag("model-unavailable").assertIsNotEnabled()
        compose.onNodeWithTag("attachment-unavailable").assertIsNotEnabled()
    }
}
