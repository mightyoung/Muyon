# MIG20 group runtime delivery

2026-10-22. Independent branch `task/mig20-group-runtime-20261022`, worktree `/workspace/mig20`, fixed implementation base `7fde617bab8f45644820590529def5b2f2193454`. Delivers executable offline coordination logic and tests; it does not claim external Agent execution or product integration.

## Delivered behavior

New `crates/muyon-core/src/group_runtime/mod.rs` provides:

- Explicit HostOnly / Fixed / PerTask leader selection. HostOnly rejects a task leader, Fixed uses the configured member, PerTask requires an explicit valid task member. No user setting/default is changed. Original governance API still rejects Fixed/PerTask; the new runtime separately validates captured mode/leader then reuses the original host-only mechanical gates through a validation projection.
- Deterministic one-next-intent advice and state projection: Ready/available slots, Stopped, Deadline, Reconciling/original request IDs, RoundLimit, BudgetLimit. Host snapshots remain the only child/request/accounting source. The runtime never synthesizes dispatched, running or completed children. Concurrent advice does not claim atomic admission.
- Owner/admin human management separated from coordinator proposals. Coordinator origin must match current leader and epoch, and has no management or additional grant. All modes use the same four named policy layers plus worker capability, DAG/depth/lifetime/active limits and checked root budget accounting.
- Bounded PerTask handoff at an inactive, resolved checkpoint. Owner/admin authorization, allowed member, stop/deadline, max handoffs and epoch overflow are checked before changing the candidate. Handoff returns next identity, old/new leader, a narrowed grant, exact material scope/source/version references, completed node IDs and unchanged root budget. Narrowing remains effective when handing back to an earlier leader. Fixed mode is selected at task creation; in-run handoff is a PerTask feature.
- Stop is monotonic within the captured runtime. Prepared, Submitted, Unknown, unknown budget markers and unknown children prevent new advice/handoff. An identical original command returns its original request/state even after stop or across a coordination epoch; conflicting payload/identity refuses. Query advice is not a network call, refund, retry, settlement or release of reservation.
- Host-attributed parallel observations with original request, member, child, full identity, sequence and event ID. Completed requires matching host child state and original receipt plus artifact references; model text cannot establish success. Unknown may resolve only via a newer event for the same original request, backed by the host's changed receipt. Duplicate events deduplicate; conflicting/old/future or misattributed events refuse.
- Summary preserves completed/failed/unknown nodes, latest speaker/artifact attribution, claim evidence, source versions, observation time and primary-origin deduplication. Contradictory support remains visible; counts do not establish truth. Current-epoch event history preserves earlier dissent when an unknown resolves. Old-epoch results are archived as late evidence and do not enter current summary or authorize work.

The runtime owns coordination/summary state only. It does not create a second persistent queue, command ledger, billing system, model gateway or transport trait. A second parallel slot is advised only after the host supplies its authoritative updated ledger and resolves the original command receipt. Submitted originals deliberately block new advice; this is conservative offline scheduling, not demonstrated parallel model inference.

## Files and fixed inputs

Owned implementation/test files: `crates/muyon-core/src/group_runtime/mod.rs`, `crates/muyon-core/tests/group_runtime.rs`. Owned plan, review and evidence are in this task directory. No existing source files changed, including lib.rs, group_governance, documents, workflow, MainActivity/ChatScreen or ProductService/ProductChatRuntime.

Read design master and group research/GR-01–08 at design intake `400e206135690c284c8402521e3135cfb7bfaee8`; governance implementation/report/tests at `7fde617bab8f45644820590529def5b2f2193454`; core exports at document-core `f4a8e8d3971208f16d4a3b1ddff5d4e8fb2a63ac` and UI combination `98baa979223d96094f11a56c3ac6d48f9b84c0eb`. No AGENTS.md / .agents skills exist in the saved workspace or relevant fixed trees. Existing embedded supplier/paper skills concern model tools and are unused. Network operations were limited to authorized repository reads/push, verified official Rust toolchain archives and the existing Cargo lock dependencies in temporary task storage; no real model/search/provider or user document access.

## Interface requests for coordinator / owners

