# MIG20 canonical binding — deliverable and limits

Base `8e3a658feea7c463b8a22dbd320e4fb3f47cf7af`. Isolated branch `task/mig20-group-canonical-binding-20261022`. No main/develop, protected lib/FFI/host/Android/documents, lockfile, gateway claim/allowed or historical Unknown edits.

## Implemented

- Actual Owner canonical request reread with persisted-byte SHA256, opaque typed identities, restart read without fake config history.
- Actual RunLedger complete-lifetime native admission facts: physical index/record, project/root/parent, child uniqueness, actual Owner chains, context/skill/revisions; no caller plan/JSON proof. Event pruning does not erase child capacity.
- Real BusinessStore namespace and exact durable group/run/root/node/member -> actual request/digest/config/epoch/revision/workflow identity mapping. Local grant-confirmed BindCanonical uses existing journal/effect/CAS/receipt/consume machinery. The original Owner request is never dispatched, replaced, refunded or advanced by association.
- Same-transaction intended mapping/node/run/group and actual source Plan journal/command/event witnesses, verified after all trigger-capable writes, including local grant consumption; failure leaves original local intent pending and rolls back effects. Mapping read validates its actual committed provenance.
- Owner/RunLedger recheck after restart/configuration/stop/context changes; exact canonical child conversation used by existing UI and original query. Missing sources preserve durable identity/query-original state, never fabricate ready/zero-usage. All pending canonical chains gate Handoff; missing command/chain evidence stays inconclusive.
- Parent parameter-count findings addressed by typed private GroupEffectWitness and GroupWorkflowRead and all real callers. No new lint allows. Existing public native recheck has7 parameters including self.

`INTERFACES.md` gives exact native APIs, tables, suggested FFI schema, explicit requested hooks and cross-database consumption/recovery protocol. New module is a child of the already-exported group store, requiring no new core lib.rs patch. AgentOwner/workflow are minimal additive API ownership shared with parent explicitly; fixed B863ece files were unchanged from base before this overlay (empty diff evidence).

## Actual verification

Environment: existing Rust1.99.1 `/tmp/mig20-rust/bin`; `CARGO_HOME=/tmp/mig20-cargo`, `CARGO_TARGET_DIR=/tmp/mig20-target`, `RUSTFLAGS=-L native=/tmp/mig20-native-libs`. No install/network/provider/model/search call. Synthetic fixtures create independent temporary SQLite files. Synthetic claim_dispatch returns bytes that are never sent; it exercises actual hold/Unknown transitions in those fixtures only.

- `python3 docs/tasks/mig20-group-canonical-binding-20261022/verify.py`: owned rustfmt PASS, complete `cargo test --manifest-path crates/Cargo.toml -p muyon-core --offline --locked` PASS **346 test executions**; diff check PASS. Core canonical target40 = **22 dedicated new tests +18 source-module repeats**. Existing bridge53 and store65 are included in346, not additional new tests.
- `python3 docs/tasks/mig20-group-canonical-binding-20261022/verify-combination.py`: fixed B `863ece54c3d9ba0fc9900d71ec310a4764b9e1a4` real document/other source archive plus ONLY owned production overlay/new source-harness document declaration. Canonical87, bridge100, store112, **299 executions PASS**, including repeated shared modules. Core owner lib/FFI/document source not edited in composition.
- Both native/B Clippy invocations exited101 **before analysis**: `cargo clippy` unavailable in selected existing toolchain. Explicit **NOT_RUN**, not lint PASS; original stderr and manifest retained. No software installed. Verify runners return nonzero for incomplete gates. B's unrelated unused-import/runtime-symbol warnings retained, not repaired on this behavior branch.
- Test-first compile RED and actual behavior RED remain in evidence01–17, including digest/physical indexing/duplicate refs, canonical UI child routing, changed actual configuration, pending scheduling, provenance/capability mismatch, failed local mapping/Unknown Handoff, missing original metadata. Independent review preserves additional actual RED source and logs, including all-pending-chain and same-transaction Plan-tail counterexamples; repairs rerun original assertions.
- Final independent review: all ORIGINAL7 counterexample assertions PASS unchanged; independently run canonical40 + bridge53 + store65 =158 executions PASS (subset/repeats, not additional unique coverage). All actual findings closed, no remaining Important finding within this native-local scope. Exact frozen8 source/test hashes matched implementation verification.
- Frozen source hashes and exact commands/statuses in `evidence/final-manifest.json`, `combination-manifest.json`, and independent review/evidence. No failed run discarded or relabeled PASS. Pre-final345 and final346 are distinct stages, not cumulative coverage.

## Remaining owner work / non-claims

Native durable association and readonly recovery are implemented and exercised; FFI operation routing/trusted account-project identity selection and existing sole host gateway recheck/consumption are not wired by this branch. Concrete APIs and proposed schema are delivered for those owners. No root-wide budget/attempt accounting or cross-SQLite atomic permission exists in current RunLedger; returned facts explicitly mark those unavailable/false. Host mutex does not create distributed atomicity. Do not release publication/engine isolation/real execution HOLD on the basis of this branch. Local rejected Handoff may prove coordination not performed while its original external request remains Unknown; inconclusive storage/chain reads remain Pending. Historical legacy pending without identity metadata conservatively blocks new advice/handoff and is lookup-only, never fabricated or replayed.

Remote verification is recorded separately after commit/push to avoid self-referential commit hashes. Parent must preserve B's unrelated mechanical cleanup while integrating these behavior-owned files.
