# Current delivery — real wiring built; credential handover pending

Remote-operation update: the user explicitly authorized loading the original
project `.env` because manual emulator entry is unavailable. The reviewed temporary
local FIFO design and its separate implementation/verification gate are in
[REMOTE-CREDENTIAL-HANDOVER.md](REMOTE-CREDENTIAL-HANDOVER.md). It reuses the
original installer/owner and does not relax the two-request/CNY budget gates.
The manual-only handover instructions below describe the earlier checkpoint.

Updated 2026-10-20. Real DeepSeek requests: **0 / 2**. Provider fees: **no model
request sent, no provider usage or charge evidence yet**. The two-request real
acceptance is incomplete until secure local handover and actual ordinary Send.

## Source and workspace

- Core integrated source: `5bffcfa1e20c28d4562868fecb93c81658cc84e0`.
- Runtime/APKs under validation: `6aeeae789e0fb444947641be178cf73fa13ec365`.
  This adds rendered-state test synchronization, preserves the first device FAIL,
  and corrects one obsolete status label; it does not change budget/transport gates.
- Isolated branch `codex/muyon-chat-live-canary`, worktree
  `/private/tmp/muyon-chat-live-canary-20261019`.
- Accepted PR97 source `d1df23200df0ffaccac6edddd3b2115aaa6cfb42`, document base
  `3abc1cae405de4c941d540f1043cdf31463b3f95`.
- PR98 `ddb34971ee2e865fd29fb9f893b0aba49ed069b9`, PR99
  `9c0073719b001d504c4403ae7a8de6bcc617ca0e` retained by isolated merge
  `ff1dfe7855a2bab9b00d7275eaa801f312161c9a`.
- Original develop remains `0ab2c4f667681b9aacb017f8cd2eea6f576cf78e` with its
  original two xcconfig modifications and untracked files preserved.

## Implemented

Compose ordinary Send uses the original Binder Service, Rust Agent, owner callback
and DurableServiceHostOwner. Original history, authorization and receipt validation
remain. Generated bindings preserve `withHost`, `withRegisteredTools`, Rust
`with_registered_tools` and `RegisteredToolSettings.snapshot()`. Owner failure
returns an error, with no synthetic fallback. Search implementations were retained.

The existing owner holds the trusted closed configuration, memory-only temporary
credential, fixed-batch cross-process budget and real fixed-host HTTPS transport.
The HTTPS adapter uses system certificate and hostname verification, one bounded
TLS POST, no reconnect/redirect/retry, and guarded cancellation/late-result handling.
Final success requires Rust validation and durable local owner settlement.

The user confirmed CNY. Official model/pricing and pinned reference tokenizer were
checked for `deepseek-flash` (1017). Peak per-million CNY prices are input miss 2,
hit 0.04, output 8. Full rendered history has a token upper bound <=16384; output
has a hard cap 128, thinking disabled. Maximum reservation is 33792 micro-CNY
per attempt, <=0.067584 CNY for two, inside the user's 1 CNY ceiling. This bound
comes from the complete pinned prompt/tokenizer proof, not arbitrary JSON bytes.
The fixed batch cannot reset with epoch/process/credential changes. Unknown,
timeout, cancellation or failure stops the batch and retains the reservation.

## Verification

| Check | Result and scope |
| --- | --- |
| Budget JVM groups | PASS 11, including full-history charge, insufficient budget, concurrency, crash/reopen and unknown stop |
| Official reference renderer | PASS 4 fixtures/history/Unicode/rejection checks |
| HTTPS socket-free checks | PASS 27, including wire bounds, cancellation, deadline, malformed response and no retry |
| Existing Rust ordinary chat | PASS 15/15 |
| New Rust live controller | PASS 5/5, with live failure/restore/source flag cases |
| Rust stop causes / bridge / lifecycle probe | PASS 3 / 9 / 1 |
| Genuine generated bindings / PR99 retained APIs | PASS byte comparison and symbol checks |
| API26 native arm64-v8a + x86_64, ELF/JNA/imports | PASS local build; actual Rust 1.93.1, NDK 28.2 |
| Exact-input APK build and lint | PASS; lint 0 errors, 14 warnings |
| First API36 six-case device run | FAIL 1/6, preserved; underlying terminal preceded displayed UI, third Send asserted too early |
| Corrected exact-source API36 six-case run | PASS 6/6, 46.01s; full two-turn same-owner history/receipts and third budget refusal with exactly two attempts |
| CI producer / Rust 1.99 CI / API26 device runtime | NOT RUN |
| PR99 API26 Settings→Send | User-reported failure remains unresolved; not a passing baseline |
| I04 / containing suites | NOT RUN, prohibited |
| Real DeepSeek HTTPS / usage / provider charge | NOT RUN, secure credential handover pending |

Details, initial failure, APK hashes and exact class selection:
[DEVICE-20261020.md](DEVICE-20261020.md). No fixture result is provider acceptance.
The device fixture has no INTERNET permission and uses a separate package/data root.

Independent Rust/ABI reviewer approved the final production scope. Final independent
architecture review is **APPROVE / CLEAR** after checking the source, native report,
three APK hashes and complete six-case device evidence. It permits secure credential
handover followed by the already authorized maximum two real ordinary Send actions;
it does not establish provider acceptance. Prior rejection/WATCH records remain
preserved. No merge, force push, deployment, branch deletion or PR86/HOLD change.

## Reusable entry and remaining handover

Build helper:
`experiments/redesign/android-rust-bridge-lab/checks/build_live_chat_local.py`.
It requires a clean exact source SHA, locally installed toolchain and verified cached
JNA AAR; it records actual tools and labels output LOCAL_LINK_VERIFIED, not CI.
Verified inputs for this APK:
`/private/tmp/muyon-live-local-6aeeae78/bridge-inputs`.
Use the Gradle source/input properties and target list recorded in DEVICE evidence.

Real APK:
`experiments/redesign/android-compose-lab/app/build/outputs/apk/liveChat/app-liveChat.apk`.
Package `com.mightyoung.muyon.androidlab.liveChat`, launch MainActivity. It opens a
non-exported secure credential Activity in the existing `:agent` process. The user
must manually enter the key locally and press “仅在本进程启用 CNY 小额聊天”.
Never send the key in chat, shell arguments, files or logs. The input is cleared and
temporary copies erased; the key lives only in the agent process. No screenshot or
UI-tree capture may run during this handover. Reopening after agent death requires
another local handover; the budget persists and must never be reset.

This exact liveChat APK has now been installed for the first time. Launch succeeded;
Activity-manager metadata confirmed CredentialActivity resumed in `:agent`. The
local handover question is pending. UI inspection is paused; no key was read or
sent to the model. No liveChat data reset or credential injection was performed.

After handover, perform only these ordinary UI messages, with the second contingent
on successful accepted first response:

1. `For this synthetic test, the code is CANARY-4827. Answer with that code only.`
2. `Repeat the code from my first message. Answer with the code only.`

Record exact outbound history, actual answer/model/id/usage, owner receipt and batch
state. Report usage-derived peak all-miss CNY cost as a **calculated upper bound**;
an invoice or actual discounted account charge needs separate provider evidence.
Any timeout/unknown/failure stops acceptance without resend or reservation release.
Do not clear/uninstall the liveChat package or budget, change batch identity, retry,
top up or upgrade. No independent curl or legacy Dart/script run can replace this.
