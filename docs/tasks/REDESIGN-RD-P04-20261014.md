# REDESIGN RD-P04 — device-deferred Android mock first slice

Date: 2026-10-14. Status: Kotlin host state implementation delivered for review;
Compose and Android device acceptance NOT_RUN; M03 blocked_contract.

Owner: delegated `/root/device_deferred_android_mock`; sole develop integrator
remains Leader B. Worktree `/workspace/Muyon-device-deferred-android-mock-20261014`,
branch `task/device-deferred-android-mock-20261014`, fixed base
`b17ac548f7a8d2d6151cbdaf6af527722c67ee50`.
Exclusive write ownership: `experiments/redesign/device-deferred/android-mock/`
and this task file. Existing writers and all product code remain untouched.

Inputs: Android v1.3.2 Addendum, page handbook D01.1; M02 supplier-name decisions;
D01a authorization-minimal and D03a recovery-minimal contracts/experiments. User
explicitly authorized four parallel development tasks and deferred real devices.
The mock seam is reversible and does not freeze M03 or assert all original exits.

Deliverables: Presenter.kt (state + RustCorePort + mock), SupplierScreen.kt
(Compose state consumer source), tests/PresenterTest.kt (complete JVM suite),
run-tests.sh and README.md documenting the trust boundary and remaining gates.
No dependencies, licenses, credentials, real data or device/ADB access added.

## Actual verification

Existing Kotlin 2.2.20 compiler and Temurin JDK 17 compile the presenter and tests
with stdlib only. Initial assertion RED: 1 passed / 17 failed, Java exit 1.
Fresh-intent regression RED: 20 passed / 1 failed, exit 1. Navigation/unknown RED:
22 passed / 1 failed, exit 1. Final complete JVM suite: 23 passed / 0 failed, exit 0.
Raw logs remain outside git under
`/workspace/reports/device-deferred-rd-p04-20261014/`. Binary output is outside git
at `/tmp/rd-p04-output`. `git diff --check` is required before commit.

These tests exercise actual presenter behavior through a synthetic port. They
are neither Compose tests nor true Rust calls. Existing baseline regression/CI is
owned by the integrator and must run on the combined candidate before integration.

## Deferred gates and provisional contract

Android actual load **NOT_RUN**. Compose compilation/rendering/accessibility,
200% font, keyboard and orientation verification **NOT_RUN**. True Rust adapter,
durable commands/receipts/drafts, unknown reconciliation, explicit conflict
resolution, read/write revocation and new-stream resync are not delivered here.
They remain required product/acceptance work; no missing gate is relabeled passed.
M03 single schema/generator/transport and Unicode implementation equivalence remain
unfrozen. The UI displays MOCK and simulated receipts, not real save success.
Scope includes FullAllow without extra risk confirmation and trusted hard-deny;
actual trust evaluation belongs to the future verified Rust port, not a UI boolean.

No develop/main merge, force push, branch deletion or deployment by this writer.

## Independent R1 correction (follow-up, original 23 tests retained)

Non-author review at fixed `7ba6604313fe78fb69b4839947c726e9e8bbb407` withheld C0:
registered Command did not retain expected revision; blank or unchanged result
revision entered the receipt ledger and projected SAVED. The two original
rejection assertions were added before the fix: actual JVM RED **23 passed /
2 failed**, exit 1. Additional binding/invalid/recovery cases ran RED **26 passed /
6 failed**, exit 1 after adding the command field but before enforcing the relation.

Command now immutably stores `expectedRevision` from the draft in the existing
in-memory submission register. Effects must match that entire registered command,
original supplier and meaningful receipt reference before accounting. The temporary
mock grammar is canonical `r<decimal unsigned 64-bit counter>` with no leading
zeroes; an effect result must be the exact arithmetic successor (+1), and an
expected max-u64 has no successor and cannot dispatch. No lexicographic version
comparison or M03 wire/schema freeze is introduced. Opaque product revisions and
actual adapter authority remain unresolved; this grammar belongs only to this lab.
It is not on-disk persistence or durable restart recovery.

Complete suite **32 passed / 0 failed**, exit 0. Retained all original 23 cases,
including late authentic mock receipts and unknown navigation. New cases reject
empty/unchanged/malformed/skipped/backwards result revisions, forged expected
binding and invalid/overflow expected revisions; accept r9→r10; retain original
expected revision when a snapshot changes; and allow unknown recovery only with
correct original revision-bound receipt, with zero resubmission. False-like string
`false` is rejected; Kotlin's typed seam does not accept a Boolean revision.

Three independent temporary reverse mutants outside git compile successfully and
fail assertions with Java exit 1: removing result relation (5 failures), removing
exact command expected binding (1 failure), removing expected-successor guard
(1 failure). Raw logs/source copies/binaries stay outside git under
`/workspace/reports/device-deferred-rd-p04-20261014/fix/` and
`/tmp/rd-p04-revision-mutants/`. The restored source suite is rerun before commit;
non-author fixed-head follow-up and combined candidate checks belong to Leader B.

Compose source requires no signature change because it consumes ScreenState and
callbacks rather than Command. Compose compilation/rendering and Android actual
load remain **NOT_RUN**. M03 remains **blocked_contract**. No dependencies,
licenses, real models/data or device access added.
