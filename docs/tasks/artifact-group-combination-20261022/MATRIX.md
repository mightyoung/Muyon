# Locked Artifact/Group isolated combination

Base a5acfba1 (Reader raw transfer/evidence plus three non-Drop deletions and
sealed FFI purefmt). Reader display lease is not included. No Host/UI/FFI/generated
binding changes in this piece. Source owners remain independent.

- Artifact 0e85c6e98c4e32efc8008092e480626f342a701d, source
  ba68de427633cd35122ea12505a4f9b6daa5e1f4. Read SOURCE-RESOLVER-HANDOFF.md.
  Import only artifacts/** complete owned delta from held de3ec5b. evidence_local
  test already exactly matches offered source and is not overwritten. Store,
  documents, evidence processor, exports and existing provider retained.
- Group 8e3a658feea7c463b8a22dbd320e4fb3f47cf7af, full owned delta from held
  68f0fb69: store.rs, new bridge.rs, store/bridge integration tests. Latest parent
  review accepts migration preservation; do not select superseded defect versions.
  Import exact single group_runtime_bridge module export and documents imports in
  both source harnesses, as offered patches specify. Existing modules once only.

Artifact per-operation live source checks and receipt-tail recheck are exercised
with the actual current Reader/evidence implementation. Notification hook remains
unwired to core/UI; Message unsupported; FFI/forms UI absent. Group local config,
recovery and v1 journal preservation do not enable canonical Agent execution,
new grants, RunLedger gateway, FFI or Host. No publication or verified enablement.
No main/develop merge, deployment, engine/network/model/credentials/fee, I04 or old
403 evidence download. Only new-schema synthetic offline tests are permitted.
