# Delivery status: incomplete real bridge, zero live calls

Historical result from the preparation commit `f826d045955bed5461598549f67d00e6bee7f1e2`.
Superseded by [CURRENT.md](CURRENT.md). The statements below about absent HTTPS,
missing credential entry and unconfirmed CNY describe that earlier snapshot only.

The requested Muyon → real DeepSeek two-turn acceptance has **not** been completed. This branch contains reviewed offline prerequisites only. There is no installed production HTTPS adapter or secure Service-process credential entry, and no claim of successful real conversation, usage or billed cost.

## Workspace and source

Original develop remains at `0ab2c4f667681b9aacb017f8cd2eea6f576cf78e`; both macOS xcconfig modifications and all original untracked data were preserved. Normal elevated `git worktree add` succeeded, without clone/copy/overwrite workaround. Worktree: `/private/tmp/muyon-chat-live-canary-20261019`, branch `codex/muyon-chat-live-canary`, base `3abc1cae405de4c941d540f1043cdf31463b3f95`. The accepted executable source `d1df23200df0ffaccac6edddd3b2115aaa6cfb42` and that base are both local commit objects; their experiments/.github trees compare equal. HANDOFF.md was read through the base commit because old develop does not contain it.

## Actual changes

* `OrdinaryChatCanaryBudget.kt`: independent fixed-batch 1,000,000 micro-CNY/two-attempt ledger, trusted full-payload proof seam, peak/cache-miss integer pricing, durable pre-handoff reservation, interprocess lock and persistent failure-stop marker. Missing currency/proof refuses. Unknown/cancel/crash/late result never refunds or re-enables the batch. It is not wired into DurableServiceHostOwner.
* `OrdinaryChatReferenceTokenBound.kt`: strict pure-text subset of the pinned official 1017 prompt renderer, including full history and role framing. Its token upper bound is for the published reference tokenizer. `isHostedBillingProof` always remains false; this is deliberately not a production proof verifier.
* Two dedicated Kotlin test files and an offline JVM runner under `android-compose-lab/checks/`.
* DESIGN.md, PRICING-AND-TOKEN-PROOF.md, REVIEW.md and this result record.

No existing Rust/Android runtime, public ABI, search source, manifest, Gradle pins or lockfile was changed. The budget accepts only a trusted verifier; none is installed. Stub verifiers and simulated reported fees occur only in isolated offline tests and are not provider evidence.

## Verification ledger

| Check | Result / limit |
| --- | --- |
| New offline JVM runner | PASS, exit 0: 11 budget groups + four official reference fixtures/history/Unicode/rejection checks; leader and independent reviewer |
| Concurrency/crash/fault cases | PASS: two concurrent JVMs only one reservation; forcible pending-process kill; pre-rename, post-rename and directory-force failure all stop across reopen |
| Existing exact ordinary_chat_controller | PASS, 15/15, 0 ignored, exit 0; no I04 or aggregate target |
| Cargo lib check | PASS after normal approved retrieval of missing locked dependency; no lockfile change |
| Shell syntax | PASS, `sh -n` |
| Independent component review | Initial REJECT repaired; final OKAY limited to offline components, details REVIEW.md |
| Complete live integration design | NOT APPROVED; current code remains synthetic-only |
| Android compile/lint | FAILED before source tasks: pinned Gradle 8.13 with available JBR 25.0.3 reports unsupported `25.0.3`; source compile/lint did not run |
| Android device / product run | NOT RUN: normally authorized adb starts, `adb devices -l` returns no devices |
| Real HTTPS/two-turn/usage/fees | NOT RUN, zero requests |
| I04 and all containing suites | PROHIBITED / NOT RUN |

Retained setup failures: initial offline Cargo resolution lacked locked cc 1.8.0; normal network attempt inside sandbox could not reach local proxy; approved normal Cargo dependency retrieval then lib check succeeded. First test link lacked sqlite3 symbols; proper macOS `RUSTFLAGS='-l sqlite3'` resolved them. First linked test run failed 15/15 at existing symlink_directory setup guard; using canonical `TMPDIR=/private/tmp` then passed 15/15 with no test/source weakening. An initially assumed ./gradlew path did not exist; repository documents an external Gradle 8.13 executable, whose actual attempt hit the JBR version failure above.

Final ordinary Rust command:

```sh
TMPDIR=/private/tmp RUSTFLAGS='-l sqlite3' CARGO_TARGET_DIR=/tmp/muyon-chat-live-canary-target cargo test --offline --locked --manifest-path experiments/redesign/rust-agent-host-lab/core/Cargo.toml --test ordinary_chat_controller -- --test-threads=1
```

Reusable new offline entry, from the isolated worktree:

```sh
sh experiments/redesign/android-compose-lab/checks/run_ordinary_chat_canary_budget.sh
```

Runner uses cached Kotlin 2.2.21 and Android Studio JBR, JVM target 17; it does not prove the repository-pinned Kotlin 2.2.20 Android build. It performs no network request or installation. Its temporary ledgers, permits, model text and reported fees are synthetic fixtures.

## Paid-call accounting and blockers

Actual model requests made by this task: **0 of maximum 2**. Actual provider usage/fee responses: **none**. Production reservations: **none** (component is uninstalled); offline fixture amounts are not CNY charges. No balance/invoice was read, so no account-balance or unrelated-account-charge claim is made. No key/.env was read or recorded. There is currently no reviewed safe local credential handover entry; do not enter a key into chat, shell or persistent settings.

Official ID/peak prices are freshly verified and recorded with links/hashes in PRICING-AND-TOKEN-PROOF.md. Account currency remains unconfirmed. Full-reference token math is established, but a hosted full-payload billing proof is not installed or approved. Whole-context reservation alone would exceed 1 CNY. Missing proof cannot be replaced by old synthetic byte counts or a post-response usage check.

WebSearch shared-file coordination remains pending. An asynchronous question lists DurableServiceHostOwner.kt and possible ServiceHostBindings.kt/service_host_bridge.rs changes; the App thread listing twice returned unavailable, so no search-task identity or message delivery is claimed. The shared runtime files were not edited. Completion requires that coordination, a reviewed live evidence/handoff/credential design and implementation, a compatible JDK/Android build and actual device path, CNY confirmation, and safe user credential handover. Only then can the two ordered real ordinary-chat requests occur.

No PR created or pushed. No merge to main/develop, force push, deployment, branch deletion, forbidden I04 execution, or old 403 log/artifact retrieval occurred. PR86 and dependency combination HOLD were not changed.
