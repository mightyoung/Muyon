# Core candidate bridge — interface and native TDD plan

Fixed core b49ed859c331b4bd8004d8d3be5b8e12e7c7ff3e, source0ddb5d2a76ae42efcc7b252c86d2992a8a85c9f3,
interface81a7270ec4ef1eafff4b6e0e37bbd14314f5e5bb. Read CANDIDATE-{REPORT,INTERFACE}
and actual candidate.rs/blobs.rs. Initial exact12 core candidate tests actually PASS
(bridge-evidence01); this supersedes author NOT_RUN only for this exact combination.

Own files: edited_candidates/core_bridge.rs, edited_candidates.rs minimal module/init,
own integration test and own docs/verifier. No core/lib/FFI edits.

Interface: `EditedCandidateJournal::prepare_core_candidate_trusted(binding,access)`
and `lookup_core_candidate(binding,access)` -> CoreCandidatePreparation (original
binding, deterministic candidate/operation IDs, expected blob, actual core state).
Only a confirmed, non-cancelled, unexpired CandidateUnvalidated may initiate prepare.
Bytes come from validated own journal, never a fresh caller payload/path/hash.
Operation ID binds full reviewed patch digest; candidate ID also binds expected
bytes/length and full binding. Same-store durable invocation claim is recorded BEFORE
core prepare. The claim is not a second core outcome or document receipt.

A duplicate claim calls only original core lookup; even absent core row is Unknown,
never automatic preparation. Fresh read+edit grant may query original base without
adopting prior confirmation or execution authority. Core response identity/base/hash
must match frozen journal+claim; unknown/missing pin remains unknown. No pin/row
writes outside core public prepare. Real source/claim/grant checks precede and follow
delivery. Cancellation before new invocation blocks; in-flight core work may retain
private bytes/pin if cancellation/expiry is observed later. Cancellation is not file
rollback, and core currently has no gateway cancellation callback. No publication,
validation credential, source mutation, file overwrite or engine run is enabled.

TDD: first add bridge lifecycle tests -> missing API RED; implement minimum wrapper
plus exact claim schema; test object/pin actual bytes, duplicate/restart no replay,
claim-before-core fault, late core sealing/expiry failure, changed binding/source,
revocation/cancel, corruption, no publication. Add >128 unresolved-upload keyset GC
probe using original synthetic crash fixtures across projects. Run exact tests/full
core offline, ownedfmt, workspace gate; preserve failures and independent review.
If core bridge exposes missing semantics, report fixed minimal hook rather than
privately changing owner files. Commit/push this branch only with full SHA/evidence.
