package com.mightyoung.muyon.product.ui.shell

import com.mightyoung.muyon.product.ui.documents.ReaderDocumentRef

/** Exact host metadata; neither URI nor card/model payload is an authority. */
data class ReaderExactSelection(val document: ReaderDocumentRef, val sourceId: String, val sha256: String) {
    init { require(sourceId.isNotBlank() && sourceId.length <= 128 && '\u0000' !in sourceId); require(sha256.matches(Regex("[0-9a-f]{64}"))) }
}
data class ReaderPhysicalState(val resumed: Boolean, val visible: Boolean, val focused: Boolean, val unsupportedWindowMode: Boolean)
class ReaderRoute internal constructor()
class ReaderSurfaceRequest internal constructor(val surfaceId: String, val generation: Long, val selectionSequence: Long,
    val lifecycleEpoch: Long, val frameSequence: Long, val selection: ReaderExactSelection)
class ReaderVisibilityObservation internal constructor(val sampledAtNanos: Long, val observationId: String,
    val request: ReaderSurfaceRequest) // one dispatch consumes it; not a native grant or deadline
/** One exact host-owned resource. Duplicate replies never close it twice; unknown close is not retried. */
class ReaderSurfaceResource(private val closeExact: () -> Unit) : AutoCloseable {
    private var state = 0 // 0 open, 1 confirmed closed, 2 outcome unknown
    @Synchronized override fun close() {
        if (state == 1) return
        check(state == 0) { "reader_resource_close_unknown" }
        state = 2
        closeExact()
        state = 1
    }
}
sealed class ReaderSurfaceReply {
    data class Opened(val request: ReaderSurfaceRequest, val resource: ReaderSurfaceResource) : ReaderSurfaceReply()
    data class Unavailable(val reason: String) : ReaderSurfaceReply()
}
/** Future private Host adapter must enforce its own serialized native fence; no JSON allow bit. */
interface ReaderSurfaceHost {
    /** Serialized authentic selection event BEFORE asynchronous lookup; not permission issuance. */
    fun acceptSelection(request: ReaderSurfaceRequest, observation: ReaderVisibilityObservation)
    fun open(request: ReaderSurfaceRequest, observation: ReaderVisibilityObservation, receive: (ReaderSurfaceReply) -> Unit)
    fun stopReadingExact(request: ReaderSurfaceRequest, reason: String): Boolean
    fun closeFrameExact(request: ReaderSurfaceRequest, reason: String): Boolean
}
class ReaderSurfaceFence(private val checkOwner: () -> Unit, private val physical: () -> ReaderPhysicalState,
    private val nowNanos: () -> Long, private val host: ReaderSurfaceHost? = null, private val changed: () -> Unit = {},
    private val postOwner: ((() -> Unit) -> Unit) = { it() }) {
    private val surfaceId = java.util.UUID.randomUUID().toString()
    private var route: ReaderRoute? = null
    private var workspace: String? = null
    private var project: String? = null
    private var lifecycleEpoch = 0L
    private var selectionSequence = 0L
    private var frameSequence = 0L
    private var lastPhysical: ReaderPhysicalState? = null
    private var current: ReaderSurfaceRequest? = null
    private var selectionEvent: ReaderSurfaceRequest? = null
    private var inFlight: ReaderSurfaceRequest? = null
    private var ownedResource: ReaderSurfaceResource? = null
    private val failedResources = mutableListOf<ReaderSurfaceResource>()
    private var intentActive = false
    private var destroyed = false
    private var held = false
    var generation = 0L; private set
    var selected: ReaderExactSelection? = null; private set
    var notice = "缺少阅读宿主与策略接口；未获阅读授权。"; private set
    var displayed: ReaderSurfaceRequest? = null; private set

    private fun increment(value: Long): Long = Math.addExact(value, 1L)
    private fun eligible(value: ReaderPhysicalState) = value.resumed && value.visible && value.focused && !value.unsupportedWindowMode
    private fun closeOwned(resource: ReaderSurfaceResource) {
        try { resource.close() } catch (_: Exception) {
            if (!held) generation = increment(generation)
            held = true
            if (failedResources.none { it === resource }) failedResources.add(resource)
            stopCurrent("reader_resource_cleanup_unknown")
            notice = "阅读资源清理结果未知；已停止，不能自动重开。"
            changed()
        }
    }
    private fun stopCurrent(reason: String, terminal: Boolean = true) {
        val requests = if (terminal) listOfNotNull(selectionEvent) else listOfNotNull(inFlight, displayed).distinct()
        if (terminal) selectionEvent = null
        inFlight = null; displayed = null; current = null; intentActive = false
        val resource = ownedResource; ownedResource = null
        // Local output/fence is invalidated before any Host cleanup callback.
        for (request in requests) {
            try { if ((if (terminal) host?.stopReadingExact(request, reason) else host?.closeFrameExact(request, reason)) != true) held = true }
            catch (_: Exception) { held = true }
        }
        resource?.let(::closeOwned)
        if (held) notice = "阅读停止或清理尚未确认；保持暂停，不能自动重开。"
    }
    private fun advance(reason: String, terminal: Boolean = true) {
        generation = increment(generation)
        stopCurrent(reason, terminal)
    }
    private fun refreshPhysical(): ReaderPhysicalState {
        val state = physical()
        if (state != lastPhysical) {
            lastPhysical = state; lifecycleEpoch = increment(lifecycleEpoch)
            advance("activity_visibility_changed")
        }
        return state
    }
    fun enter(workspace: String?, project: String?): ReaderRoute {
        checkOwner(); check(!destroyed)
        advance("reader_route_entered")
        if (this.workspace != workspace || this.project != project) selected = null
        this.workspace = workspace; this.project = project
        return ReaderRoute().also { route = it; refreshPhysical(); changed() }
    }
    fun leave(route: ReaderRoute) {
        checkOwner()
        if (this.route !== route || destroyed) return
        this.route = null; advance("reader_route_left"); changed()
    }
    fun lifecycleEvent() {
        checkOwner(); if (destroyed) return
        refreshPhysical(); changed()
    }
    fun scopeChanged(workspace: String?, project: String?) {
        checkOwner(); if (destroyed || (this.workspace == workspace && this.project == project)) return
        this.workspace = workspace; this.project = project; selected = null
        advance("reader_scope_changed"); changed()
    }
    private fun newRequest(): ReaderSurfaceRequest = ReaderSurfaceRequest(surfaceId, generation,
        selectionSequence, lifecycleEpoch, frameSequence, checkNotNull(selected)).also { current = it }
    fun select(route: ReaderRoute, selection: ReaderExactSelection): ReaderSurfaceRequest? {
        checkOwner()
        if (destroyed || held || this.route !== route) return null
        val actual = refreshPhysical()
        if (!eligible(actual) || workspace == null || selection.document.workspaceId != workspace || selection.document.projectId != project) {
            notice = "当前阅读页面、窗口或精确文档范围不可用；未调用阅读宿主。"; changed(); return null
        }
        advance("reader_selection_changed")
        if (held) { changed(); return null }
        selectionSequence = increment(selectionSequence); frameSequence = 0
        selected = selection; intentActive = true
        notice = "已记录当前文档选择；仍需宿主核实范围与阅读策略。"
        val request = newRequest()
        if (host != null) {
            selectionEvent = request
            try {
                host.acceptSelection(request, ReaderVisibilityObservation(nowNanos(), java.util.UUID.randomUUID().toString(), request))
            } catch (_: Exception) {
                held = true; advance("reader_selection_admission_unknown")
                notice = "阅读选择接纳未确认；保持暂停，不自动重试。"; changed(); return null
            }
        }
        changed(); return request
    }
    fun nextFrame(route: ReaderRoute): ReaderSurfaceRequest? {
        checkOwner()
        if (destroyed || held || this.route !== route || !intentActive || !eligible(refreshPhysical()) || !intentActive) return null
        // Page/frame epoch is separate from the exact document selection sequence.
        advance("reader_frame_changed", terminal = false)
        if (held) { changed(); return null }
        intentActive = true; frameSequence = increment(frameSequence)
        return newRequest().also { changed() }
    }
    fun dispatch(request: ReaderSurfaceRequest): Boolean {
        checkOwner()
        if (destroyed || held || current !== request || inFlight != null || displayed === request || !intentActive || route == null) return false
        val actual = refreshPhysical() // fresh owning-thread physical sample, never cached visible=true
        if (current !== request || !intentActive || !eligible(actual)) return false
        val adapter = host ?: run {
            notice = "当前缺少受信任的阅读范围、principal 与原子 Host/FFI 接口；阅读不可用。"; changed(); return false
        }
        val observation = ReaderVisibilityObservation(nowNanos(), java.util.UUID.randomUUID().toString(), request)
        inFlight = request
        try { adapter.open(request, observation) { reply -> postOwner { receive(request, reply) } } }
        catch (_: Exception) {
            held = true; advance("reader_open_outcome_unknown")
            notice = "阅读打开结果未知；已停止，不自动重试。"; changed(); return false
        }
        return true
    }
    private fun receive(request: ReaderSurfaceRequest, reply: ReaderSurfaceReply) {
        checkOwner() // production poster marshals even delayed Host replies onto this Activity thread
        if (destroyed || held || current !== request || inFlight !== request || !intentActive || route == null) {
            if (reply is ReaderSurfaceReply.Opened && reply.resource !== ownedResource) closeOwned(reply.resource)
            return
        }
        try { refreshPhysical() } catch (_: Exception) {
            held = true; advance("reader_visibility_sample_failed")
        }
        if (held || current !== request || inFlight !== request || !intentActive || route == null) {
            if (reply is ReaderSurfaceReply.Opened && reply.resource !== ownedResource) closeOwned(reply.resource)
            changed(); return
        }
        when (reply) {
            is ReaderSurfaceReply.Opened -> {
                if (reply.request !== request) {
                    // Keep the original inFlight until exact cleanup has captured its identity.
                    held = true; advance("foreign_reader_reply"); closeOwned(reply.resource)
                } else {
                    inFlight = null; ownedResource = reply.resource; displayed = request
                    notice = "宿主返回当前选择的阅读资源；不代表重授权或持续阅读已验收。"
                }
            }
            is ReaderSurfaceReply.Unavailable -> {
                inFlight = null; intentActive = false; current = null
                notice = "阅读宿主当前不可用；未显示文件。"
            }
        }
        changed()
    }
    fun destroy() {
        checkOwner(); if (destroyed) return
        destroyed = true; route = null; advance("activity_destroyed")
        val failures = failedResources.toList(); failedResources.clear()
        failures.forEach(::closeOwned); changed()
    }
}
