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
