# Preserved non-executed verification

Initial test-first.log and author.log exit 127: cargo not installed.
They are NOT_RUN, not observed behavioral RED or PASS. Initial tests were written
before implementation but could only be executed after the known toolchain was
configured; this does not constitute a fully observed initial TDD red/green cycle.

first-compiler-run.log exit 101: sha2 0.11 digest lacked LowerHex formatting in
new code/test, and the environment lacked libsqlite3.so linker alias. Both were
corrected without touching owner files or changing dependency versions.

debug-red.log exit 101: real regression reproduction, 7 pass / 1 fail, plaintext
Debug exposure. Followed by passing author and independent runs after correction.

workspace.log exit 101: offline workspace run could not fetch locked anyhow
1.0.104. cargo fetch --locked fetched repository-pinned dependencies into /tmp;
workspace-after-fetch.log and workspace-final.log preserve actual later runs.

NOT_RUN: Android build/device UI, PDF text extraction/OCR/geometry runtime,
persistent import/task receipt integration, production host adapter and module
export, real model/search requests. Real external calls were not authorized and
were not made. Original two unknown operations and reservations were untouched.
No main/develop updates, force push, deletion, deployment, payment configuration,
credential changes, user real-file imports or engine-isolation HOLD bypass.

## Follow-up failures retained and subsequently resolved

text-format-red.log: real behavioral failure, previous processor accepted
Unknown as UTF8. Fixed with core Text and strict format/bytes checks.
store-test-first.log: Python harness initially mishandled a workspace dependency
string. store-test-first-retry.log: copied lock required pruning unused workspace
packages. Both corrected; runner now resolves offline then refuses any version/
source/checksum outside the fixed repository lock.
store-test-first-source.log: test-first compilation failed on missing store module.
store-first-compile.log: nine tests compiled but failed because the old fixed core
had no Text variant. New core aec085fa was consumed, not manually patched.
store-full-core-final.log: module split exposed missing imports (21 compile errors).
Fixed and all actual Rust reruns passed. These are not disguised as behavioral
TDD RED cases; the Unknown-format negative is an observed behavioral RED/GREEN.

Reviewer also observed an ordinary root import error before pure source splitting:
lib.rs intentionally lacked pub mod evidence. The adapter's full same-crate
harness is a real-source verification seam, not a production export. Parent B
must apply the core combination export patch; no ownership bypass was attempted.

Superseded initial status: Text is now consumed from fixed core and the real
BusinessStore adapter is implemented and tested, rather than only a host trait.
Still NOT_RUN/pending: actual export + Service/FFI/UI invocation, Android/device,
persistent import/saved receipt integration, ResearchIndex, PDF/OCR engine.
