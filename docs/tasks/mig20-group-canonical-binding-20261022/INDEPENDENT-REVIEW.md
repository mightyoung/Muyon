# Independent canonical-binding review — initial findings

Branch task/mig20-group-canonical-binding-20261022, base8e3a658feea7c463b8a22dbd320e4fb3f47cf7af. Review in progress, not a final approval. Reviewer writes only this task report/evidence plus /tmp synthetic fixture/harness files. No network/provider/user files or historical/user Unknown opened or mutated. Synthetic fixture requests are prepared/claimed/settled locally with unsent bytes when tests require Unknown/terminal states. Code reviewed: additive actual Owner binding, typed actual RunLedger admission projection, local canonical association plus existing group tail integration.

## P2 — canonical-associated group run is unreadable through existing UI

A valid actual Owner request prepared in a real remote child conversation is bound to a real ledger child and mapped through Plan + BindCanonical local grants. The store group_lookup_original succeeds, but existing bridge group_ui_read(run, actual owner) calls original_json against the group's ROOT conversation, so it fails ScopeMismatch. All correctly mapped canonical remote-child nodes trigger this regression whenever the actual owner is bound. Read path should use the validated canonical association to select original conversation (keeping conservative legacy BindOriginal checks), and retain Unknown/query-only semantics.

Actual offline counterexample: independent_canonical_run_remains_readable_in_existing_ui prints CANONICAL_RUN_UI=Err(ScopeMismatch) and fails. No fault injection or arbitrary SQL is needed for this case.

## P2 — admission facts can silently omit a physically misrooted child

RunLedger.admission_facts queries only rows with matching physical scope/root, then validates records inside that subset. A child whose physical root is changed while its persisted record still has the original root_id is excluded before validation. With two actual children, projection returns one child and active_child_count1 with complete_lifetime_children=true. This is incorrect lifetime/capacity evidence under the persisted-integrity fault model explicitly exercised by the new API. Validate physical indexing vs record associations before presenting a complete root projection; do not rely on the same potentially inconsistent filter to decide which rows need checking.

Actual counterexample: independent_actual_facts_must_not_hide_physically_misrooted_children changes only physical runs.root for the sibling and fails because facts return Ok with the child missing. This is not a claim that models can write SQL or that the returned facts are a dispatch permit.

## P2 — actual facts accept duplicate original identity across children

The original RunLedger.bind_remote_plan writer prevents one original from being assigned to multiple children. New admission_facts verifies each row's Owner chain in isolation, but not cross-child original/conversation uniqueness. Copying the first child's conversation, remote_request_id/current_request_id/remote_request_ids and status into the second child's persisted record yields two typed child facts for one actual Owner request, with complete_lifetime_children=true. Revalidate the real writer's duplicate identity invariant in the read facts, including original chains, before gateway consumers may use attribution facts.

Actual counterexample: independent_actual_facts_reject_duplicate_original_identity_across_children returns Ok with two children whose first OriginalRequestBinding request_id is identical. Again limited to synthetic storage-integrity faults, with no execution permit or outbound action.

## Reproduction/evidence

Standalone runnable project /tmp/mig20-canonical-independent-review; run with the environment in PLAN and cargo test --offline --manifest-path /tmp/mig20-canonical-independent-review/Cargo.toml independent_ -- --nocapture. Full initial output evidence/independent-initial-three-RED.log (EXIT101; 0 pass/3 fail). Saved initial source evidence/independent-initial-harness.rs, manifest evidence/independent-initial-Cargo.toml, appended test/helper excerpt evidence/independent-extra-tests.rs; source fingerprints evidence/independent-initial-source-sha256.txt. Do not overwrite original failure evidence. Source rules are unchanged by this reviewer.

The request_binding implementation genuinely rereads actual persisted payload and recomputes SHA256; the new facts genuinely query the actual ledger and Owner chains. No caller JSON constructs these opaque facts, and execution_authority/cross_owner_atomic remain false. These are real interfaces, not fabricated placeholders. Further review and frozen-source verification remain pending with the parent implementer.


## Continued review — first three repaired; pending-original Handoff gap found

Independently reran the ORIGINAL three test functions without altering their assertions. All **3/3 pass** against revised sources: canonical run UI read succeeds; physically hidden child returns workflow_storage_invalid; duplicate original/conversation returns workflow_remote_binding_invalid. See evidence/independent-original-three-GREEN.log. The original three-RED log remains preserved.

New P2: Handoff still crosses a known unresolved original after failed canonical association. Using the current real CanonicalFixture: confirm/claim synthetic bytes without sending -> actual Owner Unknown; AFTER INSERT mapping fault forces BindCanonical rollback/PendingOriginal, leaving the node unbound; group_next_pending correctly returns LookupOriginal. However a normally granted Handoff command at the unchanged group revision3/epoch1 commits, increases coordinator epoch to2, and consumes a handoff while that exact pending canonical request remains Unknown. Handoff checks the root conversation and already-bound nodes, but not the exact pending canonical original now known from the journal. Only fixing advice does not maintain the existing mutation checkpoint invariant.

