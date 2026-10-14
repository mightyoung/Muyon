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
