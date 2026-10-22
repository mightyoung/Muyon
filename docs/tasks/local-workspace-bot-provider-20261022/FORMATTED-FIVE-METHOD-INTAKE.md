# Five-method source / verified formatter intake

Old4 strict-gate patch is independently published at
9ff15871556a4afc8f283a2fbc5d695d7531cd27, branch
task/local-workspace-ffi-abi-lint-20261022. B should use that commit/its exact patch
for the current old4 gate, without importing the journal/new5 source.

New5 source alone adopts purefmt111e51178645bdcf147a8a24a0caf3a76755db39 via
source-only cherry-pick95b303f26432ae420431089d27bae5d2629c37be. The source formatter
commit changes exactly the three owned Rust files; its verification-branch parent
and core lib.rs export are NOT imported. Core implementation and26-test source
match111e bytes exactly. FFI retains the new LocalDraftPrepareRequest record and
authorized old-save allowance. Two test callsite conflicts retained identical named
snapshot fields/fixtures/assertions, with formatter style. FFI normalizes exactly
to preformat typed-record01f6bea6 modulo whitespace and optional trailing commas.

Imported fixed evidencec4bc82b60f919eeedb7e466279efb783bc31a562:
SAVE-PREPARATION-RUST-VERIFICATION.md plus the complete, unchanged
independent-verification/save-preparation-20261022/ subtree (51 checksums).

Actual independent results for098d+sole export and purefmt111e:
provider26 PASS, full core209 PASS (includes26), three API probes PASS, including
both deterministic save/lookup orderings and32 finite barrier races per round.
Original3fmt FAIL retained; exact111e scoped fmt PASS. Both FFI attempts remained
BLOCKED before compilation by absent anyhow1.0.104 offline cache. No FFI test or
binding success is inferred from core/probe/formatter results.

The current core/test bytes match that actually verified111e source. Current FFI
adds a typed record and a single old-ABI allowance after that verified source;
those additions remain NOT_RUN for Rust/Clippy/fmt/actual UniFFI generation here.
B must generate real record/method bindings and verify its fixed composition; Host
must use the updated record API and keep verified=false pending its actual checks.
Old4 signatures/bodies remain unchanged. No PFD, annotation save or Android claim.

Independent final static review: no findings; exact core/test equality, FFI mapping,
fixtures/assertions, unchanged core export and all51 evidence checksums confirmed.

Retained helper failure: initial cherry-pick had two FFI test call conflicts. First
resolution omitted the cold test's archive declaration; normalization caught it,
and the declaration was restored before pushing. A second guard initially matched
both indented callsites and aborted before editing; fixed to exact line context.
Core whitespace-only normalization also correctly noticed rustfmt's closure-block
wrapping; the authoritative proof is exact111e bytes plus its actual209 run, not
pretending that a whitespace-strip comparison handles every formatter transform.
Final FFI normalized comparison and exact core/test checks pass. No failed evidence
was overwritten or source-owner test assertion removed.
