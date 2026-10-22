package com.mightyoung.muyon.product.ui.shell

import com.mightyoung.muyon.product.ui.documents.DocumentFormat
import com.mightyoung.muyon.product.ui.documents.ReaderDocumentRef

private class SurfaceTestHost : ReaderSurfaceHost {
    val selections = mutableListOf<ReaderSurfaceRequest>()
    override fun acceptSelection(request: ReaderSurfaceRequest, observation: ReaderVisibilityObservation) { selections += request; check(observation.request === request) }
    val opened = mutableListOf<ReaderSurfaceRequest>()
    val stopped = mutableListOf<ReaderSurfaceRequest>()
    val retiredFrames = mutableListOf<ReaderSurfaceRequest>()
    val callbacks = mutableMapOf<ReaderSurfaceRequest, (ReaderSurfaceReply) -> Unit>()
    val observations = mutableListOf<ReaderVisibilityObservation>()
    var cleanupKnown = true
    override fun open(request: ReaderSurfaceRequest, observation: ReaderVisibilityObservation, receive: (ReaderSurfaceReply) -> Unit) {
        check(selections.lastOrNull()?.let { it.surfaceId == request.surfaceId && it.selectionSequence == request.selectionSequence && it.selection == request.selection } == true) { "selection must be accepted before any open" }
        opened += request; observations += observation; callbacks[request] = receive
    }
    override fun stopReadingExact(request: ReaderSurfaceRequest, reason: String): Boolean { stopped += request; return cleanupKnown }
    override fun closeFrameExact(request: ReaderSurfaceRequest, reason: String): Boolean { retiredFrames += request; return cleanupKnown }
}
private class SurfaceTestResource {
    var closes = 0
    var fail = false
    val resource = ReaderSurfaceResource { closes++; if (fail) error("synthetic close unknown") }
}
fun main() {
    var state = ReaderPhysicalState(true, true, true, false)
    var clock = 1L
    var owner = true
    val host = SurfaceTestHost()
    val posted = mutableListOf<() -> Unit>()
    val fence = ReaderSurfaceFence({ check(owner) }, { state }, { ++clock }, host, postOwner = { block -> if (owner) block() else posted.add(block) })
    fun ref(id: String, revision: String = "1") = ReaderExactSelection(ReaderDocumentRef("w", "p", id, revision, DocumentFormat.PDF), "blob-$id-$revision", "a".repeat(64))
    val route = fence.enter("w", "p")
    val a1 = checkNotNull(fence.select(route, ref("a"))) { "visible user selection must create local exact intent" }
    val b = checkNotNull(fence.select(route, ref("b")))
    check(host.selections == listOf(a1, b))
    check(!fence.dispatch(a1) && host.opened.isEmpty()) // reject BEFORE any Host/destructive open
    check(fence.dispatch(b) && host.opened.single() === b)
    check(!fence.dispatch(b) && host.opened.size == 1) // one request/observation cannot be reused
    val rb = SurfaceTestResource(); host.callbacks.getValue(b)(ReaderSurfaceReply.Opened(b, rb.resource))
    check(fence.displayed === b)
    val a3 = checkNotNull(fence.select(route, ref("a")))
    check(a3.selection == a1.selection && a3.selectionSequence > a1.selectionSequence)
    check(rb.closes == 1 && host.stopped.contains(b))
    host.callbacks.getValue(b)(ReaderSurfaceReply.Opened(b, rb.resource))
    check(rb.closes == 1) // repeated stale exact resource is idempotent
    check(!fence.dispatch(a1) && fence.dispatch(a3))
    val selectionsBeforeFrame = host.selections.size
    val aFrame2 = checkNotNull(fence.nextFrame(route))
    check(aFrame2.selectionSequence == a3.selectionSequence && aFrame2.frameSequence > a3.frameSequence)
    check(host.retiredFrames.contains(a3) && !host.stopped.contains(a3))
    check(fence.dispatch(aFrame2))
    check(host.selections.size == selectionsBeforeFrame)
    val frame2 = SurfaceTestResource(); host.callbacks.getValue(aFrame2)(ReaderSurfaceReply.Opened(aFrame2, frame2.resource))
    val late = SurfaceTestResource(); host.callbacks.getValue(a3)(ReaderSurfaceReply.Opened(a3, late.resource))
    check(late.closes == 1 && frame2.closes == 0 && fence.displayed === aFrame2)
    owner = false
    host.callbacks.getValue(aFrame2)(ReaderSurfaceReply.Opened(aFrame2, frame2.resource))
    check(frame2.closes == 0 && posted.size == 1)
    owner = true; posted.removeAt(0).invoke()
    check(frame2.closes == 0 && fence.displayed === aFrame2) // background duplicate never closes active frame
    val priorGeneration = fence.generation
    state = state.copy(resumed = false); fence.lifecycleEvent()
    check(fence.generation > priorGeneration && frame2.closes == 1 && fence.displayed == null)
    check(host.stopped.last() === a3 && !host.stopped.contains(aFrame2)) // stop exact reading selection, not a page as a new chain
    val before = host.opened.size
    state = state.copy(resumed = true); fence.lifecycleEvent()
    check(!fence.dispatch(aFrame2) && fence.nextFrame(route) == null && host.opened.size == before) // never auto-resume
    val foreground = checkNotNull(fence.select(route, ref("a")))
    state = state.copy(focused = false) // fresh owning-thread sample catches even a missing callback
    check(!fence.dispatch(foreground) && host.opened.size == before)
    state = state.copy(focused = true); fence.lifecycleEvent()
    val focused = checkNotNull(fence.select(route, ref("a")))
    check(fence.dispatch(focused))
    check(host.observations.map { it.observationId }.distinct().size == host.observations.size)
    check(host.observations.zipWithNext().all { (x, y) -> y.sampledAtNanos > x.sampledAtNanos })
    val otherRoute = fence.enter("w", "p")
    val current = checkNotNull(fence.select(otherRoute, ref("b")))
    fence.leave(route) // stale dispose never closes a new route
    check(fence.dispatch(current))
    fence.scopeChanged("w", "other")
    check(!fence.dispatch(current) && fence.nextFrame(otherRoute) == null)
    check(fence.select(otherRoute, ref("b")) == null) // exact scope, no latest-ref substitution
    fence.destroy()
    val destroyed = SurfaceTestResource(); host.callbacks.getValue(current)(ReaderSurfaceReply.Opened(current, destroyed.resource))
    check(destroyed.closes == 1)
    check(runCatching { owner = false; fence.lifecycleEvent() }.isFailure)

    state = ReaderPhysicalState(true, true, true, false); owner = true
    val unavailable = ReaderSurfaceFence({}, { state }, { clock })
    val unavailableRoute = unavailable.enter("w", "p")
    val localOnly = checkNotNull(unavailable.select(unavailableRoute, ref("a")))
    check(!unavailable.dispatch(localOnly) && unavailable.displayed == null)
    state = state.copy(unsupportedWindowMode = true)
    check(unavailable.select(unavailableRoute, ref("a")) == null)
    state = state.copy(unsupportedWindowMode = false)
    val holdHost = SurfaceTestHost().also { it.cleanupKnown = false }
    val hold = ReaderSurfaceFence({}, { state }, { clock }, holdHost)
    val holdRoute = hold.enter("w", "p")
    check(hold.dispatch(checkNotNull(hold.select(holdRoute, ref("a")))))
    hold.leave(holdRoute)
    val newRoute = hold.enter("w", "p")
    check(hold.select(newRoute, ref("b")) == null) // uncertain cleanup never silently resets hold
    val cleanupHost = SurfaceTestHost()
    val cleanup = ReaderSurfaceFence({}, { state }, { clock }, cleanupHost)
    val cleanupRoute = cleanup.enter("w", "p")
    val old = checkNotNull(cleanup.select(cleanupRoute, ref("a"))); check(cleanup.dispatch(old))
    val newest = checkNotNull(cleanup.select(cleanupRoute, ref("b"))); check(cleanup.dispatch(newest))
    val newestResource = SurfaceTestResource()
    cleanupHost.callbacks.getValue(newest)(ReaderSurfaceReply.Opened(newest, newestResource.resource))
    val bad = SurfaceTestResource().also { it.fail = true }
    cleanupHost.callbacks.getValue(old)(ReaderSurfaceReply.Opened(old, bad.resource))
    check(bad.closes == 1 && newestResource.closes == 1 && cleanup.displayed == null && cleanupHost.stopped.contains(newest))
    check(cleanup.select(cleanupRoute, ref("a")) == null)
    cleanup.destroy(); check(bad.closes == 1) // unknown close is retained, never blindly retried
    val foreignHost = SurfaceTestHost()
    val foreign = ReaderSurfaceFence({}, { state }, { clock }, foreignHost)
    val foreignRoute = foreign.enter("w", "p")
    val requested = checkNotNull(foreign.select(foreignRoute, ref("a"))); check(foreign.dispatch(requested))
    val foreignResource = SurfaceTestResource()
    foreignHost.callbacks.getValue(requested)(ReaderSurfaceReply.Opened(old, foreignResource.resource))
    check(foreignHost.stopped.contains(requested) && foreignResource.closes == 1 && foreign.displayed == null)
    println("PASS reader surface fence: exact A/B/A and frame identity; stale pre-Host zero calls; owning-thread fresh sample; background/focus/scope/route/destroy cleanup; no auto-resume; unavailable and cleanup hold")
}
