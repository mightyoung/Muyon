# Combination validation — intermediate, HOLD

Branch lab/overall-combination-20261022. Locked sources and path-scoped deltas are in MATRIX.md. No main/develop merge, deployment, credential/payment action, real model/search or Office engine has been executed. Validation runs only disposable synthetic product stores; no original unknown/reservation was modified.

## Actual execution

- Rust 1.93.1: `cargo test --offline --locked --manifest-path crates/Cargo.toml --workspace --all-targets --no-run` PASS at e517f07f (source-equivalent Rust to 420baee1). All real product/FFI test targets compile; this is not a behavior PASS.
- Full core test attempt at e517f07f FAIL101: 42 lib, 18 business-worker, 3 child-tools, 11 owner, 6 product, 7 tools, 16 workflow, 13 archive and 8 blobs pass, then Bot provider 1 pass/14 fail. Later test binaries were not reached in this command. Counts describe individual targets, not extra independent totals.
- Provider7ca2 blocker: record SQL projects new `archive_hex IS NULL` through `CASE WHEN LENGTH(archive_hex)<=65536 THEN archive_hex ELSE 'oversize' END`. SQLite returns oversize for NULL, while archive_digest is NULL; record validation rejects the new draft as local_draft_corrupt. A direct SQLite NULL-expression check reproduced oversize. Parent and original provider owner are already fixing this. Do not enable host production save or treat its earlier SQL smoke as provider behavior verification.
- Python document_fidelity fake harness: 60 PASS. Actual engines remain HOLD.
- Android product Python checkers: 17 PASS; static checkers are not Android compilation.
- Pure JVM offline checks: Bot editing/codec17 PASS; chat projection and local setup PASS; persistence restart/process-CAS/faults PASS; reader state/sidecar/native text PASS. These synthetic checks do not establish Android PFD/intent/device behavior.
- Shell JVM runner initially FAIL because its explicit source list omitted new SetupDraftArchive.kt. Integration-only runner fix420baee1 includes it; real controller and request-candidate checks PASS afterwards. Both failure and passing logs retained.
- Android wrapper test/build/lint/device invocation exit2 before Gradle starts: existing Gradle/SDK unavailable, NOT_RUN. No installation or alternate environment bypass of the prior SDK restriction.
- New artifact53badad9 workflow15 PASS in actual Rust at 043051b7. Parent Important HOLD remains: final receipt write lacks output/source/historical policy recheck. Passing existing tests do not verify that missing case. Source is present solely for combination diagnosis; owner correction required before acceptance.

Independent core target run PASS: engine_protocol6, gateway19, transactions28, document_storage15, documents18, evidence_local15, group_governance21, group_runtime20, research16, resource_boundaries3, store_admission3. These targets fill coverage not reached by the stopped full-core command; they are not a full-workspace green result. Core's initial42 unit tests already included all eight new historical/Text tests and old artifact6.

Actual FFI lib at043051b7: FAIL101, 13 PASS/1 FAIL, new local_draft_bridge test fails at first resolve with local_draft_corrupt. Existing FFI tests passing do not establish new draft bridge availability.

Strict workspace/all-target Clippy at043051b7 FAIL101: production bot_drafts.rs:83 manual_is_multiple_of; document_edit/gateway.rs:91 manual_is_multiple_of and :357 useless_conversion. Artifact test source produces42 cloned_ref_to_slice_refs diagnostics. Compiler reports3 errors for lib and45 for lib-test (shared three are not additional unique findings). These source-owner fixes remain pending; no suppression or owner business edit was made. Initial offline missing-dependency failure is preserved; locked dependencies were subsequently fetched, same Cargo.lock retained. Tool preparation used task-local /tmp paths. Reader parent verification08e77d05 is supporting pure-JVM evidence only, not Android acceptance.

## Open owner/interface gaps

Provider NULL projection correction; artifact post-receipt authorization correction; evidence Text/historical-source update; real host stable conversation identity/registry/FFI and PFD/annotation-intent wiring; durable group owner. Existing host can_save=false remains correct. No guessed grant, fake owner, second driver, engine bypass or missing consumer implementation has been introduced.

This is an intermediate validation record, not release/develop approval. Final accepted fixed sources, final runs and independent review must supersede this record explicitly.
