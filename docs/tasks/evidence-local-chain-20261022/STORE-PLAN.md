# Store integration plan and ownership (follow-up to 741274f6)

Consume exact core dependency aec085fafef8aa02f86f2fc60626f168b10f4caa.
Its production Text/history source is 64017cd443a32b131c0d0851ba9346625d95819c.
Owner changes are imported by ordinary merge only. No author edits to lib.rs,
documents/, blobs.rs, Android shell/service or FFI files.

1. Tests first for real synthetic text upload/register, persisted ReadText (Inspect
   insufficient), current revision/grant generation/epoch/expiry/project and real
   reader lease checks. A separate Unknown-to-Utf8 negative must fail before fix.
2. Split pure processor in local.rs from concrete owner adapter in store.rs.
   Keep public root API and versioned JSON; require explicit Text + actual UTF-8.
3. Reuse document_access_in_transaction and controlled blob reader. Preliminary
   transaction resolves exact registered bytes, existing open_blob_reader acquires
   its lease in its own transaction, final BEGIN IMMEDIATE rechecks authority,
   reads/hashes bytes and computes/delivers the projection under the same owner
   call. Tail check covers authority/expiry; close reader after commit/rollback.
   The preliminary check alone never authorizes delivery. No new core hook needed.
4. Privately scoped real DocumentHost holds the same live Transaction and actual
   EOF reader, querying persisted grant/head and core lease on each use. No trait
   default, caller bool, duplicated policy SQL or fake CurrentDocument fixture.
5. ProcessingReceipt remains parser result. Core metadata proves only a registered
   historical source snapshot. Original import/saved intent receipts and index
   completion must come from their existing owners; do not generate them here.
6. Independent source review + actual Rust tests; preserve failures/NOT_RUN.
   Freeze source commit before final verification and push dedicated branch.

The owner export patch is intentionally unapplied on this task branch. Pure tests
compile the actual local.rs; store unit tests use an isolated generated module
entrypoint with actual original core/evidence sources and original visibility.
Full-core mode also runs every original core integration target and worker binary.
All dependency versions/sources/checksums must match the fixed repository lock.
No source rewrite or production export claim is made by this test harness.
