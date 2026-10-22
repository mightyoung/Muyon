# Independent origin/request-only gate review — initial findings

Branch task/mig20-group-origin-gate-20261022, base d06541c3367308e69852bde98d1f60756a750338. This review is in progress; no final frozen-source approval yet. Reviewer edits only this task report/evidence and /tmp standalone fixtures. No provider/network/user files or historical/user Unknown were used. Tests locally prepare/claim/settle newly created synthetic requests without sending bytes.

## P2 — conversation damage drops actual bound request attribution into Direct

Given an ordinary-prepared Direct-origin request already bound to an actual group workflow child, mutate only that child's stored conversation_id. Its remote_request_id/current_request_id/remote_request_ids still explicitly refer to the actual request, and the original Owner canonical identity/conversation is unchanged. request_attribution initially selects rows only by conversation; no match falls through to a physical-index coherence check that ignores explicit request references and Owner chain/conversation mismatch. The gate returns group_hold=false, direct_non_group_observed, workflow=null. This violates the new source-damage HOLD rule. Select/validate actual request references/chain identity as well as conversation and fail closed on their mismatch.

Actual test independent_origin_gate_cannot_drop_a_bound_child_after_conversation_damage fails. Source/evidence: independent-initial-harness.rs, independent-initial-extra.rs and independent-first-two-RED.log (0pass2fail, EXIT101).

## P2 — missing group run is treated as positive nongroup

An actual group workflow child with a Direct-origin ordinary request initially has group_hold=true. Delete only the group_runtime_runs row (fixture has no node FK); real group registration, committed Start journal/command/event and actual workflow/Owner references remain intact. Gate scans only currently present group run rows, finds none, and returns group_hold=false/direct_non_group_observed. Absence of the row is not positive nongroup evidence when registration and actual original Start facts still show the group context. Use actual registration root-conversation and original committed/pending group association evidence conservatively; missing/damaged sources must HOLD. A related partial-namespace meta-table absence must not be confused with a group namespace never initialized.

Actual independent_origin_gate_cannot_downgrade_when_actual_group_run_row_is_missing fails in independent-first-two-RED.log. Both first two cases are synthetic persisted-integrity faults, not claims that model JSON can mutate SQL or that this gate currently grants execution_authority. Its explicit false permit does not excuse an incorrect group_hold routing classification.

## P2 — followup parent source witness is captured after its first trigger-capable write

OriginDraft::Followup captures parent request/tool_steps in write_origin, but prepare_record has already INSERTed the new requests row by then. A trigger on that INSERT can mutate the parent, and the mutated value is then trusted as the expected witness. Actual offline repro: real Group-origin request receives a synthetic tool-call response with exact recorded charge66, and local tool read is reviewed/approved. AFTER INSERT ON requests increments only that parent's charged field by1. prepare_tool_followup_trusted returns Ok with a new inherited Group-origin plan, changes parent to tool_consumed, and commits parent charged67. Full-tail verification accepts the post-write parent snapshot.

Freeze the actual parent request, steps and origin before the first new request write, then compare intended terminal transitions after all writes. This is one Owner database/transaction, not a cross-SQLite atomicity requirement. Original source bytes and accounting must roll back when damaged; no new origin/link may become durable.

Actual test independent_followup_insert_cannot_mutate_parent_before_the_source_witness_is_captured fails. Source independent-followup-source-extra.rs/harness.rs, log independent-followup-parent-source-RED.log (EXIT101). Logs contain only synthetic request data; no actual outbound call occurred.

## Reproduction

Standalone /tmp/mig20-origin-gate-independent-review uses real production source modules and copied current native fixture helpers. Use the environment specified in PLAN, then cargo test --offline --manifest-path /tmp/mig20-origin-gate-independent-review/Cargo.toml independent_ -- --nocapture. Original saved source and manifest are in evidence. Initial RED files are immutable; fixes will be verified with separate logs and the same assertions. Parent continues implementation and native tests; review final disposition is pending.


## Continued review — original three repaired; real legacy BindOriginal group association omitted

Parent repaired the three initial defects. Independent first followup re-execution after the repair already returned EXIT0; its log is independent-followup-parent-source-first-fix-GREEN.log. The actual original failed completion was from exec session88710, and its relevant failure/output excerpt is retained in independent-followup-parent-source-RED.log. It is explicitly an excerpt, not a falsely labelled later GREEN run. Original first two downgrade RED logs remain complete.

New P2 uses a NORMAL real API path, without any SQL damage: prepare a Direct-origin original in the registered group's root conversation; persist a real Plan node and grant-confirmed BindOriginal, which validates the actual Owner/root-conversation identity and commits. RunLedger has the group's actual root but no remote child. Request-only gate has no workflow attribution, and its new independent local-evidence reader currently only recognizes BindCanonical, so it returns group_hold=false/direct_non_group_observed despite a committed actual group BindOriginal association. Group node/original reference and/or exact original BindOriginal command evidence must also prevent nongroup classification, including a followup's root_request_id. This does not require reclassifying the historical origin as Group; HOLD is the honest classification.

Test independent_origin_gate_holds_actual_legacy_bind_original_without_a_workflow_child, source independent-legacy-root-original-extra.rs/harness.rs and output independent-legacy-root-original-RED.log (EXIT101). This is especially relevant to the existing legacy group path, which remains available and is not a caller-forged mapping. No provider request occurred. Final frozen-source disposition is still pending the implementer's repair and regressions.


## Final independent re-review — origin/gate slice verified

