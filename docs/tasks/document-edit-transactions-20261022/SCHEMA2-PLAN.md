# Held schema2 mapping and edited candidate preparation implementation plan

> Agentic execution: native inline TDD, independent review before push, as delegated.

Goal: map narrow DOCX/PPTX host-observed run targets exactly and persist unvalidated
non-original candidate preparation without enabling engines or publication.
Spec: EDITED-CANDIDATE-INTERFACE.md + upstream6b796c8 PROTOCOL-v2.md.
Tech: existing Rust/serde/sha2/BusinessStore SQLite; no added packages or parsers.

Files: document_edit/fingerprint.rs (expanded tree canonicalization only),
engine_protocol.rs (version/policy/full identity binding), text_protocol.rs (typed
locators and held envelopes), edited_candidates.rs (separate same-store journal),
mod.rs module declarations, own integration tests, this task docs/evidence only.

Review focus: Unicode/surrogate ASCII spelling and null vs empty; duplicate expanded
attribute; real format and locator/hash mismatch; expired/legacy policy confirmation;
late grant revocation and crash after preparation claim. All receive named tests.

1. Write cross-language golden serialization/hash tests from original stdlib XML
   synthetic trees (sorted attrs, null/empty, comments/PIs, Unicode/non-BMP/control
   JSON escaping); run missing-API RED; implement bounded typed expanded tree form
   with Python ensure_ascii=true semantics; compare raw bytes+hash to Python reference.
2. Write schema2 DOCX/PPTX format/identity/full operation/locator/target-run binding
   tests and invalid text/index/path tests; watch RED; implement held mapping only.
   Version2 matching responses still HOLD, fake/unknown reject; schema1 digest gains
   tightened eligibility policy epoch, old prepared plans cannot be reused.
3. Write real local synthetic SQL lifecycle tests: prepare/reopen, no confirmation,
   exact confirm, staged different bytes unvalidated, unknown without replay, same
   intent/revision conflicts, revoked tail, candidate tamper, cancel not rollback,
   no fake validation/publication. Watch RED, implement bounded separate journal.
4. Run offline exact-core combination suites/full core, own fmt; preserve failures.
   Independent reviewer checks code+goldens+durable negative probes, fix TDD if needed.
5. Commit/push original task branch only; record exact SHA/dependency/commands and
   unmet core pin/publication API in report. Never claim actual Office editing.
