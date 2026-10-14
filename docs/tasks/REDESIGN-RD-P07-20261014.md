# RD-P07 Synthetic Atomic Business Transaction Implementation Plan

> For agentic workers: use superpowers:subagent-driven-development for one isolated implementation and a non-author task/whole-branch gate. User has explicitly authorized continued execution after the scope report; routine lab implementation does not request product approval again.

**Goal:** prove synthetic supplier writes, CAS, idempotency facts and receipts commit together in a real private SQLite database.
**Architecture:** new isolated Rust storage lab, unchanged RD-P01 domain normalization, installed SQLite C runtime with a minimal checked wrapper. Durable pending binding precedes the actual guarded business transaction; read-only recovery does not redispatch unknown work.
**Tech Stack:** cached Rust1.99.0 and existing pinned dependencies; installed SQLite runtime; Python stdlib sqlite3/subprocess/tempfile independent tests. No installation.
**Spec:** [lab contract](../../experiments/redesign/device-deferred/atomic-business-lab/CONTRACT.md).

## Global constraints

- Baseline `2b455723346fff725ddbd5e6a7a2c84dd049af4b`; P06 closed, do not repeat its verification.
- Only new `experiments/redesign/device-deferred/atomic-business-lab/` and P07/P07A documents. No preceding lab/product/schema/root dependency/CI changes.
- Synthetic Linux temporary database only; no real users/permissions/models/devices, new credentials/licenses/dependencies.
- Raw UTF-16 <=2000, XML before trim/NFC, nonempty <=200 codepoints: reuse unchanged RD-P01. Provisional local representations do not freeze M03.
- Exact intent binding, pending before effect, unknown no automatic replay, one guarded SQL transaction for applied row/history/idempotency/receipt.
- Raw evidence outside Git. Preserve every RED and source-restoration proof. Android/Compose/Electron NOT_RUN; M03 blocked_contract.
- Only B integrates after immutable non-author verification and exact candidate CI terminal success. No main/force/delete/deploy.

## Ownership and execution map

Worktree `/tmp/Muyon-rd-p07-atomic-business-20261014`, branch `task/device-deferred-atomic-business-20261014`. B owns CONTRACT and this task; one writer owns core and P07A document. Non-author can prepare independent SQL/fault review concurrently but reads/runs implementation only after fixed SHA. The running-agent registry was checked before assignment; no previous writer path is reused or overwritten.

This maps to experimental M07/M09/M10/M20 behavior, not completion of those product tasks. Formal M03, actual authority and production store/entrypoint dependencies remain blocked. Existing installed runtime discovery is setup evidence, not a test pass. Whole-product regression CI is separate from the local Rust/SQLite process suite; current CI does not execute the new lab.

## Fixed-source review checkpoint

Initial author `fe3d82080fb8a09c1d1effcbc9a93efc9b3b1289` failed non-author R1/R2 despite its passing suite: current physical domain was not checked on existing intent replay; pending/rejection triggers could commit unreceipted business or meta changes. The actual assertion failures and initial FAIL report remain external and are not relabeled as passing.

The same writer fixed these in `f3e16f089adb0ccac956bd06f3cfd664dfee906a`: original domain is checked after complete binding comparison; five-table snapshots are taken inside BEGIN IMMEDIATE and each phase checks its allowed delta before COMMIT. Only new lab core/P07A files changed; all 2301 baseline tracked blobs remain identical.

Non-author fixed-source SPEC COMPLIANCE and CODE QUALITY are C0/PASS; R1/R2 ADDRESSED. Actual evidence: 27 process methods, 2 Rust units, four unchanged original blocker assertions, nine independent properties plus three new phase properties GREEN. Five independently applied inverse classes compiled successfully and failed intended behavior assertions; source restored and complete process/property suites GREEN. CAS and duplicate mutants can be caught by final verification/PK constraints without a second committed effect; evidence distinguishes response regression from an unsafe committed write.

Source review `/tmp/rd-p07-independent-20261014/REVIEW-f3.md`; author/fix report `/tmp/rd-p07-workflow-20261014/task-1-report.md`; raw logs remain outside Git. Rust SQLite3.46.1 and independent Python SQLite3.53.1 are existing runtimes, not a claim of old native-asset CI root-cause repair. Cached rustfmt is unavailable; no component was installed.