1. **Core owner only:** UI/core fixed baselines currently have no group_governance export. Bring the existing governance dependency from its pinned branch, then add `pub mod group_governance;` and `pub mod group_runtime;` to the combined lib.rs (each once). This task deliberately does not edit lib.rs or the original governance contract. No shared document contract change is needed.
2. **Host owner only:** join trusted current config, immutable task leader choice, complete lifetime children/commands, root budget, node assignment/provenance, grants and material/artifact resolution into consistent snapshots. `Command` does not carry member assignment; the plan passed to collect must be the host's authoritative node specification, never model JSON or a display list. Named Policies clarify mapping but do not authenticate provenance by themselves.
3. Persist coordinator identity, lifetime handoff count, narrowed grants and stop state in the existing host store. `Runtime::new(..., now, handoffs)` is restoration from that store, not permission to reset epoch/count/stop/deadline. Rebuild observation history from trusted durable host events with their matching historical receipt projections; this module is not a persistence layer.
4. Handoff changes an **offline candidate**. In the host's existing transaction, compare expected current identity/epoch and lifetime count, check the inactive checkpoint again, persist next epoch/count/grants, then publish the candidate. Discard it on failed CAS. Two separately created runtime objects do not provide durable atomicity or a live host lease.
5. Every Eligible remains advice. The existing sole gateway must recheck host lease, full current authorization, payload digest, recipient/provider/data scope, approval and production cost proof, lifetime/active/round limits and original receipts in the original intent/reserve/claim transaction. No new gateway or capability is authorized by leader selection. Provider change requires the original data-recipient approvals; a reference package alone is not permission to disclose material.

These are bounded owner integration requests, not shared-file changes attempted by this task. Existing engine isolation and production HOLD remain in force.

## Verification and independent review

Test-first history is retained in `evidence/`: initial API behavioral RED **0 passed / 13 failed**, then 13 passed; projection RED **15 passed / 3 failed**, then 18 passed. Independent review reproduced IR-01 (earlier dissent lost on Unknown→Completed); the task regression genuinely failed before repair, then passed with history-based claim aggregation. Final review found no remaining confirmed important defect in this offline candidate. See `INDEPENDENT-REVIEW.md` and archived independent reproduction/RED evidence.

Final automated run `python3 docs/tasks/mig20-group-runtime-20261022/verify.py`:

- standalone runtime **20 passed / 0 failed**, compile `-D warnings`, exit0;
- standalone original governance **21 passed / 0 failed**, compile `-D warnings`, exit0;
- full locked/offline `muyon-core` Cargo suite **188 passed / 0 failed**, 17 test binaries plus 0 doc tests, exit0;
- rustfmt check and authored-file staged whitespace check exit0. Full staged raw-evidence check exits2 for original whitespace in 16 raw logs; bytes are intentionally retained, detailed in `staged-check-status.json`. The earlier unstaged check exit0 did not inspect new staged files. All fresh command/status/time/hash details are in `evidence/final-manifest.json`;
- independent final runtime **20/20**, archived stdout/stderr and exit statuses. Reviewer also independently ran the repaired IR-01 probe and the 19-test Cargo candidate; this is distinguished from the author's final full-suite result.

Two pre-existing Cargo warnings concern runtime `read`/`write` declarations in `experiments/redesign/core-agent-lab/core/src/host_session.rs`. No source/lock configuration was changed to silence them. Official Rust 1.99.1 archives were SHA256-verified and extracted only under `/tmp`; system toolchain directories were not installed into. Initial Cargo offline failed for absent serde cache; after fetching the existing lock dependencies, linking failed for missing `libsqlite3.so` link name. The existing system `libsqlite3.so.0` was referenced by a task-local `/tmp/mig20-native-libs/libsqlite3.so` symlink, without project linker changes. All initial failures remain archived.

An intermediate compile failed under dead-code warnings, and a shell invocation then accidentally executed the previous binary: `09-projection-red.log` is stale 13-test output, explicitly invalid for that candidate. Correct compilation and behavioral RED were rerun under a distinct binary (`11`/`12`); final verification script skips dependent test execution after compile failure. Historical status/meaning for every old log is recorded in `historical-status.json`; none are relabeled as final passing evidence. Original scaffold source snapshots were not retained, so historical RED logs are not advertised as exact-source replay fixtures. The independent IR-01 reproduction source was retained.

## NOT_RUN and retained limits

NOT_RUN: Android/FFI/UI wiring and device/TalkBack/APK checks; durable host CAS/crash/concurrent admission integration; actual provider/model/search execution, recipient changes, real paid cost/usage settlement; production schema migration or human multi-user sharing; remote CI terminal validation. This branch does not claim these completed. The two historical unknown requests and reserved ¥0.002620 were not queried, retried, settled, released or otherwise touched. Unknown usage remains unknown and no synthetic event changes the original ledger.

No main/develop change, force push, deletion, deployment, paid configuration, credential change, security permission expansion or engine-HOLD bypass was attempted. No action was denied by automatic approval review. No mutation has an uncertain outcome. Branch publication and exact remote SHA are reported separately after push; this report does not claim a merge.