The four independently reported defects are fixed in the frozen sources: explicit workflow request references cannot disappear because conversation changed; absent group-run indexes do not erase registration/Start group evidence; followup parent witnesses are captured BEFORE the first new request INSERT; real legacy BindOriginal associations remain HOLD without a child/canonical map. Independently reported RED evidence is retained, including the explicitly identified first-followup tool-output excerpt and separate later GREEN capture.

### Actual independent executions

- `evidence/independent-final-five-GREEN.log`: **5/5** independent functions pass with original assertions unchanged. The fifth is an additional two-case control proving committed AND pending local canonical evidence stays HOLD when the actual workflow child disappears. Earlier saved initial/followup harnesses remain identical byte prefixes of the final appended harness. Final complete source is `evidence/independent-final-harness.rs`, SHA256 `9647e99487c9fbd1b334a729a6fd55d10b18b33a9ba397fb4166922755bb6e5e`; manifest is `evidence/independent-final-Cargo.toml`.
- `evidence/independent-final-origin-controls.log`: **19/19** current origin/gate functions pass, including actual first Group followup persistence/root mapping/restart, Direct ordinary workflow/followup controls, v3->4 legacy Unknown/hold preservation, five migration damage variants, atomic prepare/followup rollback, partial namespace remnants, and source/mapping damage staying HOLD.
- `evidence/independent-final-native-regression.log`: **214 native executions PASS** across agent_child_tools3, agent_owner11, agent_tools7, agent_workflow16, group_request_binding59, group_runtime_bridge53, group_runtime_store65. The19 focused origin cases are a repeated SUBSET of binding59, not additional distinct tests. Binding59 = prior40 (22 canonical +18 imported) +19 new origin/gate functions. Existing imported/fixture duplicate executions remain included; 214 is not new/unique coverage.

Exact commands use PATH=/tmp/mig20-rust/bin:$PATH, CARGO_HOME=/tmp/mig20-cargo, CARGO_TARGET_DIR=/tmp/mig20-target, RUSTFLAGS='-L native=/tmp/mig20-native-libs':

`cargo test --offline --manifest-path /tmp/mig20-origin-gate-independent-review/Cargo.toml independent_ -- --nocapture`

`cargo test --offline -p muyon-core --test group_request_binding group_origin_gate_cases:: -- --nocapture`

`cargo test --offline -p muyon-core --test group_request_binding --test group_runtime_bridge --test group_runtime_store --test agent_owner --test agent_tools --test agent_child_tools --test agent_workflow`

The last two run from crates/. All logs record exact commands and EXIT0. `git diff --check` also passes. Parent full-core/combination/fmt results are separate provided evidence and are NOT counted as this reviewer's independent execution. Clippy remains NOT_RUN (no installed cargo clippy; parent raw exit101 retained in final-clippy-arguments.log); no installation or lint suppression was performed.

### Confirmed scope and invariants

New actual Owner preparations atomically commit full canonical request and immutable Direct/Group origin in one Owner transaction. Group seed selectors come from real Store/RunLedger/native scope and the actual member; the serialized RequestOrigin has no public constructor or Deserialize. Generic Direct preparation rejects an already-known Group conversation before its first write. A followup freezes actual parent request/tool step/origin before its first write, inherits exact classification/root/group fields, and records the durable parent edge in the same existing transaction. Final tail proves the intended full new request/origin and exact permitted parent status/link transition; damage rolls everything back. No reads are presented as a cross-owner commit lease.

Migration3->4 captures full old requests/configuration/tool_steps before writes, creates one legacy_unknown per existing request, and verifies old bytes/NULLs plus complete expected origins/version/DDL before commit. It does not guess Direct, rewrite outcomes or free holds. The legacy real Unknown fixture and migration-fault rollback controls pass.

Request attribution selects by actual canonical conversation AND actual stored request/root references, then validates actual ledger facts/Owner chains. Gate independently checks actual Store registration, node/canonical references and original BindOriginal/BindCanonical journal evidence before treating attribution absence as nongroup. Original Start/registration evidence survives missing run/child indexes. All nine owned namespace table names participate in partial-state detection, including lone nodes/events/binding-schema remnants. Pending missing identity or source errors remain HOLD. A missing canonical map is never evidence for Direct. These reads do not create account, request, attempt, reservation, claim or replay.

### Explicit existing limitation — second full tool followup is NOT implemented here

Only the FIRST actual tool followup has been proven to prepare/persist, inherit Group root, survive restart and resolve first-original mapping. The existing encoder rejects a second full preparation with tool_history_invalid before any new origin write. The active native case `second_followup_encoder_refusal_preserves_existing_group_chain_and_hold` verifies that rejection is preserved, prior chain stays unchanged, and the existing followup keeps HOLD; it does NOT establish a second successful followup. Parent original failing run14 and original attempted test source remain in evidence. The19-case GREEN is not a claim to fix or bypass that pre-existing encoder limitation.

### Final disposition and source fingerprints

`evidence/independent-final-source-sha256.txt` contains eight affected production/test hashes; all were rechecked unchanged and match parent final-manifest.json. Key frozen hashes: origin.rs `5f8ee59ce9ac5aed70ba5c887850151cb53bdf9d2dded06ddb035cf868313099`; gate.rs `bdfb7bb344573f9a5fc7e816b1f43c335a74cda292856a3dea450fa461a9d3eb`.

No remaining important defect identified in this bounded origin/read-gate patch. All reported defects are remediated; there is no denied/pending/uncertain review action. The second-followup encoder limit is an explicit existing functional limitation, not silently claimed as completed. Group/legacy/inconclusive paths remain HOLD; Direct-nongroup is only a routing observation, never permission. Cross-owner claim/budget/attempt atomicity and FFI/host/gateway consumption are still unclosed and no new permit is supplied. Reviewer modified only this task report/evidence and /tmp harnesses.