Candidate branch `review/rd-p07-combination-20261014` preserves exact fixed core blobs and changes this coordination document only. Candidate local SQLite suite and exact-head regression CI are separate remaining gates before B-only intake. Main, production schemas, existing labs/fixtures and platform NOT_RUN records remain unchanged. P06 and historical OC/CR reviews are not repeated.

## Review focus

- SQL update before a later receipt failure: physical rollback of all four applied facts, pending preserved independently.
- Original committed intent at a now-stale revision: return original receipt; changed parameters conflict without reexecution.
- Simultaneous callers: ownership claim and CAS are checked under actual SQLite transactions, not process-local maps.
- Revision beyond 2^53/u64 max: no SQLite integer/float coercion, loss, wrap or artificial success.
- Missing/corrupt/foreign database and failed read-only recovery: no silent initialization, migration, source adoption or dispatch.

## Task 1: SQLite business transaction and process recovery

Create writer-owned `core/Cargo.toml`, `core/Cargo.lock`, `core/src/main.rs`, `core/src/sqlite.rs`, `core/tests/process.py`, `core/mutations.py`, `core/README.md`, `core/verification-evidence.json`, and `docs/tasks/REDESIGN-RD-P07A-20261014.md`. Split other core modules only where needed for clarity. Consumes unchanged RD-P01 path crate and installed SQLite runtime. Produces trusted one-shot lab executable `rd-p07-atomic` with `--db PATH --request JSON` and trusted startup fault controls; explicit init/read/preview/commit/lookup operations, unique provisional strict Rust request/reply representation documented in README.

- [ ] Write subprocess tests against a compilable scaffold; assert actual SQLite business rows, history, intent facts and receipts via independent connections. Cover full binding/raw normalization, CAS, same-name new intent, exact duplicate, altered binding, read-only/missing database and numeric boundaries.
- [ ] Build offline/locked and record actual behavior assertion RED; compile/import/setup failure is not RED. Logs only `/tmp/rd-p07a-evidence-20261014/`.
- [ ] Implement checked SQLite runtime wrapper, explicit fixture initialization, readonly reads/preview/lookup, atomic pending owner claim and transactional commit/replay behavior. Record exact installed runtime version/path/hash actually loaded; stop if an uninstalled dependency is needed.
- [ ] Add fault assertions before corresponding recovery implementation: SQL-stage process exits, SIGKILL barriers, actual receipt-insert failure, concurrent duplicate and CAS races. Observe physical rows/counts/bindings after reopening, including orphan pending unknown.
- [ ] Run complete new lab process suite and appropriate crate tests, report real unit and process counts separately. Preserve every failure encountered.
- [ ] Run five essential inverse mutation classes from the spec using a separate target, require successful compilation plus intended assertion failure, restore bytes/hashes and rerun GREEN.
- [ ] Commit only owned files; report full SHA, RED/GREEN/mutation counts, exact commands/evidence and unresolved limitations. Writer does not push/merge or spawn another writer/reviewer.

## Task 2: Immutable non-author and combination gate

B creates clean review checkout at fixed author SHA and packages full base-to-head diff externally; reviewer independently checks spec compliance and code quality, reruns the complete new suite and adds physical SQL assertions/fault probes. Findings go to the writer for test-first correction and fixed-SHA rereview. Review applies to the whole new branch, including wrapper resource ownership and fail-closed boundaries.

- [ ] Obtain non-author spec/quality C0, source byte restoration and scoped evidence; no author self-certification.
- [ ] Compare all baseline tracked blobs and exact author/candidate core blobs, latest develop dependency and source head.
- [ ] Run exact candidate local lab suite through reviewer and push isolated candidate for fresh existing regression CI. Record complete head SHA and CI terminal state; do not treat CI as Rust-lab coverage.
- [ ] With gates satisfied, normal B-only integration, exact parent/tree proof, post-merge CI terminal and remote sanitized report/FINAL delivery. Stop on permission rejection, preserve evidence, never configure new credentials or bypass repository rules.

## Preflight and ledger

External task ledger `/tmp/rd-p07-workflow-20261014/progress.md`; raw logs remain external and no workspace cleanup is performed. Contract and plan share requirements only; writer core and root documents have disjoint ownership. Task1 produces immutable executable/source and evidence consumed by Task2; review/candidate changes do not redefine the command or modify author source. This is an authorized isolated implementation under the existing plan; any new product contract decision is a stop boundary rather than a local schema freeze.
