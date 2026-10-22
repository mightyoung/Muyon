> Latest real core prepare/query bridge: [CORE-CANDIDATE-BRIDGE-REPORT.md](CORE-CANDIDATE-BRIDGE-REPORT.md).
> Historical SQL-only preparation below is superseded; publication remains disabled.

# Held schema2 and edited-candidate preparation delivery

Scope: follow-up to90b7a35a49f4acb09ff73a2b088df4c1d1a037a6, same isolated branch.
Source commit: 68a31b1fa79cf6fb848c29d8bf77eb346ec3fca1.
Interfaces/plan pushed first:3a625b34ca6468bb9c1c9338b087ad43d9db04b6.
Exact core actually tested:a27f04aa2460971940d4bdf2c8263bdf81f381c2; read the core
COPY-CLONE-REPORT and COPY-CLONE-INTERFACE future pin/publication proposal.
Adapter protocol read:6b796c8d6e094d45ef25e28698048c21ef0ae7b3 PROTOCOL-v2.md,
protocol.py and text_common.py. No third-party engine/source was copied or executed.

## Delivered

Expanded-tree-json-v1 canonicalization over trusted expanded tree observations:
Python ensure_ascii=true including UTF16 surrogate escaping, compact punctuation,
sorted expanded attributes, distinct null/empty, comment/PI tags, text/tail and child
order. Duplicate attributes, excessive tree/depth/size reject. It is not an XML parser
or fingerprint of a rendered selection. Five original Python golden vectors compare
raw canonical bytes AND SHA256; independent sampling covered2308 Unicode cases.

Typed schema2 DOCX run and PPTX shape locators bind source hash, exact part/path/
indices/slide+shape IDs, whole run fingerprint, exact old/new text and full operation.
Format must match actual DocumentRef. DOCX indexes bounded9999; PPTX's narrow0/0
paragraph/run and valid source-resolved slide part/IDs required. Multiple text nodes,
wrong expected text, no-op/control/oversize text, unsupported space changes reject.
The gateway resolves real current source metadata/grant before mapping and checks
again before delivery. The run/locator itself must be a trusted host read-side
observation; no package reader or proof that it came from those source bytes exists
here. No source eligibility, full package grammar or Office fidelity is claimed.

Request digest includes schema version, tightened eligibility policy epoch, actual
format, title, source length/hash, full scoped document identity/revision, intent and
complete operation. Legacy v1 wire shape remains intact but old preview/confirmation
hashes invalidate. Hidden/protected/merged qualifications require a fresh real
adapter preflight in future; this code does not inspect those source flags.
Matching schema2 responses remain EnvironmentHold; response version mismatch,
unknown/duplicate keys, mismatched identity/hash, simulation/fake and expiry reject.
No response returns a success permit (Result<Infallible,...> remains).

A separate `edit_candidate_intents` journal persists the held request, frozen source,
confirmation/expiry, one ingestion claim and bounded different bytes on the SAME
BusinessStore connection/transaction/grant truth. States: Planned, Confirmed,
Unknown(in-flight), CandidateUnvalidated, Cancelled. Explicit fresh confirmation may
renew only known states. Prepare alone never renews consent. Candidate ingestion
checks original head/source and current ReadText+StructuredEdit/authority, writes
bytes/hash/length, reconstructs view, checks live authority last, commits once.
After durable claim, any failed/uncertain ingestion remains query-only Unknown;
restarts/duplicate calls cannot replay or replace the original candidate. Exact
binding and original intent prevent cross-scope or cross-operation reuse.

Candidate preparation is SQL data only: no immutable blob, pin, upload/staging,
file overwrite, document revision/CAS or document-success receipt is produced.
Bytes are capped8MiB per edited candidate, and edited+COPY journals share150MiB.
A duplicate staged call returns original preparation metadata, not a second write.
Reading unpublished bytes separately requires original revision, current
ReadText+StructuredEdit, exact fresh confirmation and expiry; Inspect/source-only
ReadText/new unconfirmed grant cannot deliver edited content. Cancel retains data
and prevents work/delivery; it is not a rollback. Source revision change rejects.
`commit_edited` remains UnsupportedOperation; no validation success API exists.
COPY-only clone is unchanged in meaning and refuses a non-original hash.

## Actual checks and evidence

Use the existing toolchain/cache/linker alias environment in DURABLE-REPORT.md:

```bash
bash docs/tasks/document-edit-transactions-20261022/verify-durable-combination.sh -p muyon-core
```

Script now also copies three new test targets+golden JSON into the exacta27 archive
and temporarily exports document_edit there. No working lib.rs/core/FFI edits.
Final actual fullcore17: **262passed,0failed,0 compiler warnings**,24 distinct target
summaries including0doctests. New schema2=6, candidates=12, policy=1 are subsets,
not added to262. Existing gateway19/protocol6/memory28 also passed within that run.
Owned rustfmt20exit0, script bash syntax0. Frozen source/env/archive hashes:21.

Full workspace19 exited101: locked cargo-platform0.3.3 requires Rust1.91, current
rustc/cargo1.90.0. No dependency changes/downloads/toolchain update in this slice.
Flutter absent from original environment; full application gate remains NOT_RUN.
No engine/worker/fake dispatch, actual OOXML edit/reopen/render/fidelity, real
model/search, user file or historical unknown request was attempted.

Test history and explicit fixture failures: next-evidence01-21 and SCHEMA2-LEDGER.md.
Missing new APIs02/05/07/16 are compiler RED, not behavioral failures. Real behavioral
09 demonstrates asymmetric quota;12 demonstrates private candidate disclosure;
14 is the exact prior-source legacy preview binding regression.04 and11 are test
fixture compile/generation mistakes and are retained, not counted as product failures.
08's old wrong expiry column cannot prove expiry-tail safety; corrected10/15 and
four FAILing removed-tail mutations18 establish the real check. Mutation uses its own
archive/target directory, preserving final exact archive and independent reviewer.
Earlier DURABLE-REPORT.md/FINAL-HANDOFF.md remain historical COPY delivery evidence.

## Remaining boundaries and hook request

See EDITED-CANDIDATE-INTERFACE.md for exact minimum scope/base/operation/hash-bound
immutable candidate pin prep/query and same-transaction pin->reference/CAS hook
requirements. There is no such safe full hook in fixeda27; SQL journal bytes cannot
stand in for a core-owned prepared object. No different-bytes publication, real
validation, actor/group admission, product reader, model tool, FFI/UI, engine license/
provenance/isolation/fidelity or schema2 whole-package acceptance is implemented.
The actual engine's filesystem denial is never retried or bypassed. Quotas bound
stored candidate bytes, not all metadata/history/journal growth; retention/compaction
and orphan reconciliation still require explicit owner policy. New Office packages
with masters/styles/auxiliary content remain outside adapter's tiny subset.
Only Leader B may integrate develop; permanent lib export remains core owner work.

## Independent final review

Fresh non-author exact-source full core262/262 exit0; independent candidate/held
probes5/5; Unicode2308 samples matched raw canonical bytes+hash. No remaining
blocking finding. Quota and test-expiry findings closed; edited delivery was
conservatively tightened with real behavioral RED12. Full source/probes/raw logs:
next-evidence/independent-schema2-{static,final}/. Test counts overlap, never summed.
Reviewer confirms no object/staging/upload/reference/revision effect from preparation,
request/source-title corruption rejects and new grants cannot resume Unknown.
