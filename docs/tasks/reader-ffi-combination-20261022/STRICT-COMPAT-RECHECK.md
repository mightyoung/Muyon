# Conditional candidate hook lint compatibility

Fixed source: 471a5d34bbaf12963f0f50be536fddf90f96571b. Applied owner
7557cc9fcecfac92cbec1371ce47112c413729ee exactly: seven attribute lines only.
The non-test, single-function expect(dead_code) explicitly documents the retained
publication seam awaiting a reviewed production caller. This is an intentional
conditional lint exception, not a production caller or publication implementation.
Function body, signature and tests are unchanged; publication still refuses.
Independent fixed-SHA read-only review confirmed this scope.

Actual Rust 1.93.1 offline locked checks on this source:

- Candidate integration target: PASS, 12/12, exit 0; actual repeated checks of
  the existing candidate tests, not additional unique acceptance cases. Worker
  unused reexport warning remains in this cargo-test build.
- Workspace library strict Clippy: PASS, exit 0, includes core and Android FFI.
- Workspace/all-target strict Clippy: FAIL, exit 101. Original candidate.rs:297
  dead-code blocker is cleared; newly exposed clippy::drop_non_drop at
  crates/muyon-core/tests/document_edit_candidates.rs:175, :200, :240, each drop(g).
  These belong to the new candidate tests, not the prior five-drop gateway fix.
  Owner correction is needed; no local business/test rewrite or broad allow added.

Earlier 639 successful workspace executions apply to db40/85cac Rust source.
This seven-line attribute patch does not justify recounting or relabeling them as
new tests. Native FFI three-file fmt failure and Android NOT_RUN remain unchanged.
Existing save-method ABI-specific too_many_arguments exception remains disclosed.
