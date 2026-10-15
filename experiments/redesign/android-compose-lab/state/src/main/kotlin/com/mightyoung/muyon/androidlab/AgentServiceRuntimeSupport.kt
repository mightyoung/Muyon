package com.mightyoung.muyon.androidlab
import java.util.concurrent.Executor

/** Lifecycle seam only; actual generated controller adaptation is app/Service-only. */
interface AgentControllerLifetime { fun retire(); fun awaitSettled() }
class AgentServiceBootstrap(private val backend: Executor, private val construct: () -> AgentControllerLifetime,
    private val installed: (AgentControllerLifetime) -> Unit, private val unavailable: () -> Unit) {
    fun start() = Unit
    fun retire() = Unit
}
/** Observation and control never share a possibly blocked RPC execution lane. */
class AgentRpcLanes(private val observation: Executor, private val control: Executor) {
    fun observe(work: () -> Unit): Boolean = false
    fun control(work: () -> Unit): Boolean = false
}
