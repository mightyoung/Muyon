# NULL projection repair — fixed source awaiting fresh Rust verification

Original provider7ca2bd4e9edf9cd0952ce784d3f85561583537db was **behaviorally broken**:
first resolve projected NULL archive as "oversize", record() rejected the new draft,
and the transaction rolled back. Prior Python SQL smoke did not exercise the actual
initial projection and prior static review missed this defect. Neither is Rust PASS.

## Preserved authoritative RED

Imported byte-for-byte from fixed evidence commit
fda22f1876393b390e73591ffbf5991e686c8ef6:
INDEPENDENT-RUST-VERIFICATION.md and independent-verification/ (including original
stdout/stderr, JUnit derived from actual libtest, manifest and SHA256SUMS).
Checksum verification passes. No original failure expectation or log was rewritten.

- Provider15 executed:1 passed,14 failed (all first resolve corrupt).
- Partial core118 executed:104 passed,14 failed, later suites NOT_RUN. The same14
  failures are included in both runs, not28 independent failures or full core PASS.
- FFI: BLOCKED before compilation, missing offline anyhow1.0.104 cache.
- Scoped formatter: FAIL, all3 files had differences.

The separate verification-only module export was1e81e19c170bf65aa01923b082a2175f5009490c.
This task still does not modify the sole owner's core lib.rs.

## Repair and regression scope

record() explicitly preserves SQL NULL before archive type/size checks. Missing
archive+digest is valid only at stored revision0. Stored revision>0 still requires
both a valid canonical archive and its exact digest; NULL is not a reset/migration.

Archive projection requires TEXT and <=65536 bytes, measured as LENGTH(CAST AS BLOB),
not characters or SQLite's NUL-terminated text length. BLOB storage is refused before
the Rust SQLite wrapper can coerce it to text. Oversized and invalid storage map to
non-hex sentinels and fail closed. Current and original receipt digest projections
require TEXT and exactly64 bytes. Original receipt_json requires TEXT <=4096 bytes.
No DDL, ownership, CAS, identity, ledger or public interface change.

Four new Rust regressions (19 provider tests total, plus the existing FFI test):
empty resolve/read/re-resolve/restart with NULL; malformed/over-limit/BLOB/numeric/NUL
archive storage and saved-record NULL rejection; BLOB/oversize original receipt and
BLOB original digest; valid large canonical UTF8 archive roundtrip. Prior tests remain.

SQL regression was strengthened BEFORE implementation to assert the actual bounded
projection at initial resolve. Its real failure is retained in evidence/null-projection-red.log.
The repaired source-extracted SQL checks pass for NULL, exact65536/65537 archive
projection, BLOB, embedded NUL, multibyte bytes, exact64 digest, exact4096/4097 receipt,
plus previous transaction/CAS/restart checks. See evidence/null-projection-green-sql.log.
This is SQL verification only, not Rust behavior or product acceptance.

The original formatter's exact proposed whitespace changes were replayed for the3
owned files from its preserved stdout, followed by manually formatted new tests.
No current rustfmt PASS is claimed. Independent read-only re-review confirmed the
NULL/type/byte fix, found one original-digest projection gap, and rechecked its repair;
no outstanding static findings. Its SQL checks passed; Rust remained NOT_RUN.

## Current blocking status

Repaired-source Rust compilation/tests, fresh formatter check, UniFFI, canonical
Kotlin and Android remain **NOT_RUN in this environment**. cargo/rustc/rustfmt are
absent, and the verifier's /tmp/muyon-rust/bin, /tmp/muyon-cargo and native/cache
directories do not exist here. We do not assume shared task files or install tools.
This is an environment/dependency blocker, not a denied action. Parent/independent
verifier must run fresh tests against the new fixed SHA plus authorized core export.
Old14 RED remain authoritative history; this repair is not yet verified GREEN.
Overall HOLD/can_save remains disabled pending actual Rust and host integration checks.
