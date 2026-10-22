package com.mightyoung.muyon.androidlab.agentipc

/** Reference-model calculation only; deliberately does not implement FullPayloadProofVerifier.
 *
 * Fixed official 1017 encoder subset: no tools/task/reasoning/images/response_format.
 * ByteLevel BPE with 256 byte symbols and no expanding normalizer implies that
 * tokens <= UTF-8 length of the FULL rendered prompt, including all role markers.
 * This is not serialized-JSON byte accounting or an exact tokenizer. Hosted API
 * framing/billing parity remains unproven; this result must not enable live sends.
 * See docs/tasks/ordinary-chat-live-20261019/PRICING-AND-TOKEN-PROOF.md.
 */
internal object OrdinaryChatReferenceTokenBound {
    const val MODEL = "deepseek-flash"
    const val MODEL_REVISION = "1bae0e1088993b9b82de08f59de5be5a34e42170"
    const val ENCODER_SHA256 = "13231c592e958fb39e2af6001dae69d90e7a36b265702b9b390236fb387599e2"
    const val TOKENIZER_SHA256 = "c90dfa01249db1be4245780a052ede752e1361c612ac6d08e2bdada7d599476b"
    const val MAX_REFERENCE_INPUT = 16384
    private const val BOS = "<｜begin▁of▁sentence｜>"
    private const val EOS = "<｜end▁of▁sentence｜>"
    private const val ASSISTANT = "<｜Assistant｜></think>"

    data class Message(val role: String, val content: String)
    data class Bound(val renderedPrompt: String, val publishedModelInputTokenUpperBound: Long) {
        val isHostedBillingProof: Boolean get() = false
    }

    /** Accept a strict subset instead of silently changing/merging unsupported history. */
    fun render(model: String, messages: List<Message>, thinkingDisabled: Boolean): Bound {
        require(model == MODEL && thinkingDisabled && messages.size in 1..18)
        val frozen = messages.toList()
        val start = if (frozen.first().role == "system") 1 else 0
        require(frozen.size > start && (frozen.size - start) % 2 == 1)
        val prompt = StringBuilder(BOS)
        frozen.forEachIndexed { index, message ->
            require(message.content.length <= MAX_REFERENCE_INPUT && scalarText(message.content))
            require(!message.content.contains("<｜deepseek_image｜>"))
            val role = if (index < start) "system" else if ((index - start) % 2 == 0) "user" else "assistant"
            require(message.role == role)
            when (role) {
                "system" -> prompt.append("<｜System｜>").append(message.content)
                "user" -> prompt.append("<｜User｜>").append(message.content).append(ASSISTANT)
                "assistant" -> prompt.append(message.content).append(EOS)
            }
        }
        val rendered = prompt.toString()
        val bound = rendered.toByteArray(Charsets.UTF_8).size
        require(bound in 1..MAX_REFERENCE_INPUT)
        return Bound(rendered, bound.toLong())
    }

    private fun scalarText(text: String): Boolean {
        var index = 0
        while (index < text.length) {
            val char = text[index++]
            if (Character.isHighSurrogate(char)) {
                if (index >= text.length || !Character.isLowSurrogate(text[index++])) return false
            } else if (Character.isLowSurrogate(char)) return false
        }
        return true
    }
}
