# Official pricing and token-proof boundary

Checked by an independent researcher on 2026-10-19. No credential, balance API or model request was used.

Official current ID is `deepseek-flash`, serving DeepSeek-V4.1-Flash-1017. Peak CNY price per million tokens is cache-hit input 0.04, cache-miss input 2, output 8. Peak USD price is 0.006 / 0.30 / 1.20 respectively. Use peak/cache-miss only for reservation. `thinking` defaults enabled and must explicitly be disabled; `max_tokens=128` is within the documented 1–393216 range. Sources: [CNY pricing](https://api-docs.deepseek.com/zh-cn/quick_start/pricing/), [USD pricing](https://api-docs.deepseek.com/quick_start/pricing/), [chat API](https://api-docs.deepseek.com/api/create-chat-completion/).

The actual account billing currency is not known. Only local secure handover or the user's non-secret currency confirmation can establish it. No USD conversion authority is assumed. The [balance API](https://api-docs.deepseek.com/api/get-user-balance/) documents `balance_infos[].currency`; it was not called.

## Current official tokenizer reference

Official repository: `deepseek-ai/DeepSeek-V4.1-Flash-1017`, pinned revision `1bae0e1088993b9b82de08f59de5be5a34e42170`, MIT license. Researcher inspected these public files:

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| tokenizer.json | 6367257 | c90dfa01249db1be4245780a052ede752e1361c612ac6d08e2bdada7d599476b |
| tokenizer_config.json | 801 | 6ac8c8dc065ed118161d02dd532749ae3f52c243deac27872134fae2f50d8547 |
| encoding/encoding.py | 37962 | 13231c592e958fb39e2af6001dae69d90e7a36b265702b9b390236fb387599e2 |
| LICENSE | 1084 | f2c6c602815669d292889e5be8c802f2ed950653b77999b1584e8e6aed25d040 |

[Tokenizer](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash-1017/blob/1bae0e1088993b9b82de08f59de5be5a34e42170/tokenizer.json), [configuration](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash-1017/blob/1bae0e1088993b9b82de08f59de5be5a34e42170/tokenizer_config.json), [encoder](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash-1017/blob/1bae0e1088993b9b82de08f59de5be5a34e42170/encoding/encoding.py), [encoding reference](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash-1017/blob/1bae0e1088993b9b82de08f59de5be5a34e42170/encoding/README.md).

The reference tokenizer is ByteLevel BPE with all 256 byte symbols, no expanding normalizer and merge-only tokenization. For the complete reference-rendered prompt, including BOS, all role/history delimiters and the final assistant prefix, UTF-8 length B is a conservative mathematical upper bound on tokens for that published tokenizer. It is not an exact token count and is not the old synthetic serialized-JSON byte metric. Rendering must include the complete history and use `thinking_mode="chat"`; unsupported content/tools/fields must be refused.

For a separately verified full-prompt bound B<=16384 and 128 output tokens, peak/cache-miss worst-case cost is 2B+8*128 micro-CNY, at most 33792 micro-CNY (0.033792 CNY) per request and 0.067584 CNY for two. These are conditional calculations, not a bound already established for the hosted product path. The current official model has a 1048576-token context; reserving that whole maximum costs 2.097152 CNY for input alone, exceeding this run's authority.

The official model card calls its encoder a prompt-format reference, but no hosted API parity contract was found. Therefore the mathematical proof above is established for the published tokenizer/encoder, not automatically for hidden hosted framing or billing. There is currently no production `FullPayloadProofVerifier` installed in the new component. Missing verified model/template/full-payload evidence denies reservation. [Official token usage guidance](https://api-docs.deepseek.com/quick_start/token_usage/) treats returned usage as actual measurement; a post-response usage check cannot retroactively make an unproven pre-send bound safe.

Do not use the older tokenizer ZIP linked by the generic token page as the current 1017 template. Do not install or execute unreviewed upstream code to close this gap. A future production proof implementation needs independently reviewed full rendering and a documented hosted-model trust basis before enabling the live gate.
