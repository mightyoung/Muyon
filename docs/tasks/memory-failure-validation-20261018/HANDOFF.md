# Memory failure validation — handoff and stop

Draft PR: https://github.com/mightyoung/Muyon/pull/87

Branch: `research/memory-failure-validation-20261018`; base/PR target: B06 `6635bc6be057fd36c0e0c6c0aafaf034aca2ecaa` / `docs/leaderb-next-20261018`. Reviewed executable source: `0090b6e394abcbd8556a0911f4d5be1ff18687f5`; final follow-up changes contain documentation/evidence only. The base is a historical handoff, not current production completion. Sole integration owner remains thread `01a14da8-37ed-76fa-9fb2-7c14c0dae0d5`.

## Delivered and verified

- 21 Python stdlib tests PASS (0 failures/errors/skips), independently rerun at fixed source SHA. Exact command, versions, traces and results: `results.json`, `python-tests.txt`, `REVIEW.md`.
- Actual SQLite insert failure after retirement, SQL-committed/vector-failed state, independent observer, process exits before/after commit, restart recovery, late repair after deletion, durable unknown refusal, empty/whitespace/missing versus explicit `[]`, and three sensitive negative controls.
- 8 offline Dart tests call actual gateway/provider through a synthetic loopback server, inspect actual print/persistent ledger/files, and include two ordinary semantic-ledger contract assertions. These are delivered fixtures, NOT_RUN/UNCOMPILED, not passing evidence.
- Existing 24 Rust IDs and seven matching blobs at both supplied Hy SHAs inventoried. No duplicate current-member/revision/body-hash repair. Research report officially materialized and verified; identity/hash in COVERAGE.md.
- Only the two authorized new directories changed. No production fix, UI/host/AIDL/Gradle/core adapter/Hy crate modification, model weights, real model, paid API, credential or private data used.

## Blockers and boundaries

| Action / target | Status / reason | What is complete |
| --- | --- | --- |
| Compile/run actual gateway canary Dart fixture | NOT_RUN: this environment has no Dart/Flutter SDK or resolved app package config | fixture and actual source/API static review; owner command in ADAPTER-LOG-AUDIT.md |
| Rerun existing 24 Hy Rust tests | NOT_RUN: Cargo unavailable; crate absent from B06 checkout | immutable two-candidate blob/ID comparison only |
| Generation/embedding success/failure × INFO/DEBUG × stdout/file/export canary | 16 matrix cells NOT_RUN; 8 export cells NOT_IMPLEMENTED; explicit adapter logger/level implementations not found | actual path inventory and unrun fixture; **no production zero-leak conclusion** |
| Confirm semantic-ledger outcome and arbitrary error-body handling | static reachability/suggestion only; no dynamic FAIL observed | minimal inputs and narrow owner patch advice supplied; no production edits |
| Device or frontend/backend acceptance | NOT_RUN: outside this isolated task | integration ownership preserved |
| I04 old script-state→HTTP operation | prior DENIED_BEFORE_EXECUTION/BLOCKED remains absolute | no execution/retry/rewrite/split/reroute; this task contains no implementation of that operation |

The synthetic replacement design uses a durable correction-intent barrier plus one SQL replacement commit and a rebuildable derived index. It proves only the experiment's matrix. It is not a Muyon memory writer implementation or proof of all authority/revision/concurrency properties. Intent-persistence failures, arbitrary power loss and full cross-store production recovery remain outside its tested boundary. It does not authorize unknown auto-resend.

Production follow-up is limited to owner review of `ADAPTER-LOG-AUDIT.md`: decide whether succeeded means transport or semantic operation success, then run the two minimal blank-chat/empty-embedding assertions; separately run arbitrary error-body and process-log canaries. Do not broaden this PR into production refactoring. No merge into main/develop, force push, branch deletion or deployment was performed. Stop writing after the final documentation/evidence push; no active local builders/watchers remain from this task.
