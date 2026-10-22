# DOC-01/03/04 persistence source delivery — runtime acceptance HOLD

Source base: `d2ac6a87a8bf13d8a22ebd41676683be8d849a22`.
Interface published before implementation:
`7c4a0664969da312208f1c0625920aae21c58948`.
Initial implementation: `3a9af62952ce6308d675211e4e030015aed4fa1e`.
Revision-key, payload-bound and gateway-interface correction:
`54b45d979e8443b1cd5f868b6b851eafe31c9555`.
Final reviewed production/test source:
`0b3d7df329c978b38e2b6523611343f82147e063`.

## Implemented behavior

This slice adds concrete SQLite/blob operations, rather than more empty traits:

- Reuses `BusinessStore`'s connection, owner lock, transactions and existing blob
  upload/publication. Explicit versioned schema initialization adds six tables;
  no existing business schema migration, competing store or DB file.
- Registers uploaded immutable document metadata at revision1. Publication checks
  the exact expected base and appends the next metadata/blob reference. Earlier
  file bytes and revision rows remain intact; sidecar writes never rewrite files.
- Persists exact document grants using existing `AuthorityBinding`, next-generation
  reissue, current owner epoch, active state, project liveness, exact scope/revision,
  operation intersection and a maximum 30-second expiry. Every metadata/sidecar
  operation checks these SQL facts in the same transaction as its access.
- Creates/updates/deletes comment/highlight sidecars with stable IDs, independent
  revision CAS and tombstones; stores history and separates immutable creator
  from current editor, including explicit Human vs Ai actor/run provenance.
- Rejects invalid/unresolved anchors on save. Existing anchors survive document
  revision changes and are returned/exported as stale rather than guessed forward.
- Exports deterministic, serializable `muyon.annotation-sidecar.v1` data, including
  tombstones and provenance. This is not native DOCX/PPTX/XLSX/PDF comment sync,
  PDF flattening, file output, outbound permission or renderer support.

Persistent JSON is byte-bounded before SQLite returns TEXT to Rust, with 1000
annotation records, 256 KiB per annotation payload, 16 MiB aggregate payload and
8 KiB metadata/grant document payload. Writes preserve the aggregate read budget.
SQL revision keys are cross-checked against payload identity/revision; missing or
inconsistent current metadata fails closed. Tombstones continue consuming stable
IDs/count budget; history compaction is not introduced.

Trusted host methods are not model-callable and do not authenticate a claimed
actor by themselves. The host must derive creator/editor identity and issue grants
from real session/project/group policy. No current group-membership integration
or document byte-reader authorization adapter is claimed by this source slice.

## Transaction author handoff

See [exact signatures and ownership](PERSISTENCE-INTERFACES.md). On the same
existing `BusinessStore::database()` connection/`Transaction`, call:

1. `document_access_in_transaction(tx, access, required_operations)` for current
   persisted authorization and exact authoritative base revision.
2. `document_publish_in_transaction(tx, base, title, format, finished)` for CAS
   metadata/blob publication. This is a trusted low-level hook, not confirmation.
3. Gateway writes its own receipt/intent journal, then commits once. Propagate all
   errors and roll back; do not nest a self-committing wrapper. Both hooks check
   `Transaction::belongs_to` the existing connection and neither commits.

The grant can name all nine typed operations; this establishes no engine
capability. Gateway must enforce its own user intent, capability, validation,
idempotency, cancellation and recovery protocol. A prepared upload remains pinned
if publication rolls back; the gateway must manage its future lifecycle explicitly.
No gateway/Android source was edited or integrated here. A shared-storage seam
exists, but combined end-to-end atomic receipt behavior awaits the gateway author's
implementation and combination tests; do not claim it is already verified.

## Verification

13 Rust integration tests were written, including synthetic blob/metadata/sidecar
reopen, revocation, scope, expiry, deleted project, permission intersection,
creator/editor provenance, CAS/tombstones, old-anchor retention and export JSON.
Independent-review regressions add mismatched SQL revision keys, missing revision
rows, oversized persistent payloads, post-blob metadata failure and post-history
annotation failure via synthetic SQLite triggers, plus write/read budget stability.

Commands from `/workspace/Muyon`:

| Command | Actual result |
|---|---|
| `cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --test document_storage` | NOT_RUN, cargo absent, shell127 |
| `cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core` | NOT_RUN, cargo absent, shell127 |
| `cargo test --offline --locked --manifest-path crates/Cargo.toml` | NOT_RUN, cargo absent, shell127 |
| `cargo fmt --manifest-path crates/Cargo.toml --all -- --check` | NOT_RUN, cargo absent, shell127 |
| `git diff --check` | PASS exit0 |
| `python3 docs/tasks/document-core-contracts-20261022/persistence-evidence/sql_smoke.py` | PASS: exact six-table source schema and 19 SQL statements; synthetic SQLite metadata/annotation reopen, stale CAS, revoked-grant exclusion, provenance/tombstones/history, oversized metadata projection and rollback |

The Python smoke executes actual SQL extracted from Rust source using Python
SQLite3.53.1 and disposable original synthetic rows. It does **not** compile Rust,
execute Rust authorization/anchor/body validation, run the blob publication path,
or test the full Rust API. It is supporting SQL evidence only. The independent
Rust validator must run the commands above against this new source. No old
18/18 or 165/165 result is inherited for this changed source. Workspace's known
offline dependency blocker is not declared resolved.

Original NOT_RUN/TDD history is untouched. Test source preceded implementation,
but no successful RED/GREEN execution occurred here. Logs remain in
[persistence-evidence](persistence-evidence/), including the initial source-SQL
run, a stale smoke-script query-selector failure after SQL changes (05), and the
corrected final run (07). The smoke harness failure was corrected; no Rust test
failure/pass is inferred from it. Final environment/commands are in
[08-final-environment-verification.log](persistence-evidence/08-final-environment-verification.log).

## Independent review and remaining blockers

Separate read-only reviewer `document_contract_review` reviewed initial immutable
source `3a9af629` and raised two P2 blockers: SQL key/payload revision mismatch
could accept an old revision after corruption, and oversized JSON could allocate
before limits. The reviewer also requested late-failure rollback coverage.

On fixed source `0b3d7df3`, the reviewer statically closed both P2 findings and
coverage gaps, found no new key issue and confirmed shared-transaction ownership
checks. Reviewer conclusion: **static review passed; runtime acceptance HOLD
because Rust compile/test/format remain NOT_RUN**. No reviewer file edits,
engine runs, user-file access, installation or commits.

Main/develop remain unchanged. No third-party engine, SDK/dependency installation,
network/model/search call, credential, expanded permission, user-file access,
deployment, paid action, historical unknown retry or reservation change. Existing
Leader B remains sole develop merger. Full reader/native editing and gateway/UI
integration remain unfinished; this is a concrete persistent core slice, not a
claim that the whole Office product is complete.
