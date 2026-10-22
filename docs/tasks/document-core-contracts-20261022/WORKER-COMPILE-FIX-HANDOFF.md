# Standalone worker document policy dependency repair

Fixed source: `cab23b69b2aa56f55f3b44e0fe248f026da9c08d`.
Behavioral fix: `3cf2b3ec58b437196d0682e153fcf8c56e5f685e`.
Base: `8802bf555bfce1265296318d83a2f8a1fb2b787e`.

## Original actual failure and correction

Read immutable independent evidence `263dfe4067612ba0206afa5ba4ad77dcf2d59744`,
CANDIDATE-RUST-VERIFICATION.md and full-core stderr. On base 8802 the independent
Rust environment actually passed candidate13, history8 and the individually
selected pagination1/Text1; the latter two overlap the suites and are not added.
Full package compilation failed with E0599/exit101 before executing its tests.
Scoped formatting failed for six files. These original failures are not rewritten.
The full original stderr is copied byte-for-byte into
`candidate-evidence/09-original-core-full.stderr.log`; its hash and immutable
origin are in `10-worker-fixed-source.log`.

`src/bin/business_worker.rs` independently includes product source through path
modules so its fault harness can access crate-private transaction seams. It
included blobs but omitted documents, whose candidate module implements the
real `document_candidate_upload_retained` and `document_candidate_reserves_digest`
methods on that standalone BusinessStore type. The library already included
documents, explaining why library-only targeted tests compiled while the full
package failed for both worker and worker-test builds.

The correction includes the complete `../documents/mod.rs` owner module under the
existing harness pattern. It does not duplicate methods, add a permissive default,
disable candidate retention/GC or alter publication. All documents crate-root
dependencies (business, contract, sqlite, blobs) are already real worker modules.
The added module also includes its genuine cfg(test) tests in the worker-test
build, like other directly included source; any resulting per-binary duplicated
test counts must not be described as unique coverage.

## Exact formatting correction

The original validator's `format/expected-format.json` records 13 input/output
hashes and six required changes. We applied its original formatter diff to the
unchanged six source files; recursive duplicate hunks were deduplicated and the
printer's EOF blank context excluded. All 13 input and expected output SHA256
values were checked before writing any source. Exact output matches are recorded
in `candidate-evidence/08-format-diff-hash-check.json`.

This is byte equality to independently computed rustfmt output, not a claim that
rustfmt ran here. The worker addition was not among those 13 old files and must
be included in the new actual format check. No document_edit, FFI, Android or
other owner's files changed; main/develop remain untouched.

## Required fixed-source revalidation

`candidate-evidence/10-worker-fixed-source.log` records fresh attempts:

- `cargo check --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --bin business_worker`
- `cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core`
- `rustfmt --check --edition 2021` on worker, blobs and documents/mod.rs

All three are NOT_RUN (127: tools absent). `git diff --check` exited 0. There is no
new compile/test/format pass claim. The authorized Rust environment must rerun
the full package and scoped format check on this fixed source; library-only
filtering cannot close the original full-package build failure. Real validator
and engine remain unavailable, so candidate publication remains hard denied.
