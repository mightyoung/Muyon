# Current project and pending suggestion revocation

`ProductChatRuntime.updateScope(session, project, callback)` serializes current project selection on the same control queue as native prepare/review/confirm. Each session has a monotonic local scope generation. An A → B → A selection never restores a previous generation. Ordinary request preparation requires that the host-selected project match the current scope; model arguments supply neither project nor generation.

A scope change first revokes that session's write tickets under the common send gate. It then cancels outstanding agent requests, discards only the unconfirmed P04 business plans through the trusted host port, and retires old tool origins, cached business previews and HTTP plans. Native calls happen outside the send gate. Completed business effects and prior budget accounting are not reset or undone. Original identities remain available for read-only lookup.

`ChatScreen` sends `chat_scope` when its project selection changes and waits for the scope reply before enabling request previews. It clears old disclosure/suggestion UI. The parent also updates the scope immediately from the research project's selection surface so leaving chat cannot preserve an old disclosure context.

Cancellation, provider configuration changes and session release also retire pending suggestion caches and discard their unconfirmed business plan. The coordinator checks the original tool request is still `tool_pending` and not cancelled before asking to confirm a suggestion. The native `validate_tool_suggestion_trusted` checks the original bound call, current scope/configuration/epoch, suggestion stage and exact prepared plan identity. The parent's shared ProductCore mutex combines that check with the existing P04 confirmation; a model cannot invoke it or supply a success receipt.

Fresh verification:

```text
Rust: owner 11 + local read/parser 6 + tools 7 = 24 passed; 0 failed; 0 ignored
Strict clippy: exit 0
Kotlin protocol/send gate/scope registry/settled-tool ownership: 24 passed; 0 failed; no network
Kotlin transport/runtime compile: exit 0
```

The added native regression verifies cancellation/configuration/generation changes reject suggestion validation before any business commit, preserving supplier revision 1. Offline latch tests cover scope revocation before/after actual write, and the registry test covers A → B → A generation non-reuse. These are local code checks. They do not claim a full API26 model-tool dialog run, a live provider response or paid-search acceptance.

The final cancel guard also checks the surviving tool-origin owner after network and HTTP-plan maps have retired. Another live client cannot cancel a settled pending tool or remove its business preview. The offline check exercises the shared production ownership guard with active/plan absent, verifies rejection preserves the preview, and verifies the original owner can cancel; active/plan owner conflicts remain rejected. `cancel-owner-green.log` records 24 passing offline checks and runtime compilation exit 0.
