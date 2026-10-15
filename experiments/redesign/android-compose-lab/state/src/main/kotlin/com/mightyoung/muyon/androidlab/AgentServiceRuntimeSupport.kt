package com.mightyoung.muyon.androidlab

import java.util.concurrent.Executor
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean

/** Lifecycle seam only; actual generated controller adaptation is app/Service-only. */
interface AgentControllerLifetime { fun retire(); fun awaitSettled() }
class AgentServiceBootstrap(private val backend: Executor, private val construct: () -> AgentControllerLifetime,
    private val installed: (AgentControllerLifetime) -> Unit, private val unavailable: () -> Unit) {
    private val lock = Any()
    private var started = false
    private var retired = false
    private var controller: AgentControllerLifetime? = null
    private var workerActive = false
    fun start() {
        synchronized(lock) { if (started || retired) return; started = true; workerActive = true }
        try { backend.execute {
            try {
                val value = construct()
                val discard = synchronized(lock) { controller = value; retired }
                if (discard) value.retire()
                value.awaitSettled()
                // The app's install callback also checks its platform generation before publication.
                if (!synchronized(lock) { retired }) installed(value)
            } catch (_: Exception) {
                if (!synchronized(lock) { retired }) unavailable()
            } finally { synchronized(lock) { workerActive = false } }
        } } catch (_: RejectedExecutionException) {
            synchronized(lock) { workerActive = false }
            unavailable()
        }
    }
    fun retire() {
        val target = synchronized(lock) {
            if (retired) return
            retired = true
            controller?.let { it to workerActive }
        }
        target?.let { (value, active) ->
            value.retire()
            if (!active) backend.execute { value.awaitSettled() }
        }
    }
}
/** Admission is capacity one per lane: no queued observations, independent prompt controls. */
class AgentRpcLanes(private val observation: Executor, private val control: Executor) {
    private val observing = AtomicBoolean()
    private val controlling = AtomicBoolean()
    fun observe(work: () -> Unit) = submit(observing, observation, work)
    fun control(work: () -> Unit) = submit(controlling, control, work)
    private fun submit(slot: AtomicBoolean, executor: Executor, work: () -> Unit): Boolean {
        if (!slot.compareAndSet(false, true)) return false
        try { executor.execute { try { work() } finally { slot.set(false) } } }
        catch (_: RejectedExecutionException) { slot.set(false); return false }
        return true
    }
}
