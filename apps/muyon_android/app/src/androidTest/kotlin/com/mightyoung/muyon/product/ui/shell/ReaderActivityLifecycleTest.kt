package com.mightyoung.muyon.product.ui.shell

import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.Lifecycle
import com.mightyoung.muyon.product.MainActivity
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** Real Activity callbacks, not a policy/native/continuous-reading success fixture. Requires actual APK/device. */
class ReaderActivityLifecycleTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    @Test fun actualLifecycleAdvancesLocalFenceAndDoesNotCreateDocumentsOrAuthority() {
        lateinit var surface: ActivityReaderSurface
        lateinit var route: ReaderRoute
        var resumedGeneration = 0L
        compose.activityRule.scenario.onActivity { activity ->
            surface = ActivityReaderSurface.attach(activity)
            route = surface.enter(null) // no fabricated workspace, principal, document or Host
            resumedGeneration = surface.requestGeneration
            assertTrue(surface.availableSelections.isEmpty())
            assertTrue(surface.catalogUnavailable.isNotBlank())
        }
        compose.activityRule.scenario.moveToState(Lifecycle.State.STARTED)
        compose.activityRule.scenario.onActivity {
            assertTrue(surface.requestGeneration > resumedGeneration)
            resumedGeneration = surface.requestGeneration
        }
        compose.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
        compose.activityRule.scenario.onActivity {
            assertTrue(surface.requestGeneration > resumedGeneration)
            val beforeExit = surface.requestGeneration
            surface.leave(route)
            assertTrue(surface.requestGeneration > beforeExit)
            val next = surface.enter(null)
            val beforeStaleDispose = surface.requestGeneration
            surface.leave(route)
            assertTrue(surface.requestGeneration == beforeStaleDispose)
            surface.leave(next)
            surface.destroy()
        }
    }
}
