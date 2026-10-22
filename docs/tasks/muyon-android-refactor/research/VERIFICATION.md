# Research Rust verification — 2026-10-20

Worktree `/private/tmp/muyon-android-refactor-20261020`; no Android/FFI/Cargo changes by this lane. Schema and dispatcher additions are in its existing business.rs ownership; P05 remains owned independently.

Actual commands:

```
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --test research
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core research::resource_tests::real_opaque_uploads_are_not_aggregated_when_sealing_or_importing --lib
cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --test research --test business --test contract --test blobs
cargo clippy --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --all-targets -- -D warnings
```

Fresh results after the streaming repair: **research 15 passed / business 12 passed / contract 10 passed / blobs 8 passed**, zero failures and zero ignored. The separate real-resource unit also passed, 1 passed/0 ignored. Clippy with warnings denied passed again after the final borrow-only cleanup, exit 0. Final rustfmt --check and git diff --check on owned files/docs also exit 0.

Frozen source SHA-256: research.rs `7b9b62e91772a23fd1d2bffc6ab9e4c9c436200ec2e6d18ab13d9f65748003e5`; business.rs `0296db296f28d281ceb319dd68ba88171f3e39b1c11e13ed76d7a3214fc809e4`; tests/research.rs `4c19406ff67eb4569fe58f3bec5794951866ce0f0a6f4aef501525bcf93a836a`.

| Executed behavior | Actual assertion |
| --- | --- |
| real private manual PDF | actual P05 Pdf upload, metadata/entry/document/binding SQL commit, deleted source file, private attachment reopen and original receipt recovery |
| one real project catalog | manual PDF and imported papers appear together, while local ID / external record ID / source revision remain separate |
| project/kind/upload refusal | exact blob in a different project or a Document-kind upload cannot be used as a manual Pdf; no entry is published |
| original JSONL and duplicate revisions | leading/trailing record whitespace preserved, duplicate kind/id/rev rows remain distinct local IDs, count reported, one current binding selected |
| cited immutable revisions | changed cited same-revision record rejects with no source/attachment publication, explicit new revision succeeds and keeps the old cited row |
| refresh cleanup | missing uncited entry removed; changed cited document gets retained old bytes plus a new version; stale mismatching material hash is not accepted as attachment |
| wire forgery | changing raw_json/record consistently in the command still fails against the actual sealed snapshot; wrong project fails |
| malformed materials | duplicate JSON keys, traversal/absolute/backslash names and unrecognizable-only material reject before domain publication |
| sourceRef larger than wire budget | actual JSONL exceeds 1 MiB, sealed return does not serialize raw records, command stays below 4 KiB, 80 actual papers imported |
| actual SQLite fault window | receipt corruption after actual manual publication rolls entry/document/reference/history state back; upload remains pinned; original pending stays unknown, cancellation then blocks its retry |
| real process fault after paper commit | business_worker actually commits the real paper/private blob, withholds reply at a marker and is SIGKILLed; reopen obtains exact original receipt and one paper |
| actual stored ZIP | directory and actual ZIP generate identical records fingerprints; changed decoded member bytes fail CRC/length binding |
| manual ambiguity carry | explicit current-project candidate choice removes competitors; a repeat refresh preserves its stable local ID and +manual selection |
| import domain tail fault | a real AFTER UPDATE trigger corrupts imported raw JSON after receipt write; member-tail verification rejects and rolls records/source/documents/blob references back |
| loose import versus manual constraints | null title, claim fallback, original `rev: "01"`, unknown fractional metadata and absent source record ID import without manual-title rules |
| source-layout fidelity | prefixed four-log research-skill root recognized; actual arXiv manifest binds private PDF only when its actual hash matches |

## Resource repair evidence

Independent review identified static allocation pressure: the first implementation retained decoded file vectors and the complete ZIP concurrently. No device OOM was reproduced. The repair removes that data map, streams each decoded ZIP member's CRC/length and STORED byte comparison, reads only one textual file on demand, moves rather than clones seal records, fingerprints ordered per-record hashes, and borrows records for binding computation. Manual PDFs use streaming header/final-tail checks too.

The resource unit uses real 2 MiB PDF and 2 MiB Markdown private uploads. A test-only thread-local observer counts calls to the aggregate upload reader: **0** while sealing those opaque documents, **1** while actually importing (the small generated manifest), with both document rows committed. This proves the tested code path does not aggregate opaque PDF/MD, not a measured whole-device peak-RSS guarantee. A01 still aggregates one original ZIP up to 150 MiB, and bounded parsed JSON records retain structured metadata; those remain explicit resource boundaries.

## Initial diagnostic failures and repairs

The process-fault worker initially re-exported crate-private transaction/contract helpers across a crate boundary; cargo check failed. The worker now compiles the exact product modules by path inside its test binary, and actual process tests pass. This compile diagnostic was never reported as behavioral RED.

During streaming validation, `--locked` refused a concurrently changed workspace lock. The parent regenerated its owned lock offline; this lane preserved `--offline --locked` and resumed actual tests afterward. No temporary dependency or weakened assertion was added.

## Remaining gates

This is Rust domain/private-file proof. Android picker URIs, its trusted directory provider, real platform DEFLATE output, API26 UI/Service flows, memory behavior on a device, native artifact identity, search/live model and whole-application recovery still need their own evidence. Existing Rust A01 metadata/decoded-stream vectors do not turn a missing Android decoder run into an end-to-end ZIP pass. New persistent snapshots from a new owner epoch require a new trusted file-port sealing; original pending/committed intents use original receipt lookup and are not silently reauthorized.
