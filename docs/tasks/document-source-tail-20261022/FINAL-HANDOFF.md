# Real COPY receipt-tail repair

Owned semantic repair source: `e5f96a834d65acf2ae43d3ec5abbd1ce7905ea19`.
Final pure-format source: `a193b69fc6e216d6f93b227f0e8854b206c2af85` (same semantics).
Test-first prerequisite/Text metadata codec source: `e5aaf8ddfa6c4cf8f467595cea1de4b431dcba05`.
Branch: `task/document-source-tail-20261022`, based e3fa0ee71f071bb8cff667d50ee1c0da6827a7c9.
Required final core source: `a961bb58c08ce77b559ce0d021d2ed50a857bb9e`
(owner report b7d5a7a21c4fd28064b916f984aec081c721f3bc). Core was not copied into this
branch or modified. The gateway source depends on that additive core interface;
this e3fa-based branch alone is deliberately not a complete integration build.
The owner combines the exact sources; only Leader B integrates develop.

## Change and real failure boundary

COPY obtains metadata plus the actual opaque same-Transaction publication token
from `document_clone_with_postcondition_in_transaction`. After the last committed
receipt UPDATE, receipt load/view, and original grant check, it consumes the token
through `document_publication_postcondition_in_transaction`. Errors propagate out
of the transaction and roll back head/revision/blob reference, actual source/binding
invalidation, notifications and committed receipt. One final read-only grant check
keeps expiry/revocation current after postcondition reads. No business write follows
the token verifier, and no work follows the last grant except COMMIT.

There is no token construction, renewed invalidation, notification repair, alternate
identity, successful mocked validator or edited-candidate publication. Preparation,
confirmation, original-intent query/unknown/no replay, permissions and budget semantics
remain unchanged. Existing Text metadata needed its missing decode arm before a real
StoreEvidence source could exercise the path; that arm roundtrips an already-supported
format and grants no new engine capability.

## Actual execution evidence

All commands are offline with the cached locked Rust 1.90 toolchain and existing
system SQLite linker alias. Original command argv, untrimmed stdout/stderr and driver
build/test paths are in `evidence/`. `23-final-manifest.json` pins the semantic source;27 pins the final formatted source.

- Historical e3fa+old gateway: 04/06 preserve two real receipt-trigger REDs;
  Text codec behavior RED02 and GREEN03 remain separate from the worker compile error01.
- Interface-first 9a357f27 core plus old gateway:10 still RED2; fixed gateway:11 GREEN2,
  12 all23 pass;13 core source subset23 pass. These counts apply only to that earlier source.
- Final a961 core plus old gateway:21 is actual RED2 (exit101), both return Committed,
  head2 and missing or prematurely acknowledged notification. It is not a source-only claim.
- Final a961 plus repaired gateway:17 all23 gateway tests pass, including real manual
  form/source positive control, unchanged older authorization/unknown/concurrency tests
  and both exact receipt triggers. Failed tampering returns StorageCorrupt, head1,
  no committed receipt, original source/binding/manual values retained.
- Final a961 core source-notification subset:18 all24 pass. Counts overlap full library
  and gateway runs; do not sum them as distinct coverage.
- Final a961 full real library:22 all186 pass (source subset24 is contained in186).
- Owned rustfmt:15 and explicit24 preserve the actual one-call layout failure.
  The earlier shell ended with an unrelated successful git command, so its overall
  status was not a valid rustfmt result; no format PASS is inferred from that status.
  Pure-format a193b69f fixes only call wrapping;25 explicitly exits0.
  Final formatted source reruns all23 gateway tests in26; no business code changed.

Actual integration driver command:
`python3 docs/tasks/document-source-tail-20261022/verify-gateway-direct.py <exact-archive>`
It cargo-builds the real library, then compiles the unchanged actual integration test
with rustc and actual muyon_core/serde_json/sha2 artifacts. No core/lib/worker/harness
source changes, mocks or fake API replacements. Final green archive16 and red archive20
pin the core; red uses the original e5aaf8dd gateway, green uses the repair source.

Core subset command:
`cargo test --offline --locked --manifest-path <exact-archive>/crates/Cargo.toml -p muyon-core --lib source_notification`

## Remaining integration gates

Ordinary Cargo gateway target was actually attempted at final a961:19 exits101 BEFORE
running tests because standalone business_worker path modules lack the real
`BusinessStore::invalidate_local_evidence_sources_in_transaction`, source_notifications.rs:107
(E0599). Earlier14 records the same problem at9a. This is pending the owning worker/core
module integration; no hook was disabled, stubbed, or edited here. The direct23 result
does not close this gate. The library also warns the legacy core clone wrapper is unused;
worker warns CandidateState/CandidateStatus imports unused. Do not claim warning-free
strict Clippy. This toolchain has no cargo-clippy, so no new local strict-Clippy PASS.

This is a COPY publication consistency repair, not host notification delivery/poll/ACK,
real Office editing, an engine launch or a release. Real edited-candidate publish stays
held. No main/develop edit, force push, branch deletion, deploy, paid/model/search request,
credential/permission change or user-file operation occurred. Historical unknown requests
were not retried. Independent review and final evidence details follow below.

## Independent review

A separate reviewer independently archived exact a961, overlaid only owned gateway/tests
and built into an isolated target directory. Actual gateway23/23 and real core source
subset24/24 pass. An additional independent test probes five actual committed-receipt
trigger mutations (notification generation, source reactivation, binding reactivation,
core metadata title and blob-reference deletion); all five roll back. These are
negative fault probes on real SQLite APIs, not mock postconditions or engine validation.
Reviewed SHA256 gateway: ad4a0f87cdbee45e22c05a3664135a7c19029f4287d2261bb0879a9abbcd561c;
test: f4832e6eb40c59af41dd99a912929d9bb229e7fb4f8c273947d33e43ea1ee5bf.
No new Important finding. Reviewer separately reproduced the ordinary Cargo worker
E0599 compile blocker; it remains pending, not passed. Raw independent logs/probe
source/manifests are in evidence/independent-source-tail-final/. An earlier reviewer
capacity failure performed no work; successful independent rerun supplies this evidence.

Reviewer also independently verified e5f96a..a193b69 changes whitespace only and
rustfmt truly exits0 (format-followup.json). Final gateway SHA256 is
537b4bb2a3a80a530e34d8d689d61304672326232684ca7ad19ea02ec5d47def, test unchanged.
Local final-formatted gateway23/23 rerun26 is separate from the reviewer's preformat
semantic tests; old/new hashes and exact scopes are not conflated.
