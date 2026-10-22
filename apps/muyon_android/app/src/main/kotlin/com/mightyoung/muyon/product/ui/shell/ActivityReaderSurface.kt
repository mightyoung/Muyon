package com.mightyoung.muyon.product.ui.shell

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.View
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver

/** Constructed only with the real Activity. Never accepts a caller's visible/principal/current bit. */
class ActivityReaderSurface private constructor(private val activity: ComponentActivity) {
    companion object { fun attach(activity: ComponentActivity) = ActivityReaderSurface(activity) }
    private val handler = Handler(Looper.getMainLooper())
    private var started = false
    private var resumed = false
    private var destroyed = false
    private var workspace: String? = null
    private var project: String? = null
    private var activeRoute: ReaderRoute? = null
    var revision by mutableLongStateOf(0L); private set
    private val fence = ReaderSurfaceFence(::checkMain, ::sampleActualWindow, SystemClock::elapsedRealtimeNanos,
        host = null, // No released scope/principal/reauthorization bridge exists. No fake adapter.
        changed = { revision = Math.addExact(revision, 1L) },
        postOwner = { block ->
            if (Looper.myLooper() == Looper.getMainLooper()) block()
            else check(handler.post { block() }) { "reader_activity_thread_unavailable" }
        })
    private val observer = LifecycleEventObserver { _, event ->
        when (event) {
            Lifecycle.Event.ON_START -> { started = true; fence.lifecycleEvent() }
            Lifecycle.Event.ON_RESUME -> { resumed = true; fence.lifecycleEvent() }
            Lifecycle.Event.ON_PAUSE -> pausing()
            Lifecycle.Event.ON_STOP -> stopping()
            Lifecycle.Event.ON_DESTROY -> destroy()
            else -> Unit
        }
    }
    private val attachment = object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(view: View) { windowChanged() }
        override fun onViewDetachedFromWindow(view: View) { windowChanged() }
    }
    init {
        checkMain()
        activity.window.decorView.addOnAttachStateChangeListener(attachment)
        activity.lifecycle.addObserver(observer)
    }
    private fun checkMain() { check(Looper.myLooper() == Looper.getMainLooper()) { "reader_requires_activity_thread" } }
    private fun sampleActualWindow(): ReaderPhysicalState {
        checkMain()
        return try {
            val view = activity.window.decorView
            ReaderPhysicalState(started && resumed && !destroyed && activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED),
                view.isAttachedToWindow && view.windowVisibility == View.VISIBLE && view.visibility == View.VISIBLE &&
                    !activity.isFinishing && !activity.isDestroyed,
                view.hasWindowFocus(), activity.isInMultiWindowMode || activity.isInPictureInPictureMode)
        } catch (_: Exception) { ReaderPhysicalState(false, false, false, true) }
    }
    fun pausing() { checkMain(); if (!destroyed) { resumed = false; fence.lifecycleEvent() } }
    fun stopping() { checkMain(); if (!destroyed) { resumed = false; started = false; fence.lifecycleEvent() } }
    fun windowChanged() { checkMain(); if (!destroyed) fence.lifecycleEvent() }
    fun bindActualWorkspace(value: String?) {
        checkMain(); if (destroyed) return
        workspace = value?.takeIf { it.isNotBlank() }; fence.scopeChanged(workspace, project)
    }
    fun projectChanged(value: String?) {
        checkMain(); if (destroyed) return
        project = value; fence.scopeChanged(workspace, project)
    }
    fun connectionLost() { bindActualWorkspace(null) }
    fun enter(project: String?): ReaderRoute {
        checkMain(); this.project = project
        return fence.enter(workspace, project).also { activeRoute = it }
    }
    fun leave(route: ReaderRoute) { checkMain(); fence.leave(route); if (activeRoute === route) activeRoute = null }
    fun leaveForNavigation() { checkMain(); activeRoute?.let(::leave) }
    /** Called by the exact host-listed row's actual Compose onClick, not a card/tool JSON route. */
    fun chooseFromUserGesture(route: ReaderRoute, selection: ReaderExactSelection): Boolean {
        checkMain()
        val request = fence.select(route, selection) ?: return false
        return fence.dispatch(request)
    }
    // A real canonical listing source is pending Host. An absent list is NOT an empty-store claim.
    val availableSelections: List<ReaderExactSelection> get() { checkMain(); return emptyList() }
    val catalogUnavailable: String get() = "文档目录与阅读策略接口尚不可用，当前无法选择已核实的文档源。"
    val notice: String get() { checkMain(); return fence.notice }
    val requestGeneration: Long get() { checkMain(); return fence.generation }
    fun destroy() {
        checkMain(); if (destroyed) return
        destroyed = true; resumed = false; started = false
        fence.destroy()
        activity.window.decorView.removeOnAttachStateChangeListener(attachment)
        activity.lifecycle.removeObserver(observer)
        // Keep already posted exact-result cleanup callbacks; they close their own resources after destroy.
    }
}
