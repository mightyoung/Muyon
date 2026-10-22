# Reader/evidence native handoff

Branch task/reader-evidence-ffi-20261022. Native interface is INTERFACE.md.
Source dependencies: provider7bb89a713c0ce5678a8c4cae7fc5e24612d88362,
evidence78cdff32dee68b664c4fe71b4bbd6b81251af5e7,
reader report8d7323aab51ff76616ee196b90a7d4ee83b45d97,
reader source2e71384e808ecbe5bb010d05e87094e33e9cd3fd.
Original ff3 failure evidence remains imported; no old PASS count is reused as
this FFI's test result. New core independent acceptance belongs to parent.

## Delivered

13 typed native methods for exact metadata/readonly annotations; bounded open,
chunk/check/close/owner release/Service shutdown; actual StoreEvidence process,
literal query, exact quote, explicit citations and close. Actual same BusinessStore
connection/owner lock is retained through DocumentReaderHost, not a double store.
No new issuer/login/grant policy, arbitrary path, model/search/engine, account or
annotation save. JSON output is bounded, unsupported PDF/OCR stays unsupported.
Cleanup errors withhold output. Scope binds service-session/generation/project;
Host must validate actual current scope. All five existing draft methods remain
byte-identical to7bb89; no generated bindings/Host/Kotlin/core ownership edits.

Corrected public callback separately gates old StoreEvidence output after cleanup:
owned encoded result only, exact source metadata, fresh actual authorization,
no nested transaction. Processing lifetime has a tail check. Annotation projection
has the same2,000,000-byte source ceiling. Native full-capacity synchronization is
bounded8 checks at admission; raw chunk calls no is_current. Core64MiB snapshot
budget is payload, not total RSS. Native16MiB admission is no completion guarantee.

## Verification and evidence

Tests were authored first; first attempt in evidence/test-first.log exited127
because cargo is absent. This is NOT a behavioral RED. Twelve synthetic actual
store/grant/file tests are now authored; native-tests/fmt/strict-clippy logs again
record127/NOT_RUN. No unknown software installation attempted. Source checks PASS:
original five signatures/bodies identical, no private tx/database adapter calls,
no redundant chunk hash, diff whitespace. Independent review original2findings
and repairs are in INDEPENDENT-REVIEW.md; no remaining Important static finding.
Specific processing expiry DURING delivery still needs targeted runtime coverage.
No SQL smoke is represented as Rust success.

## Integration gates; no fake whole-reader completion

B alone owns core/lib.rs. CORE-EXPORTS-REQUEST.patch is the exact additive request
against this branch's unchanged lib.rs: bot_drafts and evidence exports, if not
already present in B's combination. It is a reviewable patch FILE, not an owner
source edit. B must compile/test/fmt/clippy and generate actual UniFFI bindings;
ABI changes require Host codec sync. Existing record prepare ABI remains unchanged.

Host needs its actual authenticated principal/session/project -> already issued
DocumentAccess/DocumentRef join. Grant references must never originate in model or
UI JSON. There is no fabricated authorized project enumeration or new grant API.

EOF closes core session/pin: bridge emits session_active=false and removes ID;
later check is invalidated. There is no reopening latest revision. Bytes may be
consumed synchronously by trusted code under this raw-read contract; copied bytes
are NOT an enduring cache/PFD authorization. Production PDF display remains HOLD.

Precise core-owner follow-up: additive display-retaining read mode on SAME exact
immutable source/pin/grant/generation, including EOF, with fresh is_current,
explicit close and real expiry. Cannot make current EOF ID active or silently
reopen another head. Core owner decides API; no private helpers need public export.
Host then needs a real bounded/digest-checked READ_ONLY seekable PFD, actual
Messenger transport, display lease checks/lifecycle disposal/invalidations and
Android tests. Explicit is_current hashes full source: never invoke perchunk;
any display check policy must be separately bounded and reviewed.

Annotation editing additionally needs original intent/journal/receipt recovery;
it is disabled in every projection. No dummy save/FD/permission/safety clearance.
Historical unknowns and reservations are untouched. No main/develop mutation,
force push, deployment, credentials/security expansion or user-file reads.
