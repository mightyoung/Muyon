# Independent review — 2026-10-22

Reviewed working tree based on `68f0fb697699d3a8589fc2cc4f274edaf2b2a67d`, including the new untracked bridge and test source. Read-only review of production/test files; only this report and evidence were written in the repository. All synthetic databases and owner/ledger operations ran under `/tmp`; no actual network, user files, lib/FFI or owner changes.

## Finding P2 — settled tool-call cost is presented as unknown

Location: `crates/muyon-core/src/group_runtime/bridge.rs:151-153` (`original_json`). The `settled` predicate omits `tool_pending`, and the per-chain-item cost predicate also omits it. A real `AgentOwner::settle_response` validates token usage, writes the exact charged amount, and changes the request from `unknown` to `tool_pending` when a valid tool-call response arrives. The charge is therefore already a known owner fact, even though the tool/request chain is still unfinished. Both run and workflow projections use this helper, so the UI can continue to hide a known paid charge throughout tool review.

Reproduced offline using the actual BusinessStore, RunLedger and AgentOwner. Create a remote child; prepare/confirm/claim the synthetic plan; settle a valid `product_supplier_list` tool-call response with 17 input and 4 output tokens; read workflow through the bridge. Owner status becomes `tool_pending`, charged amount is `66`, but UI `actual_micro_cny` and its chain entry are null, and `actual_usage_known` is false. The added independent assertion fails (`Null` vs `String("66")`). No tool execution or provider traffic occurs.

Suggested repair: include tool_pending in known-cost status handling, while separately keeping request-chain resolution/terminal handling conservative. `group_ui_run` currently uses actual_usage_known to decide unresolved, so simply expanding that predicate without separating outcome state would introduce a new misleading resolved state. Preserve null cost for actual Unknown and retain all grant/dispatch restrictions.

Evidence: `evidence/independent-counterexample.log`; independent fixture saved as `evidence/independent-review-harness.rs` and its manifest as `evidence/independent-review-Cargo.toml`. Original temporary runnable project: `/tmp/mig20-independent-review`; rerun with the environment variables stated in PLAN and `cargo test --offline --manifest-path /tmp/mig20-independent-review/Cargo.toml independent_ -- --nocapture`.

## Verified

- Independently ran original targets: bridge **34/34**, store **65/65** passed (including source-imported duplicate tests); see `evidence/independent-original-tests.log`. Only existing read/write runtime-symbol warnings appeared.
- Added independent behavior test passes: Configure replaces future defaults with fixed coordinator c and removes a/b; existing per_task run still hands off to its captured b using actual owner, and a new run captures fixed c. This exercises actual operations beyond merely checking captured JSON fields.
- Legacy rows are frozen to the persisted prior mode in the same transaction before defaults change; new Start captures mode and members. Handoff now uses the captured mode. Existing grant-tail checks and Unknown receipt branches remain unchanged in the diff.
- Native UI scope has private fields and checks actual workspace/project/epoch. Strict read/change schemas exclude caller scope and authority. Configuration preparation creates a GroupCommand and no grant or persistence.
- Workflow facts really come from RunLedger.execute snapshot and contain lifetime rows rather than truncated event inference. Original owner lookup correctly matches the actual child conversation; canonical payload digest binding and Gateway permit remain explicitly unavailable. This interface is real and must not be described as missing.

## Finding P2 (SQL-trigger fault model) — legacy capture can be silently undone before a committed configuration

Location: `crates/muyon-core/src/group_runtime/store.rs:801-816`, new Configure migration. An UPDATE affecting one row proves an attempted freeze, not that the frozen record remained persisted. With an AFTER UPDATE trigger that restores OLD.record on group_runtime_runs, configuring a legacy per_task run to future host_only defaults commits. The old run still lacks coordination_mode and group_run now falls back to host_only, retroactively changing its handoff semantics. The final tail reads the group record, exact grant/intent/event, but not the changed legacy run record.

Actual offline counterexample `independent_legacy_capture_survives_configuration_tail` prints `CONFIGURE_RECEIPT=Committed EXISTING_RUN_MODE=Some("host_only")` and fails the invariant that committed Configure must leave the existing run per_task. The trigger only undoes the new freeze write; no arbitrary external file or owner mutation is involved. Evidence: `evidence/independent-legacy-tail-counterexample.log`, same independent harness. This is a local storage/trigger correctness boundary, not an assertion that models can inject SQL or dispatch calls. Under the trigger fault model already used to verify local transaction tails, retain and finally verify the expected affected legacy run records, or fail uncertainly and roll back. A failure should not issue a fabricated definitive rejection.

No denied/pending action. Two confirmed correctness findings above; the second specifically assumes the existing synthetic SQL-trigger fault model. No authorization/dispatch escalation found in reviewed scope.


## Final independent re-review — both findings repaired

Reviewed the revised production diff and independently reran the ORIGINAL three appended counterexample/control tests without modifying their source or assertions. `/tmp/mig20-independent-review/review.rs` and the saved `evidence/independent-review-harness.rs` remain byte-identical SHA256 `67113e0b32fa9585ba46b7a7d01ee7f269c2f63407720263d8e943351324bad7`. All **3/3** now pass: tool_pending current/chain cost is `66`, actual_usage_known is true, original_chain_resolved is false; undoing legacy capture produces PendingOriginal and retains old per_task; removed-member/new-default control remains passing. New log: `evidence/independent-final-counterexamples.log`. Original RED logs above have not been overwritten.

Verified in source that cost settlement includes tool_pending/tool_consumed separately from chain resolution (only completed/cancelled/failed). `group_ui_run` now derives unresolved from original_chain_resolved, preserving reconciling/deadline behavior for paid but unfinished tool chains. Missing/unavailable owners explicitly report chain unresolved.

Verified that Configure captures the intended complete ordered set of run_id/group_id/record rows before trigger-capable migration writes, updates expected records to the intended legacy freeze, then compares the actual complete row set in `group_consume_and_verify_tail` AFTER the exact active-grant consumption UPDATE. Only reads follow that comparison before commit. A mismatch returns Storage, causing rollback and PendingOriginal rather than a fabricated terminal rejection. The comparison covers both legacy freeze and later record/set damage, including receipt and consume triggers. The existing grant, scope, receipt, event, expiry checks remain present.

Independently reran native targets after repair: bridge **38/38** and store **65/65** pass; see `evidence/independent-final-native-tests.log`. Bridge38 comprises the prior34 plus four test functions; its source-imported tests remain included in those counts. Native regressions additionally assert tool_pending chain cost/unresolved state and receipt/consume run-record mutation rollback across group/run/event/receipt/grant.

Final source SHA256 at verification:
- store.rs: `96c255f87d0fde55125fe3261c316136a743797918e5caaf433e85db23cb8780`
- bridge.rs: `b14177400e5b10ea726f7ab73cdb51be05652a49bb21a4123d3309eccf5a383d`
- group_runtime_bridge.rs: `4b587ad9e2233ec3a1bd381a181bfdd1399c61922478ceaa697403d5f0387b60`

Final conclusion: both independently reported P2 findings are remediated in the reviewed tree. No remaining important regression or scope/authorization finding identified in this review. No denied, pending, or uncertain action; production and test sources were not edited by this reviewer.
