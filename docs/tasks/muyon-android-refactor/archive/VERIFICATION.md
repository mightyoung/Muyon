# A01 ZIP32 metadata reader — implementation evidence

## Scope and API

`crates/muyon-core/src/archive.rs` adds no dependency. `parse_archive(&[u8])`
returns `ArchiveManifest { archive_length, archive_digest, entries }`, where
entries contain regular members only. `to_contract_entries(&FileSource)` binds
the exact archive SHA-256 and byte length before converting to the existing
contract type. It does not authenticate a caller's file lease.

`DecodedEntryValidator::new(&ArchiveMember)` / `update(&[u8])` / `finish()`
validates the actual decoded stream against the CEN expected expanded length
and CRC32, with a sticky failure on overrun. The platform must supply the exact
validated compressed range from the same immutable source, count compressed
reads, feed every decoded byte, and successfully finish before publishing.
The reader does not decompress and metadata success does not certify contents.

Profile: single-disk ZIP32, STORED/DEFLATED, extraction version 10/20
(DEFLATED requires 20), creator DOS/UNIX. UTF-8 EFS names and unflagged ASCII are
accepted; other legacy encodings are unsupported. Flags are limited to EFS,
bit 3 descriptor, and DEFLATE option bits. Signed and unsigned 32-bit descriptors
are accepted; local CRC/sizes can be zero or match CEN when bit 3 is set.
Only structurally checked timestamp 0x5455 and UID/GID 0x7875 extras are allowed;
all ownership/timestamp values remain inert. ZIP64, encryption, multipart,
unknown methods/flags/extra fields/creators are refused.

Limits: compressed archive <=150 MiB, aggregate declared expanded size <=150
MiB, individual expanded member <=30 MiB, <=10,000 entries including directory
records, UTF-8 filename <=1,024 bytes. Path components reject absolute paths,
empty segments, dot/parent traversal, backslashes, colons and controls; NFC
aliases, duplicate names and a regular-file ancestor are rejected. Original
names are retained. All accepted creator types are inspected for UNIX special
file bits, including archive 4.0.9's DOS creator plus UNIX permissions.
Directory type/name mismatches are refused. Header, filename, flags, method,
DOS timestamp, sizes and CRC must agree between CEN and LOC as applicable.

Physical local extents must be contiguous and nonoverlapping from offset zero
through CEN. This intentionally refuses self-extracting prefixes, padding,
unindexed local records and digital signature records, even where a broader
ZIP implementation might support them. CEN ends exactly at EOCD, which ends
at EOF including its comment. Directory entries are validated but never
presented as readable regular contract entries.

Format reference: [PKWARE APPNOTE 6.3.10](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT),
sections 4.3.7–4.3.16 and 4.4. Layout and descriptor support follow the documented
records; the accepted profile above is intentionally narrower than all ZIP.

## Executed verification (2026-10-20)

Working directory: `/private/tmp/muyon-android-refactor-20261020`.

- `python3 crates/muyon-core/tests/fixtures/archive/generate.py`: exit 0;
  Python stdlib ZIP_STORED/DEFLATED and nonseekable descriptor production,
  directory/Chinese filenames, malicious path/type/overlap/extra/quota fixtures.
  Duplicate-name fixture intentionally emits Python's duplicate warning.
- From `crates`: `cargo test --offline --locked -p muyon-core --test archive`:
  **13 passed**, exit 0 after restoration of guard mutations.
- Controlled mutation: omit parent traversal check, allow symlink UNIX type,
  and omit range contiguity/overlap check. With those three mutations,
  `cargo test --offline --locked -p muyon-core --test archive guard`:
  **overlap_guard, traversal_guard, symlink_guard all FAILED**, exit 101.
  All mutations were restored; full archive suite then passed 13/13.
- `rustfmt --check --edition 2021 crates/muyon-core/src/archive.rs crates/muyon-core/tests/archive.rs`:
  exit 0. `git diff --check`: exit 0.
- From `crates`: `cargo clippy --offline --locked -p muyon-core --test archive -- -D warnings`:
  exit 0, no warnings.

Actual Dart encoder run used the already-installed SDK binary (the Flutter
wrapper attempted a forbidden SDK engine-stamp write). No SDK/config was changed:

```sh
python3 docs/tasks/muyon-android-refactor/archive/generate-dart-config.py /tmp/muyon-a01-packages.json
/Users/muyi/development/flutter/bin/cache/dart-sdk/bin/dart --packages=/tmp/muyon-a01-packages.json docs/tasks/muyon-android-refactor/archive/archive409.dart crates/muyon-core/tests/fixtures/archive/archive409.zip
```

Result: `archive 4.0.9 round-trip: 3 entries, 434 bytes`, exit 0. The script uses
the research exporter's `ArchiveFile` + `ZipEncoder` construction (with a fixed
fixture modification timestamp) and
actually decodes with `verify: true`, checking every resulting content against
the input. The fixed bytes are accepted by the Rust reader and expected CRC/
length validators. Cache config helper resolves already-installed versions only;
it never installs dependencies. These are encoder compatibility and metadata
evidence, not a full `ResearchPackage` service export/import acceptance result.

## Remaining gates

API26 platform bounded compressed/decompressed streams, revoked-URI/private
copy semantics, cancellation and read leases are **NOT_RUN** in this lane.
Full existing research service export/import with attachment lifecycle is
**NOT_RUN**. Independent security/code review and downstream integration remain
open. A01 metadata tests do not close U02a/R02/FS01 or overall Android delivery.
