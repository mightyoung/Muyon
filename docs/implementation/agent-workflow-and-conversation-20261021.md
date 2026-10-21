# Agent workflows and conversation presentation

Implement the user's ChatGPT/Codex collaboration reference and Claude conversation reference within the existing Muse product shell. Reuse the existing Rust owner, scoped business tools, request budget, cancellation and actual-field disclosure. Public references describe patterns; private ChatGPT/Claude servers are not available for reuse.

## Execution contract

- A separate Rust-owned SQLite run ledger holds root/child identity, skill digest, task, scope and ordered public activity events. Depth1, at most2 active and8 total children per root. Creation is not completion. No full parent history is silently inherited.
- Bundled `SKILL.md` supplies name/description first and full instructions only when selected. Enabled skills cannot grant tools or data authority. Two local read workflows use the existing `ReadScope` and business service. Local tool tasks and remote AI tasks are labeled separately.
- Remote children use distinct conversations and the same existing owner/configuration/aggregate budget/prepare/confirm gates. An unresolved original root request prevents deriving around recovery. No price proof, credentials or user approval is manufactured. No I04 or live provider retry is authorized by this work.
- Root cancellation propagates to descendants and actual remote request IDs. An attempted unknown remote request keeps its identity and budget hold. Restart recovers uncertain work without replay. Reconnected sessions can read history, not take over old mutable authority.
- Service APIs obtain the project from the successfully selected session scope. Model/action JSON cannot supply workspace, epoch or grants, bind request IDs or manufacture completion.

## Presentation contract

The normal conversation stays quiet. A compact expandable execution group shows real child states, skill loading and tool results; configuration and skill controls stay in management. Actual waiting/failed/unknown states remain visible. Public provider reasoning summaries may be rendered only if supplied; the current provider disables thinking, so this implementation displays host execution activity rather than invented reasoning.

Use platform sans/serif fonts with Claude-inspired readable16/24 body text, bounded line width, selectable paragraphs, headings/lists/quotes/code/tables and safe links. Extracted vendor fonts were removed during review remediation because redistribution permission was not established. Code copy and table scrolling operate on real rendered content. Preserve exact original-request provenance and business confirmation/disclosure UI.

## Acceptance

The scoped build/device verification and exact APK identities are recorded in [agent-workflow-proof-20261021](agent-workflow-proof-20261021/README.md). Local record results use a readable summary with a separate raw-record disclosure; task selection remains compact.

Rust tests prove actual local reads, scope isolation, progressive skill loading/toggle, bounds, cancellation, late results, restart and remote blocked-plan identity. Android tests prove real Service→Rust creation/execute/query/reopen, management/timeline interactions and readable rich text. Build, lint, bridge regeneration, two-ABI package checks and existing device regression remain separate gates. Real provider multi-agent inference stays unverified while the existing pricing proof gate is unavailable.

## Public references and reuse

The implementation directly reuses this product's `BusinessStore`, `ReadScope`, `AgentOwner`, actual-field tool review and wire encoder. It introduces no SDK/runtime dependency. Public implementations informed lifecycle and event boundaries; private app/server source was not available.

- [OpenAI subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents), [multi-agent API](https://developers.openai.com/api/docs/guides/agents-api/multi-agent): parent/child lifecycle, distinct tasks and bounded delegation.
- [Agent Skills specification](https://agentskills.io/specification), [OpenAI skill loading](https://learn.chatgpt.com/docs/build-skills): metadata before full `SKILL.md`; instructions are not an authority grant.
- [Codex spawn guard](https://github.com/openai/codex/blob/b48277327d427b92ace30c1ee9d4817f8fa836b7/codex-rs/core/src/agent/control/spawn_guard.rs), [stable activity groups](https://github.com/openai/codex/blob/b48277327d427b92ace30c1ee9d4817f8fa836b7/codex-rs/tui/src/history_cell/activity_group.rs): fixed2026-10-21 source reference, Apache2.
- [Agents SDK event types](https://github.com/openai/openai-agents-python/blob/64cd5dfc5a1579870dcbed0ea42b27aa84033fee/src/agents/stream_events.py): fixed2026-10-19 source reference, MIT; separate tool, result and agent events.
- [Claude thinking summaries](https://platform.claude.com/docs/en/build-with-claude/thinking), [paired tool calls](https://platform.claude.com/docs/en/agents-and-tools/tool-use/handle-tool-calls), [OpenAI reasoning summaries](https://developers.openai.com/api/docs/guides/reasoning#reasoning-summaries): public summaries differ from hidden chain of thought. No hidden reasoning is exposed or fabricated.

The existing provider remains `stream:false` and `thinking:disabled`; its private `reasoning_content` is rejected. Current presentation displays observed request/transport/tool facts and local workflow events. It does not implement an alternative reasoning provider. Markdown supports a bounded practical subset rather than claiming complete CommonMark/HTML support; only valid HTTP(S) links are actionable.

Remote child requests advertise only the selected skill's fixed tool subset. Settlement rejects a response calling another tool, retaining its unknown budget hold; approved tool followups preserve the same subset. A durable owner-created followup chain remains attached to the original child. Snapshot observes its leaf, cancellation expands the actual chain even before a snapshot, and both normal-chat and child preparation inspect every root's chain in the trusted conversation/project scope. Zero-reservation prepared observations report their actual missing-price-proof reason as blocked. Duplicate observations do not manufacture events. Large result previews are explicitly truncated while complete local results stay in the run ledger; snapshot/list responses are limited to512KiB.

The management flow currently dispatches explicitly created tasks. Local skills perform real business reads; AI children enter the existing model request preparation and confirmation path. This does not claim automatic model-selected delegation, parallel paid-provider inference or parent synthesis is accepted while the pricing gate remains blocked. Group membership and profile descriptions alone still do not authorize automatic execution or outbound disclosure.
