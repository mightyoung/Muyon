# RD-P05A actual Rust laboratory core bridge

Writer: `/root/device_deferred_rust_domain`; branch `task/device-deferred-core-bridge-20261014`, worktree `/workspace/Muyon-device-deferred-core-bridge-20261014`. Shared contract/fixture base `b62980bbc91bbc78c0b765118d2221ffd536f45e`; writer owns only `experiments/redesign/device-deferred/core-port-lab/core/` and this task file. B owns root contract/fixtures/comparison and sole develop integration. No predecessor SPIKE/domain/recovery/product files changed.

Implemented actual stdio NDJSON executable `rd-p05-core`; installed binary path `/tmp/rd-p05-core-target/debug/rd-p05-core`, startup `--seed <trusted fixture>`. Exact Rust serde request/reply/business structures are the unique lab wire source. Cached pinned serde1.0.229/serde_json1.0.154/sha2 0.11.1 plus unchanged local RD-P01/RD-P02 path dependencies, own Cargo.lock, offline build. No installation or new license.

Actual private synthetic memory store/plan/intent/ledger: raw UTF-16 preview→RD-P01 candidate; commit revalidates domain/plan/current CAS; immutable exact original command replay returns original receipt without another write; altered payload conflicts; explicit new same-name intent increments once. Clone-before-effect stages row/reducer event/paired checkpoint/receipt and swaps once only after successful validation. Receipt is generated from actual result, never expected tables. Trusted precommit failure discards staged business state. Trusted once-lost commit reply returns unknown after effect; read-only lookup uses real internal ledger RD-P02 reconcile with zero new dispatch. RD-P02 reconnect/epoch fencing cannot erase a prior effect or regress current rows from an old receipt.

User-authorized design and B-owned protocol are used directly; no new product DTO/schema/authority is frozen. Pause on environment disconnect preserved four untracked files at 2646420; resumed with explicit B authority, FF shared3ca4a06 then b62980, never overwritten another writer.

## Fresh executed evidence

- TDD actual process RED: 16 tests, 12 assertion failures/4 passes, exit1 against compilable stub. Initial actual pipeline GREEN16 exit0.
- Explicit-null/UTF8 label/error metadata strengthening RED22 had 2 named assertion failures, then GREEN22.
- Large trusted seed + escaped metadata budget RED actual reply34182 bytes >32768. Budget guard implemented; separate commit effect→oversized unknown→receipt-only lookup RED failed before lookup axis correction.
- Final actual-process suite **24 passed/0 failed/0 skipped, exit0**. Tests cover name/UTF16 boundaries, NFC, exact domain, CAS, selected row only, sameintent/reuse, same-name newintent, lost response, precommit staged rollback, lookup no writes, old epoch effects/current projection, strict fields/null/versions/types/canonical counters, multibyte labels, malformed/oversized frames/EOF, revisions above2^53 and encoded reply budget.
- Four semantic inverse mutants build successfully offline/locked and each targeted real process assertion fails exit1: disabled duplicate replay; bypass original CAS; absent lookup dispatches commit; old receipt regresses current projection. All source bytes restored in finally; ready client binary not overwritten (mutant target distinct).
- Rust crate cargo test command runs successfully; its test count is 0, so actual pipeline evidence is explicitly the 24 Python process tests, not a claimed 24 Rust unit tests. Whole product candidate CI belongs to B, not run here.
- Raw logs `/workspace/reports/rd-p05a-core-20261014/`; no original logs, binary, cache or secret in Git. See core README for exact commands and verification-evidence.json for hashes/counts. Independent immutable review and exact candidate CI required before integration.

## Preserved gates

Effects/checkpoints are actual **synthetic memory** execution, not production database persistence or restart recovery; trusted startup and callers are lab controls, not authorization tokens/user provenance. Process restart creates a fresh seed state. No real receipt provider, models, user data, credentials, IPC security, production idempotency/recovery or real adapters were tested here. Pure normalization dependencies still differ Unicode8/17; corpus limits remain.

Android actual load, Compose and Electron runtime **NOT_RUN**. M03 **blocked_contract**. Device verification is deferred without removing release/device gates or claiming original M03 exits passed. Only B may integrate; writer does not merge develop/main, forcepush, delete or deploy.
