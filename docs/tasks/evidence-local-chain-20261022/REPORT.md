# MIG16 / U01–04 U07–08 — concrete BusinessStore follow-up

Verified source: `3296cb8402afd5003279ad443d701dda1fee9f56`.
Core dependency: `aec085fafef8aa02f86f2fc60626f168b10f4caa`.
Dedicated branch: `task/evidence-local-chain-20261022`.

## Delivered behavior

The first delivery's pure processor is now in evidence/local.rs. evidence/store.rs
adds the real BusinessStore DocumentHost and processing receipt path. It reuses
persisted ReadText grants, current registered document revision/scope/project,
generation/epoch/expiry, and actual controlled blob reader leases. It never treats
Inspect or a client permission list as ReadText authority.

Within final BEGIN IMMEDIATE and the existing owner call: reauthorize exact
metadata; read real controlled bytes; verify SHA-256/length; parse/project; validate
current authority and reader lease again; commit. Cleanup is explicit; failure
cannot return a successful payload. A preliminary transaction permits acquisition
of the existing reader API; it is not used as delivery authority. Tests demonstrate
SQLite 5 writer exclusion during delivery and successful writer access afterward.

All StoreEvidence open/find/answer operations reopen actual controlled bytes and
recheck current authority. Cached text is private, not wire-deserializable and
redacted in Debug. StoredProcessing has no caller-supplied DocumentHost escape.
The adapter creates no store/schema/index, no import/save business intent and no
new grant; it does not touch original unknown operations or reservations.

Text is now exact core Text + explicit Utf8Text + validated actual UTF-8, not
Unknown. Contradictory formats and canonical PDF bytes relabelled Text fail.
Registered PDF/OCR produces Unsupported without fake content. Index remains
NotRun. Real core metadata and actual parser receipt are separate fields in
`muyon.stored-processing.v1`; there is no invented saved/index success flag.

Source, receipt and evidence identity bind exact scope/document/revision/blob.
Quote opening validates byte range and digest. Body, explicitly selected citations
and uncited candidates remain separate; claim support is unassessed, independent
corroboration count unknown. Old revision access is rejected, never redirected to
latest or granted by a publication-tail check. Text never gets a fabricated page.

## Actual Rust verification of the frozen source

- Standard pure processing suite: 16 passed, 0 failed.
- Standard workspace on fixed core: 226 passed, 0 failed, 0 ignored, 21 groups.
  This does not include the unexported store adapter.
- Full-core source harness: 225 passed, 0 failed, 0 ignored, 19 groups, including
  all original core integration targets, actual core unit tests and 12 real store
  tests. Android FFI workspace targets are outside this isolated core harness.
- Independent reviewer on exact 3296cb84: store 12 passed, 0 failed, exit 0;
  no unresolved Critical/Important source findings. Final evidence hashes in
  REVIEW.md. Counts overlap and must not be added together.
- Scoped rustfmt, Python syntax, source/prose whitespace and owner-file identity
  checked. Raw tool logs retain their whitespace and all failures.

Source was frozen before final verification. Later delivery commits change only
reports/logs; SOURCE-MANIFEST.json binds the exact source files to the frozen SHA.
Shared history/Text Rust tests run as actual Rust in the full-source harness and
standard workspace. No SQL smoke result is substituted for Rust execution.

## Ownership, limitations and remaining actions

No author changes to lib.rs, documents/, blobs.rs or Android shell/host/FFI source.
Those source paths match fixed core aec085fa exactly; incoming owner commits were
consumed by ordinary merges. No main/develop writes, force push/delete, deployment,
payment/credential/security permission changes, real model/search requests,
user real-file imports or engine-isolation HOLD bypass.

Pending, not denied: parent B applies the existing core export patch on the actual
combination branch; Service/FFI owner calls the new concrete StoreEvidence adapter
under the existing trusted store guard. Native UI, durable import/saved receipt
binding and ResearchIndex wiring remain that integration work. Adapter source
and real database execution are delivered, but product entrypoint completion is
not asserted. Android build/device, PDF extraction/OCR/geometry runtime and real
external model/search calls are NOT_RUN. See HANDOFF.md for exact APIs and steps.
