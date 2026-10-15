# Core Agent synthetic lab boundary

Experimental typed Rust Agent, not M03 or production wire. One fixed synthetic tool `fixture.record` stores an opaque UTF8 value; no supplier/domain semantics, HTTP or model account. Trusted registration declares write/risk; user/model payload never grants authority.

## Process interface v0

Binary name `muyon-core-agent-lab`. CLI commands `start`, `run`, `cancel`, `lookup`, `inspect`; options `--dir PATH` and task binding fixed at start. `start` consumes host-owned mode/budgets/input and a provider script file. Subsequent commands reuse durable original binding. Kernel writer documents exact flag names/output format before process checker implementation; the following input grammar is fixed to avoid a new JSON library.

Provider script is UTF8 text with one tab-delimited complete event per line: `tool<TAB>call-ref<TAB>fixture.record<TAB>hex-utf8-value`, `answer<TAB>hex-utf8-text`, or `fail<TAB>fixed-reason`. A script is input events, not expected/caseID outcomes. No approval/scope/risk/fault fields in model input. Names/call refs are bounded ASCII identifiers; hex is strict even-length bytes and decoded UTF8 must be valid. Empty values/text may be represented by empty final field; tabs/newlines in text use hex. No partial/streaming/HTTP protocol claim. Script and context maximums are enforced before allocation/work as practical.

Host-only fixture flags configure mode, hard prerequisites/scope/revocation, registered risk, explicit trusted confirmation, tool definite failure or response loss, and checkpoint pause/fault injection. These do not come from provider arguments. Test checkpoints are flushed notifications that let a checker kill the actual Rust process at durable boundaries. New kernels must not accept this fixture protocol from a product renderer.

Structured CLI output is a stable key/value or JSON observation of actual task status, counters, original binding, tool outcome/receipt and answer; the writer and checker agree exact names before tests. `inspect`/`lookup` are read-only for the effect store (task projection may durably reconcile a verified original receipt); missing/corrupt original evidence preserves unknown. No debug branch returns hard-coded expected results.

## Durable identity/effects

Host creates stable task/attempt/model-turn/invocation identity; provider call-ref is correlation and duplicate/conflicting calls are checked, never authority. Keep exact binding in the journal before dispatch. Same effect-store atomic record includes actual value/effect count and original receipt; no success based only on provider answer or task status. Retain original receipt separately from later task text. Task journal and tool effect store are separate authorities; restart cannot use an absent task receipt as proof of no effect.

Persist cancellation/budget/context/provider position so a normal subsequent `run` does not repeat completed calls and an unknown run cannot dispatch. Explicit `lookup` may reconcile the original receipt, then a later explicit `run` may request the next scripted response; it must never replay an unresolved invocation. Cancellation after commit keeps receipt and prevents further provider turns.

Private one-owner directory, std atomic replacement/fsync under Linux assumptions; strict versioned bounded parser/checks; directory lock. No production schema, crypto authentication, SQLite migration, power-loss/remote exactly-once, Android/Electron or real model claim.

## Ownership and scope

Root owns this contract and parent plan. Core writer owns core/ and C1 taskdoc. Independent fixture/CI writer owns checks/, fixtures/, new .github/workflows/core-agent-lab.yml and C2 taskdoc. Existing labs/product/CI files unchanged. C0 non-author review and exact candidate/postmerge tests required before integration. FullAllow/Auto are settled; no risk confirmation is added to FullAllow or used to bypass hard gates.
