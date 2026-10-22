# RD-P08A trusted host adapter

Scope: new `operable-supplier-flow/host/**` plus this report, based on `25bfb3180111b156b8ba567fd14c7cca101d3e13`. The unchanged accepted P07 CLI is the sole supplier business implementation. No old lab/product/schema/CI changes, installations, external calls, credentials or real suppliers.

## Delivered

- `host/flow.mjs`: pinned executable, fixed synthetic DB/IDs, real P07 init/read/preview/commit/lookup; exact UTF16 code units; durable per-tab draft/intent and full binding before dispatch; global serialization and Linux flock; fail-closed journal validation; unknown recovery by original lookup only.
- `host/server.mjs`: loopback-only HTTP, exact Host/Origin, per-start CSRF nonce, narrow session/action envelopes, duplicate-key rejection, UTF8/body limits and fixed static assets. No public fault/process/path/SQL options.
- `host/PROJECTION.md`: exact shared browser/Android projection, session header/recovery metadata, action and storage/concurrency semantics. Preview references explicitly host correlations; M03 blocked_contract.
- Eleven tests and `host/run-tests.sh`, including actual subprocess SIGKILL after successful commit and request-traced restart. Test-only `process-worker.mjs` barriers are not runtime API capabilities.

## Verification

Command: `experiments/redesign/device-deferred/operable-supplier-flow/host/run-tests.sh` — exit 0, **11 tests, 11 pass, 0 fail**. Direct SQLite observations verify correct S1/S2 targeting, preserved untouched supplier, history/receipt counts, and no duplicate effect. After actual host SIGKILL, S1 revision `2`, history `1`, receipts `1`; restarted host sends original full-binding lookup and **zero commits**. Old nonce returns 403. Independent HTTP sessions cause actual stale CAS with input/expected revision retained. Tests cover lone surrogate/control/overlong/empty raw, normalization via P07, preview-only, draft invalidation, double submit, unknown guards, missing/unavailable lookup, altered binding, malformed response, historical/current distinction, corrupt/missing journal, competing host, disk-write failure, Host/Origin/nonce/body/path/envelope negatives.

TDD evidence is external: initial behavioral seam RED (`task-1-red.log`) preserved; real-P07-init behavioral RED (`task-1-red-real-core.log`) reports `undefined !== saved` and `undefined !== conflict`, then both GREEN. HTTP RED reports 404 vs 200 before its handler implementation. Supplemental edge tests were added against the working adapter; a new missing-receipt test produced a real RED (`task-1-receipt-clear-red.log`) and drove clearing stale receipt projection. No claim that every supplemental test individually had a failing first run. One negative test required raw `node:http` because Node fetch discards caller Host overrides; server restriction was retained.

Raw logs: `/tmp/rd-p08-workflow-20261014/task-1-*.log`; final `task-1-final-green.log`. All synthetic directories and first failures retained outside Git. Binary SHA256 verified `62232d1bdec9f923058dd9446b644781737caef9e111dc4dbb5658afe54c674c`. No P06/P07 whole regression suites were rerun.

## Limits and integration gate

Private Linux synthetic host only. Local owner, pinned binary, advisory flock and ordinary local filesystem assumptions are documented. Journal writes use file fsync/rename/directory fsync; no disk power-loss or malicious local-file mutation guarantee. No formal grants/modes/authentication, product retention/schema/migration decision, or implicit new intent after unknown. Single host required; session cap 32, no auto eviction. Missing/corrupt paired storage refuses startup instead of reseeding. Startup revalidates dispatched saved receipts through P07 lookup.

Non-author review and actual combined browser QA remain root integration gates. Desktop/mobile browser, Electron, Android/Compose/native accessibility/device and real model execution were not performed by this host writer. Existing CI does not execute these new Node/browser/JVM experiments. No push/merge performed.
