# Core reading policy implementation contract

Authoritative inputs: Host660f03da29d26d6cdcf28c594c959cc6c43098e4 NATIVE-READER-POLICY-V1.md + NATIVE-READER-POLICY-REVIEW.md + REVIEW.md; FFI1cf16e10f6d655e0dafbc9d0b31776368af69252 CORE-READER-POLICY-ATOMIC-REQUEST.md. Read completely. This contract is not a generated ABI or completed feature.

Isolated branch task/document-reader-policy-20261022, source basea961bb58c08ce77b559ce0d021d2ed50a857bb9e plus exact approved purefmt0fda32e4 (local2ec63258). The invalidation branch separately recovered purefmt ase767e520d746d5660ce834884bb65a193286c450; its independent evidencebe769c9c remains distinct from this new reader policy.

Core owns documents::reading_policy, native policy SQLite records on the EXISTING BusinessStore, transaction-owned root/grant/CAS/attempt/outcome policy and native challenge/token lifetimes, plus narrow DocumentReaderHost helpers and existing grant/head mutation fencing. No second store, caller paths or generic public transaction authority. FFI retains BState/lib/wire/API/selection registry/presentation ID mappings. Host owns genuine Looper observation, Binder/current Runtime scope, D->G->drain serialization and OS/PFD cleanup. Core never asserts physical visibility.

Public facade names match the FFI request:

```rust
ReadingPolicyHost::open(reader: &mut DocumentReaderHost) -> PolicyResult<Self>
observe(&mut self, reader, &PolicyObserveRequest) -> PolicyResult<PolicyObservation>
begin(&mut self, reader, &PolicyBeginRequest, &PresentationTicket, &Revision)
    -> PolicyResult<OriginalPolicyOutcome>
prepare(&mut self, reader, &PolicyPrepareRequest) -> PolicyResult<PreparedPolicyOutcome>
renew(&mut self, reader, &PolicyRenewRequest) -> PolicyResult<OriginalPolicyOutcome>
reconcile(&mut self, reader, &PolicyReconcileRequest) -> PolicyResult<OriginalPolicyOutcome>
stop(&mut self, reader, &PolicyStopRequest) -> PolicyResult<OriginalPolicyOutcome>
continue_presentation(&mut self, reader, &PolicyContinueRequest) -> PolicyResult<PolicyContinuation>
selection_changed(&mut self, reader, &PolicyScope, &Revision) -> PolicyResult<()>
frame_advanced(&mut self, reader, &PresentationTicket, &PresentationTicket) -> PolicyResult<()>
```

All facade records live in documents::reading_policy; no root lib edit. PolicyScope = {service_session:String, generation:Revision, project:String}; derived workspace/epoch NEVER appear as caller inputs. ReadingSurfaceBinding = {surface_id:String, lifecycle_epoch:String, selection_sequence:Revision}; lifecycle_epoch is bounded opaque correlation text, not a claimed elapsed clock. FFI/Host map their genuine typed original value before generation. Requests contain exactly the semantic fields in HostA..G and the actual input request fields documented by FFI. PolicyContinueRequest additionally takes FFI's preallocated NEW presentation_id correlation as requested. Root/source/access remains exact existing DocumentRef and DocumentAccess, not a new permission type. Core counter values stay Revision; trusted expiry math uses native time.

Core returns actual grant observation classifications, original outcomes and genuine PresentationInfo only from an actual handoff. Historical reconcile never returns an apparently-live ticket. ID tokens are native-generated, bounded, one-use, <=2000ms monotonic freshness. Begin is possible ONLY after real initial Render presentation + valid existing persisted parent grant. Selection hook must run synchronously before FFI publishes a new selection token; frame hook before its response. Late roots cannot reach destructive open/close. Natural expiration permits only established-root first child generation1 / own-child.next() with new original observation. Parent is never reissued/narrowed; root stop revokes own child only. Generic parent/child reissue/revoke and head/source mutations terminal-fence roots in their original transaction.

Persistent bounded roots/attempts/original receipts share the BusinessStore transaction with child issuance and root CAS; startup invalidates old owner-instance roots and tokens while retaining historical outcomes. Limit16 root records/256 attempt records, bounded persisted JSON before materialization; reserved root stop space cannot be refused because new-admission quota is full. No eviction that resurrects original IDs. An explicit conservative capacity exhaustion remains unavailable until a separately reviewed retention strategy. This is a policy-ledger bound, not a total store/disk quota.

G uses a new genuine Core handoff, never a replayed selection token or old lease extension. Preflight validates exact predecessor/root/current selection/new valid child/source before destructive actions; a bounded authenticated fresh source snapshot is explicitly opened rather than promising snapshot transfer. Original cleanup failure retains pins/budget/poison. SQL child commit and Reader/PFD transfer are not atomic: durable handoff reservation and completed/failed/unknown outcomes remain distinct. Original reconciliation fences unperformed work, never silently retries issue or handoff.

First or daily re-open without valid initial grant remains unapproved and denied. Background/route exit/stop roots never revive just because a parent expired or a child existed. No generic issuer+cached allow continuation. Existing Reader/raw/presentation contracts retain their behavior. No actual model/search/engine, credentials, external sends or user file operations. New policy exports/Android acceptance remain gated pending actual tests and owner integration.
