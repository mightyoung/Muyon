# ABI-compatible current gate / typed future preparation

Parent directed scope: inspect B82169330ff6868b5979e351056d538dd496e9519
STRICT-GATE-REMAINING.md. Explicit permission covers ONLY a reasoned method-level
clippy::too_many_arguments exception on fixed local_draft_save. It does not permit
global/impl allowances, another suppressed lint, behavior/test weakening or unilateral
replacement of accepted generated ABI/Host callsites.

## Current four-method combination: independently usable minimal delivery

Use branch task/local-workspace-ffi-abi-lint-20261022, fixed source
9ff15871556a4afc8f283a2fbc5d695d7531cd27 (based8b2d7783, no journal/fifth method).
Or apply FIXED-FOUR-METHOD-ABI-LINT.patch generated against exact B82169330 FFI.
Only two comments plus #[allow(clippy::too_many_arguments)] are added directly on
local_draft_save. Signature, argument order, return/error shape and body remain
byte-identical after removing those three lines. Existing unrelated baseline
allowances are preserved; exactly one NEW local exception is added here.

Why not substitute a record there: accepted generated UniFFI signatures/checksums
and actual Service9d2 positional localDraftSave invocation would change. A wrapper
preserving old ABI still has this same argument count. A deliberate later versioned
migration may introduce a save request record and retire the compatibility method
after Host + actual generation updates; it is not the current quality-gate repair.
B can close its old4 gate without importing this next5 source.

## Queued new fifth API: typed record before first accepted generation

The queued098d local_draft_prepare_save had10 explicit parameters plus self and
would trigger the same default lint. It has not been accepted/generated into B's
old4 combination or used by fixed Host9d2. Therefore it now takes ONE typed
LocalDraftPrepareRequest, derived through existing dependency UniFFI0.32.2 Record.
The repository already uses this derive in android-rust-bridge-lab records; no new
dependency/UDL/handwritten JNI or unsupported package is introduced.

Record fields/types and exact method signature are fixed in INTERFACES.md and
SAVE-PREPARATION-INTERFACE.md. It contains exactly the10 previous snapshot values.
Method destructures the record into the same local variables; validation, core
prepare call, atomic journal/state machine, result JSON and errors are unchanged.
Both FFI consumer tests now construct that actual typed record. Core26 tests and
source remain unchanged. No lint allow on prepare or the record. Core continues to
group its two captured revisions in SaveRevisions and remains at7 arguments.

Host action: DO NOT implement the superseded098d positional fifth method. Adopt
B's newly generated LocalDraftPrepareRequest and call localDraftPrepareSave(request)
using actual generated names/types. B must regenerate and compare real binding bytes
on the accepted new5 source, then Host updates strict codec/calls. No generated Kotlin
was hand-edited here. Old4 signatures/body are retained. verified stays false.

## Verification boundaries

Independent static review of old4 patch: no findings, exact ABI/body preservation.
Old4 patch applies cleanly to exact B source in a temporary code-only checkout.
New5 record mapping/source checks and git diff --check pass; runtime checks remain
NOT_RUN because cargo/rustc/rustfmt/UniFFI generator are unavailable here. Historical
B435/four-method14 PASS and old strict-gate FAIL remain evidence for their exact
sources, not acceptance of the new record or local exception. B must run its full
strict gate and required fixed-source checks; later diagnostics are not inferred away.


Independent read-only new5 re-review: no findings. All10 field types/values map
exactly, all four original native signatures/bodies remain byte-identical, and the
prepare body after request destructuring is unchanged. Core source/26 tests are
unchanged and no allow was added to prepare. Generation/Host validation NOT_RUN.
