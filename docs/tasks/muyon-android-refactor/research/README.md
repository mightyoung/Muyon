# R01 / R03 / R02 Rust domain and private-file implementation

Product source: `crates/muyon-core/src/research.rs`; the sole business schema writer adds the research tables and routes PaperCreate / ResearchImport through the existing durable executor. No Android picker, decoder, UI or FFI file was modified by this lane.

## Public interfaces

```
seal_research_snapshot(project_id, &[SnapshotEntry { relative_path, upload_id }],
                       Option<original_archive_upload_id>) -> SealedResearchSnapshot
papers(project_id, limit, offset) -> Vec<PaperRecord>
paper(project_id, local_paper_id) -> PaperRecord
entries(project_id, limit, offset) -> Vec<PaperRecord>
entry(project_id, local_entry_id) -> PaperRecord
documents(project_id, limit, offset) -> Vec<DocumentRecord>
document(project_id, local_document_id) -> DocumentRecord
paper_bindings(project_id, local_paper_id) -> Vec<PaperBinding>
research_sources(project_id) -> Vec<ResearchSourceRecord>
open_paper_attachment(project_id, local_paper_id, digest) -> ControlledReader
```

Lists/details bind to the real initialized store's workspace and a current existing project. Source records expose source_id plus distinct local CAS revision and external revision; UI must read this state when preparing a refresh rather than guessing expected_revision. Imported entries retain their separate stable local ID, original source record ID/revision, exact JSONL record text and derived display title. Manual and imported papers share the same catalog. Display fallback follows the legacy title/claim/statement/observation/query/step/cause/name/id/file-line chain, bounded to 500 display scalars without rejecting or truncating original JSON metadata. Imported null/missing title is permitted. Source revisions are projected to canonical unsigned text when parseable, with original loose metadata preserved independently.

`cite_entry_trusted`, `cite_document_trusted` and `choose_paper_binding_trusted` are host-only local domain operations for current-project reference/choice facts. They are not write commands available to a model. No new Android UI for citations or binding choices is claimed. Manual ambiguity decisions survive refresh when the same ambiguity recurs; candidates in other projects are not removed.

## Manual PDF

PaperCreate requires the actual project and the validated P01 payload. Its exact attachment_upload_id is part of plan/binding; actual upload kind must be Pdf both before execution and inside the business transaction. The private reader validates hash/length, and bounded streaming checks inspect the `%PDF-` header and `%%EOF` in the final 1 KiB. This is a basic format check, not a full malicious-PDF detector. Optional authors/year/DOI/URL/notes persist without automatic networking.

The actual uploaded blob is published through P05's exact active transaction token in the same SQL transaction as entry/document/binding/history/receipt. If attachment_upload_id is absent, an already published, readable same-project reference plus actual private bytes must be proven; a digest alone cannot borrow another project's upload. New stable paper IDs cannot overwrite existing rows. Source removal after upload does not remove the private copy. Original intent duplicates recover the stored original receipt.

## Trusted snapshot sealing

Only the trusted host file port should invoke the sealer. Inputs are opaque IDs of actual pinned private uploads, not arbitrary filesystem paths or records. The sealer validates relative names, NFC aliases, duplicate upload IDs, file-prefix collisions, the 30 MiB file / 150 MiB kept package / 10,000 file bounds, existing project/revision and current upload owner. Research-skill root detection and skip paths are ported from `research_skill.dart`; four base logs establish the root, V2 metadata controls layout, and task/result `research-package-v1` manifests are refused at this entry.

For ZIP, A01 parses the actual immutable archive's ZIP32 metadata and rejects unsupported flags/types/links/offsets. The trusted platform decoder supplies immutable decoded member uploads; Rust independently streams each actual member through A01's length/CRC validator, and STORED members additionally match the original archive bytes at their validated offset. The method does not implement DEFLATE; platform inflater correctness and actual Android file-provider handling remain separate runtime gates.

Rust reads and parses real frozen JSONL/manifest files. Unknown JSON metadata stays inert; duplicate JSON object keys and non-object JSONL rows fail. The generated sealed-manifest blob contains the exact accepted file/upload/digest descriptors, project/revision/epoch, optional original archive and records fingerprint. A persisted registry binds that actual manifest upload to the owner/project. It is not a UI-created JSON manifest.

The records fingerprint is the stable SHA-256 of the **ordered list of each ImportedPaper's stable digest**, avoiding a full extra JSON tree and byte copy of all records. The manifest digest separately binds all document bytes. SourceRef import commands may omit records or send `records: []`, keeping the command below 1 MiB even for a larger JSONL package. If records are provided they must exactly match Rust's records reparsed from the frozen snapshot. Wire records never establish what the file contains. Seal results serialize only digest/count/layout/root and the manifest/upload reference; their Rust-only records vector is not serialized across Binder.

## Refresh and references

The implementation follows `exchange.dart:234–546`, not a generic upsert. Same kind/id/revision duplicates are preserved as independent local rows and reported. Existing rows pair at most once: identical cited content first, identical content next, then an uncited row. A leftover cited record whose same source key changed refuses the entire refresh; missing cited material stays. Only missing uncited records are removed. Manual papers and other import sources are outside that cleanup.

Documents pair by project-relative path. Changed bytes with a current citation retain the old local document and bytes as a retained version, while the new version gets a new ID. Missing cited documents remain; unnoted missing versions can be removed. Material-binding and arXiv manifests compute actual hash-checked candidates, current source revisions, ambiguity and manual choices. A hash-mismatching or ambiguous automatic candidate does not expose an accepted paper attachment.

Every import consumes the exact manifest/document/log/archive upload pins in the **same** active business transaction that publishes rows, references, source CAS revision, business history and original receipt. Source refresh uses its own local revision, distinct from the project's revision and external source revision. Pending/unknown remains read-only recovery; sourceRef preparation never causes automatic redispatch. Final transaction checks verify actual paper projections or source/member hashes/revisions plus committed upload state after receipt/history writes.

## Resource boundary

Opaque PDF/Markdown bytes are never accumulated for batch seal/import. P05 opens/hash-verifies them in bounded chunks; ZIP decoded members are validated in 64 KiB chunks. Only one bounded textual JSONL/manifest file is aggregated for parsing, then released. Raw records and their parsed metadata are retained within the bounded import; bindings borrow those records instead of cloning the complete collection. The original ZIP remains a single bounded in-memory buffer of at most 150 MiB because A01 currently parses bytes. This remains a memory boundary requiring device validation; no device OOM was reproduced or claimed fixed by the local repair.

Proof: [VERIFICATION.md](VERIFICATION.md).
