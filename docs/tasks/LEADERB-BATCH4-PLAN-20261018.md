# LeaderB Batch4 validation and repair plan

> Agentic execution: three isolated subagents implement independent work; the sole integrator reviews and combines. User explicitly authorized this execution method and task-branch commits/pushes.

Goal: close same-source Android and formal CI gaps and investigate the two preserved timing failures, without adding features.

Architecture: A owns Android tooling/build/Service verification; B owns formal gates/contracts/workflows (including core/mutations.py); C owns Rust timing behavior and physical fixtures. Only LeaderB /root integrates. Independent reviewers receive immutable candidates.

Spec: user delegation dated 2026-10-18; immutable handoffs 49d3f6030c4d3464d66b4b6421e5cc416aa36133 and ff93284bd0c3a9e22d5b239743eb5e717cbc88ad.

## Inputs and ownership

- Base product: d25a407830ef624802583983c0be2414bbd59dc4. develop: 0ab2c4f667681b9aacb017f8cd2eea6f576cf78e. main: cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003.
- 2026-10-18 04:12 UTC: remote refs, open PRs/issues, recent Actions and local processes checked. No other active integrator found; latest Actions predate batch and are completed. This is observed scope, not a global session lock.
- Root integration: /workspace/batch4/integration, lab/leaderb-batch4-combined-20261018.
- A: /workspace/batch4/android, lab/leaderb-batch4-android-20261018; Android-specific files/tools/evidence.
- B: /workspace/batch4/gates, lab/leaderb-batch4-gates-20261018; scripts, contracts, workflow and core/mutations.py.
- C: /workspace/batch4/timing, lab/leaderb-batch4-timing-20261018; Rust and physical fixtures, excluding mutations.py.
- Evidence: /workspace/batch4/evidence/{android,gates,timing}; previous raw restored read-only by convention at /workspace/leaderb-b3-evidence. SHA256 5d44399e51939d0ae74f98225a58c2295e3003fc37df9cb7b13cb2605f929cd1 verified before extraction.

## Constraints and review focus

Retain original negative controls, 100ms idle and 5000ms total budget. Preserve historical failed logs. Exact SHA evidence cannot be grafted across versions. Formal gate must execute final candidate itself; external runner green is supplementary. SDK acceptance limited to selected android-sdk-license hash24333f8a63b6825ea9c5514f83c2829b004d1fee. No main edits/force push/deployment/paid APIs/credentials/new privileges. No RSI handoff or REMORY implementation. No Claude review is claimed. Device/ART/Binder/UID/kill results remain unverified unless actually run.

## Tasks

- [x] Read fixed handoffs; preserve baseline snapshots, inspect ownership, verify and restore raw archive.
- [x] Create clean isolated worktrees and dispatch A/B/C with explicit file/tool ownership.
- [ ] A: recover fixed official Android skills and tools; execute native/Service/JNI/package/ordinary build and negative controls on exact source. Retain command, tool, SHA, exit and artifact identities.
- [ ] B: reproduce inventory/anchor/pin rejection; add failing checker tests; minimally repair formal contracts without weakening original gates; run all old and added controls; commit.
- [ ] C: extract original failure details; test scheduling and durable-I/O hypotheses with controlled comparisons; add deterministic regression before minimal justified fix; commit or state unresolved cause explicitly.
- [ ] Integrator: inspect diffs and resolve ownership/dependencies; combine onto new task branch; fix candidate SHA.
- [ ] Run same-source final validation and formal remote CI to terminal state; commission independent code/evidence review. Repeat affected checks after any fixes.
- [ ] Merge develop only if review/necessary tests and existing integration restrictions permit; otherwise record precise remaining hold without declaring acceptance.
- [ ] Preserve raw evidence and next handoff; stop all writers/builders and report clean state.
