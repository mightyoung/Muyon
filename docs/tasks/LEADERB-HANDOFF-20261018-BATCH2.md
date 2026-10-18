# LeaderB independent batch 2 — 2026-10-18

Status: STOPPED after source/evidence preservation. This session explicitly assumed sole LeaderB after the previous session completed. All three subagents finished; local builds/tests and source edits stopped. Only the integrator pushed the three independent branches. No combined candidate or develop merge was made.

## Resume from these fixed inputs

Previous short handoff: `6c724cee7a098869c077199bc3cae3cf31ff5535`, `docs/tasks/LEADERB-HANDOFF-20261018-RESUMED.md`. Fresh `/workspace/Muyon` was clean `work` at `cc7c8d14`; no applicable AGENTS.md, prior worktrees/tools/logs or active builders existed. Remote main/develop/product/HTTP heads matched before recovery. Original checkout remains untouched.

| Independent branch | Fixed source | Meaning |
| --- | --- | --- |
| `lab/android-service-verification-a-20261018` | `a0c14e13b700a57b92fabab19dd546a636da2741` | Four verification files only; actual product executions were at clean `2fbdc13efd84cabf04623775f87e762cd0d08c11`, before verification commits |
| `lab/leaderb-http-recovery-20261018` | `8e0f6b1d0abfb0115bf48fa0bc8c790bfe30fa16` | Six reviewed Rust files atop isolated HTTP `21acf36875da91c75157fddf6ef88e68c677a2ee`; no Android/checks/workflow changes |
| `lab/leaderb-checks-20261018` | checker code `7481ba0daf8954bb54139d2cf2a248edfd0ca5d0`, then this preservation documentation | Six checker files atop product2f; single owner; includes neither A verification nor B runtime changes |

## Actual new results

- A exact2f: existing Linux full GREEN (Rust9/JVM5, missing-library negative and panic containment), freshly generated JVM bindings and shipping library SHA256 `15d520efc06323709e2bbdcb6b8bf82bf214ac90520b5c936cc0ca8b4ebac8c1`. Shipping Service JVM four variants completed with original receipts, dedup/conflict, epoch/lease/visibility, lookup/status byte preservation, retire/join and root reopen. Associated durable oracle four variants and seven negative controls passed. State163 and independent Service Rust13 passed.
- A three new compiled shipping JVM inverses: dedup, stale epoch, global slot held until join. Every exact2f baseline GREEN, build0, precise mutant assertion exit1, natural process cleanup. Initial archive omission caused compile INVALID, retained separately and never counted as a kill; corrected rerun is `a-service-inverses-rerun/`.
- B TDD reproduced classification failures, `invalid_wire_state` on real metered reopen and durable unknown overwritten by a later cancel. A closed `native-host` provider discriminator permits bounded host-metered restoration without relaxing script/chat-sse or reconstructing authority. Budget remains `budget_exhausted/host_budget`; wire journal and outbound ledger failures preserve unknown; host inflight reopens unknown.
- B actual first process performs loopback I/O; a distinct process reopens the original bytes/task/attempt, drives twice and reopens again, preserves unknown and begin ledger, records no provider sends and no second connection. Post-I/O sent/failed-ledger failures are actual atomic-write failures. `wire_journal` specifically tests post-I/O checkpoint persistence failure, not charge-time failure or ENOSPC.
- Integrator exact8e0 default-parallel full Core115 / plugin22 / host59 GREEN, source clean/unchanged. All seven compiled HTTP inverses killed at their intended assertions: budget, journal, restore, inflight unknown, ledger unknown, unknown-over-late-cancel, shared charging. Checker controls: native29 / Android68 GREEN; all prior inventories/families and17 inverse definitions retained.
- Independent read-only final review: scoped PASS for A/B/checker sources and the above evidence. It does **not** approve product integration. Detailed final report is sealed by the evidence descriptor.

## Blockers and limits — do not silently upgrade

API24 arm64/x86_64 producers and package were actually attempted but INVALID setup: sdkmanager initially could not use the existing proxy; explicit JVM proxy/system trust fixed listing, then SDK/NDK packages were skipped because new licenses were unaccepted. No license acceptance or workaround was performed. API24 link, JNI/ELF/import checks, APK/native inventory/16KiB/zipalign/lint/AIDL and ordinary Android assembly remain NOT_RUN downstream. This is not an automatic approval rejection.

ART/Binder/UID/permissions/Android fsync/kill/rebind/device/emulator remain NOT_RUN. JVM global-slot contention is same-process evidence. JVM first payload and exact handler count were not directly observed; separate Rust observer runs are independent evidence and cannot be grafted onto JVM runs. HTTP recovery is test-only trusted session reconstruction, not a shipping HTTP Service resume API or live-provider acceptance. Legacy positive-wire host journals have no automatic migration. Original17/native3 inverses were not freshly rerun at B8e0; do not claim all existing integration gates passed.

## Preservation and next shortest step

`LEADERB-BATCH-20261018-EVIDENCE.json` records source identities, key raw-file SHA256 values and the local evidence archive seal. Raw logs, libraries, original synthetic fixtures, setup failures and reviews are outside Git at `/workspace/leaderb-evidence-20261018`; `/workspace/leaderb-batch-20261018-evidence.tar.gz` retains1391 files, excluding rebuildable targets/tools/work copies. Raw evidence was not uploaded remotely; a fresh environment must recover these files or rerun missing evidence, never invent it.

Before resuming, explicitly assume sole ownership, check AGENTS/remote heads/clean worktrees/stopped writers, and read this handoff. Preserve the A/B/checker split until all required integration gates are met. Resolve the SDK/NDK license/tool prerequisite through an authorized path, then rerun exact-source two-ABI/package gates and missing Service evidence. Do not block unrelated development for absent device evidence. New isolated heads have no new dedicated CI claim; branch-filtered archive pushes do not substitute for acceptance.

Exact product2f CI `39088023844` and PR85 head`34e388ee0c440ed191002067d7894c690a15610b` CI`39087025974` were freshly checked completed SUCCESS, including job/step states. Main remains `cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003`; develop remains `0ab2c4f667681b9aacb017f8cd2eea6f576cf78e`. No develop/main merge, force push, branch deletion, deployment, privilege/credential configuration, real model/GPU/data charges, dispatch retry or dispatch workaround. REMORY3/CTX14 and production memory remain untouched. This batch ends here.
