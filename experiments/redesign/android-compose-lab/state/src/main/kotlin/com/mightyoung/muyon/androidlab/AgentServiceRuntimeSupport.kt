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
    private var stopSignalled = false
    fun start() {
        synchronized(lock) { if (started || retired) return; started = true; workerActive = true }
        try { backend.execute {
            try {
                val value = construct()
                val discard = synchronized(lock) { controller = value; retired }
                if (discard) {
                    value.retire()
                    synchronized(lock) { stopSignalled = true }
                }
                value.awaitSettled()
                // Retirement may occur while the initializer waiter returns. Handoff and
                // the decision to wait for close share the lock with retire(); native work
                // and listener invocation stay outside it.
                var retirementSettled = discard
                while (true) {
                    val next = synchronized(lock) {
                        if (retired && !stopSignalled) {
                            // retire() owns the signal in progress. It must schedule the
                            // close waiter after that signal returns; an earlier Ready
                            // observation cannot settle a not-yet-signalled close.
                            workerActive = false
                            0
                        } else if (retired && !retirementSettled) 1 else {
                            workerActive = false
                            if (retired) 0 else 2
                        }
                    }
                    if (next == 1) {
                        value.awaitSettled()
                        retirementSettled = true
                    } else {
                        // App install also checks its platform generation before publication.
                        if (next == 2) installed(value)
                        break
                    }
                }
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
            controller
        }
        target?.let { value ->
            value.retire()
            val needsWaiter = synchronized(lock) {
                stopSignalled = true
                if (workerActive) false else { workerActive = true; true }
            }
            if (needsWaiter) backend.execute {
                try { value.awaitSettled() } finally { synchronized(lock) { workerActive = false } }
            }
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