Actual RED: evidence/independent-pending-handoff-RED.log (EXIT101, 0 pass/1 fail), output PENDING_CANONICAL_UNKNOWN_HANDOFF=Committed and EPOCH=2. Source evidence/independent-pending-handoff-harness.rs plus independent-pending-handoff-extra.rs; runnable target late_review in /tmp/mig20-canonical-independent-review. The test uses the real original Owner hold/Unknown and an actual local grant, without provider/network calls or editing original Unknown. Suggested fix: before Handoff mutates anything, reconcile actual chains from exact pending canonical journal commands too; positively nonterminal original refuses Unknown, inconclusive lookup remains Storage/Pending; preserve identity/hold and never replay. Final frozen-source disposition remains pending.


The pending-original Handoff counterexample was also extended to TWO actual pending canonical associations. Lexicographically first original was positively settled via a valid synthetic Owner response to completed; the second actual original remained Unknown. Handoff again committed/epoch2 before the repair. This control ensures a fix must inspect ALL pending actual chains rather than only the first ID used for read advice. Original completion evidence: evidence/independent-all-pending-handoff-original-RED.log (captured from the first exec completion before code repair); extra source/harness: evidence/independent-all-pending-handoff-extra.rs and independent-all-pending-handoff-harness.rs. No provider send occurs.


## Continued pending-original checkpoint review — missing source must stay inconclusive

After adding all-pending-chain checks, both previous independent Handoff tests pass unmodified: the Unknown checkpoint returns local Rejected(error unknown) and keeps epoch1, including when lexicographically first pending chain is terminal and the second is Unknown. However, a related missing-source variant still reproduces: after the actual Unknown and failed local mapping, delete only its durable original-command metadata row. group_pending_canonical_originals treats group_original_command Unknown as continue, discarding the pending evidence. Advice becomes PendingHostAdmission and Handoff commits even though the actual original remains Unknown. Loss of identity proof must remain inconclusive; it cannot prove no pending original exists. This does not ask the implementation to fabricate the missing identity, and legacy missing commands must remain conservatively unknown too.

Actual output: MISSING_PENDING_IDENTITY_ADVICE=Ok(PendingHostAdmission), MISSING_PENDING_IDENTITY_HANDOFF=Committed. RED log evidence/independent-missing-pending-identity-RED.log (EXIT101). Test/harness evidence/independent-missing-pending-identity-extra.rs and independent-missing-pending-identity-harness.rs. Current new code under test is explicitly not frozen/final-approved yet. No production/native tests were changed by reviewer.


## Frozen-review additional P2 — checked source Plan provenance is not covered by the final tail

All SIX prior independent test functions now pass unmodified (original UI/physical-root/duplicate cases plus single/all/missing pending). Missing identity advice now returns Storage and Handoff returns PendingOriginal; known actual Unknown correctly refuses Handoff without advancing epoch.

The frozen-source review found a new same-BusinessStore provenance tail gap. New verify_node_plan/committed_command proves the actual historical local Plan's original command, receipt and event before writing a canonical mapping. But canonical final witness only compares mapping/node/run, not this checked source provenance. Install an AFTER INSERT group_request_bindings trigger deleting only the Plan event canonical-node: BindCanonical returns Committed revision4, and its immediate group_request_binding read returns Unknown because the required source Plan proof was erased within that same transaction.

This is not a cross-Owner/Ledger atomicity demand and does not involve network or changing an original Owner outcome. It is the existing SQL-trigger fault model applied to an actual same-database source now required by the new mapping reader. Final consumer-tail proof should recheck mapping's source provenance too (or retain exact expected source rows), map damage to Storage/PendingOriginal and roll back all local writes. Otherwise the command promises a committed verifiable association that its own transaction made unverifiable.

Repro: evidence/independent-source-plan-tail-extra.rs and independent-source-plan-tail-harness.rs; runnable late_review target independent_canonical_tail_preserves_the_actual_source_plan_provenance. Original output evidence/independent-source-plan-tail-RED.log (EXIT101, 0pass/1fail): CANONICAL_SOURCE_PLAN_TAIL=Committed and REREAD=Err(Unknown). Final approval remains held for this actual finding, not an environmental/permission block. Reviewer still edits only this task evidence/report and /tmp harnesses.


## Final independent re-review — all reported counterexamples pass

Final bounded review of the canonical-binding slice is complete. No remaining important defect identified in the reviewed frozen sources. This establishes the local association/read/recovery behavior only; it grants no Gateway/FFI dispatch permission and makes no cross-owner atomicity assertion.

### Actual independent execution

