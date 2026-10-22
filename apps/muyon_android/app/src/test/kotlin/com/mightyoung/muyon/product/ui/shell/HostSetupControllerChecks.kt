package com.mightyoung.muyon.product.ui.shell

import com.mightyoung.muyon.product.chat.*
import java.lang.reflect.Proxy
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.json.JSONObject

fun main() {
    val port = Proxy.newProxyInstance(ProductChatPort::class.java.classLoader, arrayOf(ProductChatPort::class.java)) { _, method, _ ->
        error("native port forbidden in local setup: ${method.name}")
    } as ProductChatPort
    val runtime = ProductChatRuntime(port, ProductChatExchange { _, _, _, _, _ -> error("NETWORK FORBIDDEN") })
    fun waitCall(block: ((JSONObject) -> Unit) -> Unit): JSONObject {
        val latch = CountDownLatch(1); var result: JSONObject? = null
        block { result = it; latch.countDown() }; check(latch.await(5, TimeUnit.SECONDS)); return checkNotNull(result)
    }
    try {
        val generation = waitCall { runtime.updateScope("session", "p", it) }.getLong("scope_generation")
        val scope = HostSetupScope("w", "c", "p", generation)
        val monitor = Object()
        var calls = 0
        var tamperNext = false
        var loseNext = false
        var holdNext = false
        var held: (() -> Unit)? = null
        val route: (String, JSONObject, (JSONObject) -> Unit) -> Unit = { method, payload, callback ->
            check(method == "chat_setup_draft"); calls++
            runtime.setupDraft("session", "w", payload.getString("conversation_id"), "p", generation,
                payload.getJSONObject("operation")) { inner ->
                val detached = JSONObject(inner.toString())
                if (tamperNext) { tamperNext = false; detached.put("name", "同版本伪造名称") }
                val reply = JSONObject().put("status", "ok").put("data", detached)
                when {
                    loseNext -> { loseNext = false; callback(JSONObject().put("status", "unknown")) }
                    holdNext -> { holdNext = false; held = { callback(reply) }; synchronized(monitor) { monitor.notifyAll() } }
                    else -> callback(reply)
                }
            }
        }
        val controller = HostSetupController(scope, route, { synchronized(monitor) { monitor.notifyAll() } })
        fun idle() { synchronized(monitor) {
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
            while (controller.busy && System.nanoTime() < deadline) monitor.wait(20)
            check(!controller.busy) { "local host callback missing" }
        } }
        controller.open(); idle()
        val opened = checkNotNull(controller.snapshot) { "host open must publish actual local snapshot" }
        check(opened.step == "NAME" && opened.name.isEmpty() && opened.revision == 0L)
        check(!controller.mutate(opened, "create")); check(calls == 1)
        check(controller.mutate(opened, "edit_name", "真正名称")); idle()
        val named = checkNotNull(controller.snapshot)
        check(named.name == "真正名称" && named.id == opened.id && named.revision == 1L)
        val beforeStale = calls
        check(!controller.mutate(opened, "edit_name", "旧卡片覆盖")); check(calls == beforeStale)
        check(controller.mutate(named, "next")); idle()
        check(controller.snapshot?.step == "PURPOSE")
        check(controller.mutate(checkNotNull(controller.snapshot), "edit_purpose", "整理论文")); idle()
        check(controller.mutate(checkNotNull(controller.snapshot), "suggest_role")); idle()
        val suggested = checkNotNull(controller.snapshot)
        val token = checkNotNull(suggested.suggestion).requestId
        check(!canAcceptHostSuggestion(suggested, "用户尚未应用的手工角色"))
        check(controller.mutate(suggested, "accept_role", suggestionToken = token)); idle()
        check(controller.snapshot?.role == "文献整理助手")
        loseNext = true
        val beforeUnknown = calls
        check(controller.mutate(checkNotNull(controller.snapshot), "edit_role", "手工最终角色")); idle()
        check(controller.needsRead && calls == beforeUnknown + 1)
        check(!controller.mutate(checkNotNull(controller.snapshot), "next"))
        controller.readOriginal(); idle()
        check(!controller.needsRead && controller.snapshot?.role == "手工最终角色")
        check(controller.snapshot?.id == opened.id && calls == beforeUnknown + 2) // read, never edit replay
        check(controller.mutate(checkNotNull(controller.snapshot), "cancel")); idle()
        check(controller.snapshot?.cancelled == true)
        check(controller.mutate(checkNotNull(controller.snapshot), "resume")); idle()
        check(controller.snapshot?.cancelled == false && controller.snapshot?.id == opened.id)
        val consistent = controller.snapshot
        tamperNext = true; controller.readOriginal(); idle()
        check(controller.needsRead && controller.snapshot == consistent)
        controller.readOriginal(); idle(); check(!controller.needsRead && controller.snapshot == consistent)
        holdNext = true
        val beforeClose = controller.snapshot
        check(controller.mutate(checkNotNull(beforeClose), "edit_name", "迟到结果"))
        synchronized(monitor) {
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
            while (held == null && System.nanoTime() < deadline) monitor.wait(20)
        }
        val beforeDuplicate = calls
        check(!controller.mutate(checkNotNull(beforeClose), "edit_name", "重复点击")); check(calls == beforeDuplicate)
        controller.close(); checkNotNull(held).invoke()
        check(controller.snapshot == beforeClose && !controller.busy)
        val retained = checkNotNull(beforeClose)
        val resumed = HostSetupController(scope, route, {}, retained)
        val beforeReentry = calls
        resumed.open(); check(calls == beforeReentry) // unknown/re-entry never auto-opens another identity
        resumed.readOriginal()
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
        while (resumed.busy && System.nanoTime() < deadline) Thread.yield()
        check(!resumed.busy && !resumed.needsRead && resumed.snapshot?.id == retained.id)
        resumed.close()
        runtime.releaseSession("session")
        waitCall { runtime.updateScope("session", "p", it) }
        val expired = HostSetupController(scope, route, {}, retained)
        expired.readOriginal()
        val expiredDeadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
        while (expired.busy && System.nanoTime() < expiredDeadline) Thread.yield()
        check(!expired.busy && expired.needsRead && expired.snapshot == retained)
        val callsBeforeBlockedOpen = calls
        expired.open(); check(calls == callsBeforeBlockedOpen)
        expired.close()
        println("PASS real host/controller: one reducer, exact CAS, stale/double action rejection, template token/manual buffer, lost outcome original read, cancel/resume, same-CAS immutability, closed-view callback isolation, re-entry original-ID read and expired-session retention; no native/transport")
    } finally { runtime.close(); check(runtime.awaitDrain(5000)) }
}
