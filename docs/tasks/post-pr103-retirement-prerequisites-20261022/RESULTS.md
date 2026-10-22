# Post-PR103 retirement prerequisite candidate

Base: `4d15b990f725d41a43b86fcd2b170b2219a6f766`.
Formal source: `974a7fcd65d29a7d31c5b6a12f9eb5e79e918679`.
Reviewed/tested source tree: `e6c4469a6d32804e51dffc76f1e3eaacc9781ea9`.
Local review commit `50ce62bf7033f63e4632e362ecd95fa7524c3ee0` has exactly that same tree and parent. Existing connected GitHub tree/commit tools created the formal commit; the remote tree hash and reconstructed raw commit hash were verified. This is a new candidate, not a claim that the old local commit was pushed unchanged. Old `2283acf175c8f0ab37de8a6d1135d3fde2d27314` / `3f4793e9790c8e18e967e847d60b368783b42dac` and their branches/evidence remain untouched. Evidence seal is a separate docs-only child; its exact SHA is in the publication readback.

## Scope and three reviewed corrections

Only 11 source/reference paths differ from develop: ci/verify workflows; three prerequisite scripts; the supplier_store Rust test; three schema12 fixture files; two historical reference inventory documents. Outside these paths, parent mode/type/blob bytes are unchanged, preserving Office/Bot/UI/aeb, the three production Rust path dependencies, product gates and coverage floors. No Flutter directory or user file is removed. No active entrypoint switch, new engine, model/search request, credential change, PR or merge is performed.

1. Existing ci/verify job IDs retain Flutter body and PIPESTATUS failure propagation. Both depend on independent laya-offline and use job/step always() plus an actual Bash assertion accepting only success. Failure/cancelled/skipped/empty/unknown are locally executed negative cases. Four original Laya tests run independently of Flutter and stop on any failure. Whole-workflow force cancellation may cancel a queued job before the guard executes; cancelled never means success. Hosted cancellation injection and branch-protection configuration are not verified.
2. Historical SOURCE_PIN remains 214b4031deb38ca7dfd35ee86396089eb48157d5; GATE_BASE is current develop4d15. Exact comparisons preserve current on/selector, original Flutter body, coverage threshold/suites and aeb diagnostics/tests. Updating only GATE_BASE first produced two real fetch-pin failures; updating both workflow pins restored green. No trigger was added to get a green result.
3. Schema checker trusts fixed reviewed literal sizes/SHA256/Git blob IDs, hashes actual bounded bytes and rejects a manifest that redefines them. Full23-reference inventory has a fixed raw SHA256, then actual historical object size/hash/blob comparisons. Missing history fails, without silent skip. Both independent CI jobs explicitly fetch four immutable commits and execute checker plus all15 contracts before Laya. Negative tests really mutate copies: synchronized fixture+manifest, forged blob, missing/corrupted files, missing manifest/history, empty inventory and Laya failures. A future change to verifier literals is new source requiring review, not a cryptographic signature boundary.

## Actual verification

On clean local50ce/treee6: contracts15 PASS; original Laya8+4+8+9=29 PASS; named supplier_store12 PASS; production Rust workspace/all-targets601 reported executions across33 groups, zero failed/ignored; strict Clippy -D warnings exit0. These are overlapping executions, not601 independent scenarios. Commands, full source SHA, UTC times, dirty=false and exits are retained in evidence JSON/raw logs.

On clean formal source974a: contracts15 PASS, separately recorded. Independent review reran15 and checker on50ce, found Critical0/Important0/Minor0, and then independently confirmed974a tree+parent identity. Broad Rust results are the verified identical-tree50ce execution, not misreported as a second run on974a.

A fresh isolated shallow Git repository fetched the exact four pins from the existing local Git object store, then ran checker and all15 contracts successfully. This validates missing-history provisioning with real shallow objects, not new GitHub network behavior. The previous2283 public-network four-pin fetch is historical only; new4d15 GitHub CI transport remains subject to hosted execution. Shared Git was not made shallow. Original REDs are separately labelled historical; new integration-pin RED is retained alongside new GREEN.

## Publication and remaining limits

Publish only independent task/post-pr103-retirement-prerequisites-20261022 using the already restored same-user GitHub connection. This matches an existing task/** selector; no workflow_dispatch or selector modification is introduced. Fresh hosted CI is pending publication at seal time and cannot inherit PR103 green. Manual macOS verify and hosted failure/cancellation injection remain NOT_RUN. No PR is created; parent will independently review before organizing it. No merge authorization is inferred for this slice.

This is a prerequisite, not completed Flutter/Dart retirement. All six old workflows, ci/verify/doctor/packaging entrypoints remain active; old red2395<2401 history is retained and never rewritten as green. Historical inverse Dart entrypoint closure is incomplete; Electron/full inquiry replacement remain unready. Laya selection_set.json still must move before future old apps deletion. No new Flutter installation. Library upload401 is unrelated and not retried. I04/legacy task.db-HTTP-reopen, denied Reader work, old403 objects, real model/provider/search/Office engine and persistent credentials were not used. Existing verified=false/live capability HOLDs remain.
