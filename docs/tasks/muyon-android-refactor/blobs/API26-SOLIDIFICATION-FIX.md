# API26 private blob solidification repair

## Reproduced failure

Actual product instrumentation in `/private/tmp/muyon-product-api26-second.log`
failed both PDF and ZIP `finish_upload` calls with `unknown: StorageIo`.
Supplier tests passed. Parent device inspection found original staging files
present (15,308 / 676 bytes) and an empty objects directory.

The exact device log in `/private/tmp/muyon-product-api26-logcat.txt` lines
6302, 6411 and 6527 identifies the failing operation: `avc: denied { link }`,
`scontext=u:r:untrusted_app:s0:c512,c768`, `tcontext=u:object_r:app_data_file:s0:c512,c768`,
`tclass=file permissive=0`. This is an actual SELinux hard-link refusal, not a
CRC/content rejection. No SELinux change, elevated helper, permission bypass,
hard-link retry or ignored error is part of this repair.

## Reviewed replacement protocol

The same protocol is used on every host; there is no failed-hard-link fallback.
All operations remain under the existing BusinessStore connection transaction,
OS owner lock and trusted Service's serialized writer. Private directories
remain 0700 and managed files 0600.

1. Validate original upload/project/epoch/revision, byte length, typed envelope
   and SHA-256 using the retained original staging file.
2. Inspect final digest path with `symlink_metadata`. Any existing target is
   never renamed over. A regular existing file is reused only after exact hash
   and length validation; corrupt/special/dangling-symlink targets fail closed.
3. When absent, create `staging/pub_<upload_id>` with create_new and O_NOFOLLOW.
   Copy in <=64 KiB reads/writes, checking actual copied length and SHA-256.
   A previously existing temporary is reused only if already complete and
   verified; a partial/corrupt/symlink temporary is not overwritten.
4. Sync the copied file and staging directory. Recheck final path with
   symlink_metadata, and rename only the copied temporary when still absent.
   The original staging name/content remains intact.
5. Verify final object's actual hash/length, sync it and both objects/staging
   directories, then commit the ready blob, pinned upload and persistent pin.
6. Only afterward remove original/redundant temporary names and sync staging.
   Cleanup errors are surfaced as StorageIo. The durable pinned fact is still
   visible through lookup; a same-kind finish can safely retry cleanup.

POSIX rename is **not** claimed to provide atomic no-replace semantics. The
target-check/rename guarantee depends on the pre-existing exclusive owner,
private 0700 root and serialized business write transaction excluding every
other managed writer. Arbitrary filesystem writes by rogue same-UID native code
are outside that existing ownership boundary. Model/user input never chooses
these paths. This ownership assumption was explicitly reviewed before editing.

Publication temporaries stay outside objects, whose filenames remain canonical
64-hex digests. Temporary names derive from a durable upload ID. Explicit
abort/reconciliation cleans both original and temporary only for the matching
proven terminal/redundant upload state. Unknown uploads retain their temporary;
pending/unknown business outcomes continue protecting pins and blobs. No timer
expiry, standalone database or new dependency was added.

## Host evidence after replacement

`cargo test --offline --locked -p muyon-core --lib blobs::tests -- --nocapture`:
**14 passed**, exit 0. This includes 12 real storage/publication SIGKILL windows
plus two actual PaperCreate SIGKILL windows: **14 separate OS process deaths**,
each confirmed signal 9 and inspected using an independent SQLite connection.

New crash cases assert: original staging survives; fresh copy starts at zero
bytes; a synced first chunk is exactly 65,536 bytes and shorter than the full
70 KiB source; durable pre-rename copy is complete; rename leaves independent
original/object inodes. Explicit old-owner recovery removes owned temporaries,
and the existing record/history/reference/receipt and unknown/pin checks pass.

Focused new tests:

- `corrupt_existing_object_and_dangling_symlink_are_never_replaced`: target
  inode and bytes/symlink remain unchanged; no pin is issued.
- `partial_publication_copy_is_not_reused_and_unknown_uploads_are_not_cleaned`:
  partial copy is refused without mutation; old copying upload cleanup removes
  exactly both names, while unknown preserves both.
- `rename_then_failed_pin_commit_can_retry_existing_target_without_overwrite`:
  controlled SQL failure after rename retains original stage; same-owner retry
  validates and reuses the same target inode and commits one pin.
- `failed_ledger_after_solidification_keeps_staging_and_object_independent`:
  appending to original staging after rollback cannot alter object content.

Further executed checks: archive **13/13**, blob integration **8/8**, research
integration **15/15**, all exit 0; targeted strict Clippy
`cargo clippy --offline --locked -p muyon-core --lib --test blobs -- -D warnings`
exit 0. Independent reviewer separately ran whole library **15/15**, archive
**13/13**, blobs **8/8**, plus strict Clippy, and approved only Rust repair/design
and host regression. Review logs are
`/private/tmp/muyon-review-copy-rename-tests.log` and
`/private/tmp/muyon-review-copy-rename-clippy.log`.

Frozen repaired `src/blobs.rs` SHA-256:
`d07a8d557155315770afc310ccaae557340adb1c1b6b4df3b25ef61ead9bb470`.
Earlier hashes and hard-link mutation results in VERIFICATION.md are historical
and explicitly superseded by this copy/rename identity and crash evidence.

The parent owns native/Gradle build, APK install and API26 execution. Host
evidence and design review do not claim device acceptance; the original device
RED remains until the rebuilt product passes those exact PDF/ZIP cases.
