# Independent BusinessStore persistence review

Scope: new `group_runtime/store.rs`, its same-crate source harness, and task plan. Review is read-only for production files. Only temporary synthetic databases and offline actual BusinessStore/AgentOwner APIs were used; no network, original user requests, real model execution, user documents, commits or pushes.

## IR-S01 — stop can permanently prevent registration of an already-existing original request (P2, repaired; independent recheck passed)

The reviewed original `BindOriginal` rejected a closed run at `store.rs:758` and required `pending_host_admission` at lines 764–766, while Stop replaced unbound proposals with a cancellation state. Sequence: plan; real offline original request reaches Unknown; Stop commits before binding; binding is Rejected and group original lookup cannot recover the reference. This is a real cross-owner ordering window because the group and AgentOwner databases are not one transaction. A local stop must not prevent read-only registration/reconciliation of an original request which already exists. The revised candidate permits query-only original registration after stop/deadline and preserves the stopped run. Independent test `independent_original_binding_remains_possible_after_stop` now passes.

## IR-S02 — handoff can permanently consume active slots with already-terminal originals (P2, repaired; independent recheck passed)

The reviewed `group_next_pending` counted cached nonterminal node states (`store.rs:527–535`) after live original queries proved their requests terminal. Handoff checked the receipts but did not refresh cached bound nodes (`store.rs:836–851`). Observe then refused old-epoch nodes (`store.rs:794–795`). Reproduction: bind two Unknown requests, settle each via the real owner, hand off before Observe, and create an epoch-2 proposal. The run permanently returned None because both epoch-1 nodes still counted active, and they could no longer be refreshed. The revised candidate refreshes bound nodes from live original receipts during handoff, removes the stale active count, and permits old-epoch reconciliation. Independent test `independent_handoff_does_not_permanently_leak_terminal_active_slots` now passes, including old-node Observe.

## IR-S03 — a completed real tool chain is permanently treated as unresolved (P2, repaired; independent recheck passed)

`terminal` recognizes only completed/failed/cancelled, but the real AgentOwner sets a consumed tool-calling request to `tool_consumed` and stores its followup edge in `tool_steps`; its real terminal result belongs to the followup request. Looking up only the bound first request makes group advice return LookupOriginal forever after the entire chain has completed, while Handoff also refuses it. This was reproduced with real prepare_chat, bind_tool_scope_trusted, confirm, claim, synthetic tool-call settlement, review_tool_read, approve_tool_read_trusted, prepare_tool_followup_trusted, followup confirm/claim/settle, and ensure_conversation_resolved. The final owner conversation is resolved and the followup is completed, but group advice still holds.

Recommended repair: follow only the owner's durable `request_chain`, validate every conversation identity, retain the bound root identity for attribution, and derive result/hold from the real chain tail. An unresolved followup must still direct lookup to its actual request ID. Merely classifying tool_consumed as terminal would allow unresolved followups through and is insufficient.

## Evidence and verification

Independent temporary crate: `/tmp/mig20-independent-store`; its manifest imports the real repository modules and existing dependency packages. Historical reproduction snapshots are archived under `evidence/independent-store-reproduction.rs` and `evidence/independent-store-tool-chain-reproduction.rs`, with the manifest `independent-store-reproduction-Cargo.toml`. These snapshots include the repository tests present when copied and do **not** represent the final author suite. Their absolute production paths read the current implementation when rebuilt.

- Initial independent author-suite execution at the concurrent 32-test candidate: **30 passed, 2 failed**, exactly the author's already-known missing-owner handoff and NULL-versus-empty-string defects. These are not additional independent findings.
- Historical independent IR-S01/IR-S02 RED: **0 passed, 2 failed, exit 101**, preserved byte-for-byte command stdout/stderr in `evidence/independent-store-red.log`.
- Historical independent IR-S03 RED: **0 passed, 1 failed, exit 101**, preserved in `evidence/independent-store-tool-chain-red.log`.
- Latest independent three-counterexample recheck: **2 passed, 1 failed**, IR-S01/IR-S02 repaired; IR-S03 still open at this report version.

Trusted host grant issuance remains a host-only authentication boundary and was not treated as model-accessible. Missing canonical payload/RunLedger binding and cross-database gateway CAS remain declared owner integration limitations; this report does not invent a second grant, accounting ledger or dispatch authority. No additional authorization bypass was confirmed within that declared boundary.

## Repair recheck supplement

IR-S03 is repaired in the current candidate. The original request view follows only the existing owner's persisted request_chain, preserves the bound root ID in original_request_id, exposes the real tail in current, and retains the real observations in chain. The independent tool-chain case was strengthened to check prepared-followup and Unknown-followup holds, lookup of the real followup ID, original root attribution, two-element chain, and release after final completion. All three independent counterexamples now pass: **3 passed, 0 failed, exit 0**, recorded with full stdout/stderr in `evidence/independent-store-green.log`. The strengthened current reproduction source is archived separately as `evidence/independent-store-final-reproduction.rs`; original historical RED source/output remain unchanged.

The concurrently evolving author suite reached 35 tests during an independent rerun: **34 passed, 1 failed, exit 101**. Its only failure was the author's newly added `a_new_run_id_cannot_reset_the_same_registered_root_lifetime`; complete output is preserved in `evidence/independent-final-store.log`. This is an intermediate RED candidate, not final-suite approval. The implementation owner is addressing this additional lifetime-boundary regression separately.

## Final frozen-candidate verification

Independently rebuilt and reran the owner's frozen store harness: **35 passed, 0 failed, exit 0**. This consists of **17 dedicated group-store tests plus 18 tests included from the existing source modules**. Complete command/stdout/stderr/exit are in `evidence/independent-final-store-fixed.log`. The earlier 34/35 RED `evidence/independent-final-store.log` is preserved unchanged.

Independently rebuilt and reran all three enhanced counterexamples against the same candidate: **3 passed, 0 failed, exit 0**, recorded in `evidence/independent-store-final-green.log`. IR-S01, IR-S02 and IR-S03 are closed for this candidate. Prepared and Unknown tool followups still block and identify the real followup request; a fully completed chain releases the advisory hold. The new root-identity lifetime regression also passes in the 35-test harness.

The reviewer made no production-file changes. Only temporary reproduction files and this task's report/evidence were written. No remaining important defect was confirmed inside the declared trusted-host local-mutation boundary.

This result certifies the reviewed local persistence behavior only. Canonical binding between the actual host payload/member/grant revisions and the original request still needs the core owner's hook; the full RunLedger projection and the sole gateway's atomic authorization/cost/reserve/claim recheck still need host integration. BusinessStore and AgentOwner are separate connections and this slice does not supply a cross-database execution transaction. No external gateway, FFI export, network/provider execution, or real-model group parallelism is claimed by this review.

Reviewed candidate SHA-256 values:

- `crates/muyon-core/src/group_runtime/store.rs`: `ecf344bfb6272185b8494b5b82676b28a6f3eb604499c1ca5afbd3b457f41e2d`
- `crates/muyon-core/tests/group_runtime_store.rs`: `369da0b2f14f822edcfe4deec1542dc59410dea91a44ac81cdcec944724a5ae0`
