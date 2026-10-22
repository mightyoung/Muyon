# Held adapter source handoff to parent / Rust document_edit author / Leader B

Task branch task/document-fidelity-harness-20261022, continuation base7037166d4f1154ebbb38bdaea158b6ac4f8b544a.

New implementation commits:

- d023a616eaa7cf787be4041a939df08f53254c01 — strict neutral request/inert engine spec, hard-held real entry, dormant openpyxl candidate worker source, independent XLSX part/single-node oracle and fake executor tests; independently reviewed.
- d18636f7f1eb7a54f06b647eae14aa55d0da89d1 — single review-fix pass: preserve document-level comment/PI position and stable held response for malformed diagnostic admission; author43-test green and original independent probes rerun by author. Raw original/fixed evidence retained.
- This final sealing commit adds handoff/scope/remote evidence and completion ledger only; final tip is returned by execution response and checked against remote after normal push.

HOST-PROTOCOL.md is the proposed Rust-neutral boundary, REQUEST-EXAMPLE.json a bounded synthetic request. It is not wired into the Rust author's in-progress gateway/persistence/CAS. Host owns scope/authorization/read handles/revisions/operation identity/idempotency/durable candidates/CAS/receipts; adapter never emits committed/saved/synced. Directory ownership is tools/document_fidelity/adapters, its tests and task docs; no Rust/Android owner file changed.

43 author tests pass after fixes; independent review originally ran41 tests and six original fixture comparisons. No43-test independent rerun claimed. All accepted test candidates are explicitly simulated_validated/fake_executor_used=true/real_roundtrip=not_run; global safety/fidelity unknown, render/recalc/visual/annotation not_run. Fake callback limits are checked after return, no actual OS timeout cancellation or sandbox guarantee. No real subprocess executor shipped; run_real and worker entry cannot start the engine even with all-pass diagnostic flags.

Boundary decisions: real execution remains unconditionally held rather than introducing a caller-asserted admission escape; runtime integration cost is NOT_RUN. Malformed admission was treated as protocol correctness despite original P3 grade and fixed (no engine ever ran). Visibility covers worksheet state only: explicit hidden-row/column coordinates are possible; future host must disclose/restrict hidden targets before enabling execution. No deferred minor finding remains.

Unknown parts/member-set changes rejected; all bytes outside one target worksheet part invariant; only target numeric v text can change, retaining stale formula caches/other nodes. Candidate normalization that violates invariants is unsupported/failure, never a fidelity claim. Real openpyxl may fail this oracle; actual behavior untested. DOCX/PPTX/PDF/advanced XLSX follow stages documented in protocol, not declared completed.

Remaining blockers: existing bwrap UID-map readonly failure not retried; trusted isolation/artifact/license/resource attestation and process launcher/cancel/IO enforcement, real engine reopen/round-trip/render/recalc, Rust protocol mapping/persistence/CAS and UI owner integration. Prior Flutter-missing full-repository failure remains. No install/EULA/cost/credential/permission/config change, original user file, network/model/search/unknown retry, deploy/main/develop merge/force push/delete. Existing source fixtures unchanged; original workspace clean. Leader B alone merges develop.
