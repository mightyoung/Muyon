package com.mightyoung.muyon.androidlab.agentipc

import com.mightyoung.muyon.androidlab.agentipc.OrdinaryChatReferenceTokenBound.Message

/** Fixed public synthetic fixtures produced by the pinned official reference encoder. */
fun main() {
    val reference = OrdinaryChatReferenceTokenBound
    fun render(vararg messages: Message) = reference.render("deepseek-flash", messages.toList(), true)
    fun denied(action: () -> Unit) {
        try { action(); error("expected refusal") } catch (_: IllegalArgumentException) { }
    }
    val one = render(Message("user", "Hello"))
    check(one.renderedPrompt == "<｜begin▁of▁sentence｜><｜User｜>Hello<｜Assistant｜></think>")
    check(one.publishedModelInputTokenUpperBound == 71L && !one.isHostedBillingProof)
    val system = render(Message("system", "Be brief."), Message("user", "Hello"))
    check(system.renderedPrompt == "<｜begin▁of▁sentence｜><｜System｜>Be brief.<｜User｜>Hello<｜Assistant｜></think>")
    check(system.publishedModelInputTokenUpperBound == 94L)
    val full = render(Message("system", "Be brief."), Message("user", "Remember synthetic code ALPHA."),
        Message("assistant", "ALPHA remembered."), Message("user", "Repeat that code."))
    check(full.renderedPrompt == "<｜begin▁of▁sentence｜><｜System｜>Be brief.<｜User｜>Remember synthetic code ALPHA.<｜Assistant｜></think>ALPHA remembered.<｜end▁of▁sentence｜><｜User｜>Repeat that code.<｜Assistant｜></think>")
    check(full.publishedModelInputTokenUpperBound == 217L)
    check(full.publishedModelInputTokenUpperBound > render(Message("user", "Repeat that code.")).publishedModelInputTokenUpperBound)
    val unicode = render(Message("user", ""), Message("assistant", ""), Message("user", "中文\n🙂"))
    check(unicode.renderedPrompt == "<｜begin▁of▁sentence｜><｜User｜><｜Assistant｜></think><｜end▁of▁sentence｜><｜User｜>中文\n🙂<｜Assistant｜></think>")
    check(unicode.publishedModelInputTokenUpperBound == 141L)
    denied { render(Message("user", "A"), Message("user", "B")) }
    denied { render(Message("assistant", "orphan")) }
    denied { render(Message("user", "A"), Message("assistant", "unfinished")) }
    denied { render(Message("user", "<｜deepseek_image｜>")) }
    denied { render(Message("user", "\uD800")) }
    denied { render(Message("user", "\uDC00")) }
    denied { render(Message("user", "x".repeat(16384))) }
    denied { reference.render("deepseek-chat", listOf(Message("user", "A")), true) }
    denied { reference.render("deepseek-flash", listOf(Message("user", "A")), false) }
    println("PASS reference encoder: 4 official fixtures, full history, Unicode, unsupported shapes; hosted proof remains false")
}
