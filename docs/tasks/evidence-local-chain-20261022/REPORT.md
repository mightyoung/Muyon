# MIG16 / U01–04 U07–08 — offline processing delivery

Status: implementable offline evidence module delivered; production owner wiring
is pending, not claimed complete. Dedicated branch task/evidence-local-chain-20261022
starts at document-core f4a8e8d3971208f16d4a3b1ddff5d4e8fb2a63ac.

## Implemented

- Concrete bounded local UTF-8 extraction and literal excerpt matching, SHA-256
  and byte-length verification against current authorized core source; no
  filesystem imports, alternate document database or vector index.
- Stable source/version/receipt/evidence JSON structures using core DocumentRef,
  BlobRef and AuthorityBinding. Exact workspace/project/document/revision/blob
  binding prevents stale reference rebinding to a newer document.
- Exact UTF-8 byte anchors, quote digest and source identity revalidation;
  no invented PDF page or geometry. All derived text deliveries recheck permission
  and source before and after computation. Unknown/revoked access fails closed.
- Immutable body/citation/candidate projection with explicit selection and stable
  numbers within a projection; claim support remains unassessed and independent
  corroboration count unknown. Duplicate passages never inflate source count.
- Processing events reflect actual extraction outcomes. Malformed/empty/NUL text
  fails; PDF/OCR unsupported; semantic index not_run. A processing receipt is
  historical ephemeral metadata, never an import/save/commit/index completion.
- Redacted Debug prevents cached text disclosure after revocation.

## Requirement boundaries

U01: extraction/failed/unsupported real states implemented; selected/saved and
persistent index availability require existing owner records, not recreated here.
U02: scope isolation checked per use; no cross-project defaults or disclosure grant.
U03: revision-bound text excerpt resolution implemented; PDF page resolution remains
unsupported by this processor (existing core anchors are reusable by engine owner).
U04: concrete body/citation/candidate projection, separate unassessed support and
unknown independent corroboration. No automatic correctness/credibility badge.
U07: synchronous actual extraction events only, no invented queued/cancelled state
or new task runner. U08: deterministic processing identity, no business intent
retries, reservation mutations or unknown-operation resolution attempted.

## Verification

- Final dedicated suite: 15 passed, 0 failed (also contained in workspace-final.log).
- Independent reviewer: final dedicated suite 15 passed, 0 failed; no unresolved
  Critical/Important findings. Prior Debug leak reproduced then fixed; see REVIEW.md.
- Final locked/offline Rust workspace: 211 passed, 0 failed, 0 ignored, 21 result
  groups; exit 0. Existing documents/storage.rs dead-code warning retained.
- rustfmt limited to owned module/test; source/prose staged diff whitespace checked; raw logs retain tool whitespace.
- Initial NOT_RUN, compile failure, actual regression RED, unavailable offline
  dependency failure and successful reruns preserved in evidence/.
- Test-first limitation: tests existed before implementation but initial cargo
  execution was NOT_RUN. Do not claim a fully observed initial TDD RED cycle.
  The Debug regression did have an observed behavioral RED/GREEN cycle.

Tooling: repository CI specifies Rust 1.93.1. Official rustc/cargo/std/rustfmt
checksums verified before isolated /tmp installation. Fetches only used fixed
repository commits and pinned repository build dependencies; no model/search
request or user real-file processing. Existing system SQLite runtime reused
via temporary linker alias. No dependency versions or owner files changed.

## Remaining integration blockers

Pending (not denied): core owner must export evidence in lib.rs and settle Text
format; host owner must implement authoritative DocumentHost adapter and connect
controlled bytes plus existing persistent import/task/intent receipts. ReadText
cannot be inferred from read_document's Inspect-only check. See HANDOFF.md.

NOT_RUN: Android build/device, PDF extraction/OCR/engine geometry, real UI/host
integration and persistence recovery for the new processing projection. No engine
HOLD, original unknown/reservation, main/develop, deploy, payment configuration,
credential or security permission changes. Full native app completion is not
asserted by this bounded module delivery.