`evidence/independent-final-seven-counterexamples-GREEN.log`: EXIT0, **7/7 independent counterexample functions pass**, split across the original review target3 and late_review target4. Original assertions were NOT weakened. The entire initial /tmp review.rs remains byte-identical to the saved initial evidence (SHA256 `4ec75a35aa6deb505e89f567032a9ca777e432458f0e5f163468403b25cec746`). The current late-review.rs retains the earlier saved handoff/missing-identity harnesses as byte-identical prefixes and only appends controls (final SHA256 `9e4d248b5b842be6afc58c02721cbee86e1b8857e1891aa1c1f3de7acf3e6158`, copy `evidence/independent-final-late-harness.rs`). Original RED files are retained separately and have not been overwritten.

Exact command (with PATH/CARGO_HOME/CARGO_TARGET_DIR/RUSTFLAGS as specified in PLAN):
`cargo test --offline --manifest-path /tmp/mig20-canonical-independent-review/Cargo.toml --test review --test late_review independent_ -- --nocapture`

Confirmed outputs: actual canonical run UI read succeeds with Unknown usage remaining null; physically hidden and duplicate original rows fail closed; single and multiple pending actual Unknown chains refuse Handoff with unchanged epoch; missing original-command identity returns Storage for advice and PendingOriginal for Handoff; damaged source Plan provenance returns PendingOriginal and the local association is rolled back.

`evidence/independent-final-native-regression.log`: EXIT0, dedicated **group_request_binding40/40**, existing **group_runtime_bridge53/53**, existing **group_runtime_store65/65** pass. These are **158 native test executions**, not 158 newly authored tests. The dedicated40 comprises22 dedicated functions plus18 imported source tests. Original source-imported duplicates remain included in existing53/65 as before. Current native tests also cover physical scope damage, configuration replacement, real Unknown/holds after restart, no-context refusal, another actual root with same digest, receipt provenance, capability tampering, mapping/node/run effect-tail faults, missing metadata, all8 lifetime children after display event pruning, and owner-chain-read failure staying Pending.

Exact native command:
`cargo test --offline -p muyon-core --test group_request_binding --test group_runtime_bridge --test group_runtime_store` from crates/.

`git diff --check` passes. Clippy is **NOT_RUN** because the tool is unavailable (no installation performed); parent full-core/fixed-document/remote combination runs are not claimed as this reviewer's independent executions. Prior historical test totals are not counted as new coverage.

### Source review conclusions

- AgentOwner.request_binding reads the actual stored request row, validates request identity, and recomputes SHA256 over its actual canonical payload bytes. Opaque bindings cannot be deserialized or constructed from caller plans. It does not expose raw payload/credentials or add claim/dispatch permissions.
- Typed RunLedger facts scan physical rows before filtering the requested root, compare actual indexes and record context, reject duplicate remote conversations/request references, then bind actual Owner chains and private epoch/session context. The lifetime rows and active counts come from real records, with root excluded and display events irrelevant. Current configuration is separately read from actual Owner configuration; historical canonical identity remains readable while stale context is false.
- BindCanonical uses actual native owner/ledger/scope, the actual node's committed Plan provenance and exact canonical digest; mappings are unique by node/original/workflow child and cannot replace an existing association. The existing local grant/CAS/pending journal/receipt/event/consume machinery remains the sole mutation path.
- The mapping witness is captured before its first trigger-capable write. It now freezes the checked source Plan's full journal7 columns, command binding2 columns and event4 columns as their original bytes/NULLs. After exact grant consumption, the same transaction compares that source witness plus exact mapping/node/run/group records and current command receipt/event/grant. Only reads then commit. A missing/rewritten source returns Storage, drops the transaction and retains PendingOriginal; it cannot commit an immediately unverifiable association.
- Handoff checks ALL exact pending canonical originals, not just the first read advice ID. Actual nonterminal chains refuse Unknown; failed chain reads and missing command metadata remain inconclusive Storage/PendingOriginal. Bound-node and root-conversation legacy checks remain in place. No advice or local mapping claims, refunds, cancels or resends an original request.
- Existing UI original lookup uses the verified canonical child conversation while retaining conservative legacy root-conversation checks. Unknown cost remains null; workspace accounting is not fabricated into root accounting. execution_authority and cross_owner_atomic remain false.

### Frozen sources and disposition

Full hashes for owner.rs, workflow.rs, store.rs, binding.rs, bridge.rs and the three native test sources are saved in `evidence/independent-final-source-sha256.txt`. Final reviewed binding.rs SHA256: `da5814f087ff30a185e7aeffc784ed32177b86782711e102bb0f418000f7298e`; store.rs: `a0d80c3cf27761dab591c86c1e594197769ce5d8992cd183070a6d5691e16c18`.

All independently reported defects in this slice are remediated under the reviewed source fingerprints. No denied, pending or uncertain action and no remaining review blocker. Reviewer did not edit production or native test files. Gateway/FFI integration and cross-owner commit remain explicit owner boundaries, not permissions supplied by this review.

Parent separately reports final full-core346 executions PASS, fixed B863ece composition87/100/112 (299 executions) PASS, fmt/diff PASS, and clippy original exit101 retained as NOT_RUN/unavailable. These are recorded as parent-provided evidence, not additional independent executions. All eight final source/test fingerprints were independently rechecked unchanged after that report.
