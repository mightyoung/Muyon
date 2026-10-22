# Reader tail fix and authenticated snapshot stream

## Immutable sources for separate verification

| Purpose | Branch / fixed source |
| --- | --- |
| Original rejected Reader | `ff3cc928311afc12bee3205f28b662c6b7499b34` |
| Original actual evidence | `4fae7905fd40a6a6234699c6f00a1c1555adab66` on task/document-core-verification-20261022 |
| Tail regressions, before fix | `7a72a8290f821eb015d34421e09c24ac9ca70cdc` |
| Pure final tail fix, no performance delta | task/document-reader-tail-fix-20261022 @ `fec40dc8aeec350ef6d77005d4efb79fd186eb7a` |
| Stream cost regression before optimization | `7a4514350ec7372e06bbd2daab8e4871fc653a5b` |
| Final tail + snapshot source | task/document-core-contracts-20261022 @ `2e71384e808ecbe5bb010d05e87094e33e9cd3fd` |

The pure tail branch starts exactly at ff3cc and cherry-picks only two regression
tests plus security fixes. It leaves the original O(n²) stream unchanged so its
security acceptance can finish independently. Main/develop, FFI, lib.rs and other
owners' source modules remain untouched. No branch rewrite or force push.

## Actual old-source evidence, not new-source acceptance

Read the immutable READER-RUST-VERIFICATION.md and original probe outputs. On
ff3cc, Reader13 and full package266 executions passed, but independent one-shot
and EOF cleanup probes actually returned Ok with 59 bytes after grant expiry and
pin deletion; both are genuine RED. The other four independent invalidation probes
passed. The initial private-API probe compile failure executed no tests and is not
counted as RED. Four owned files also failed format. None of these results close
new-source acceptance. Original stdout/stderr are copied unchanged to
reader-evidence/original-cleanup-red-*; origin and hashes are in 08 manifest.

## Final cleanup behavior

One-shot checks the active view before cleanup, completes pin deletion/COMMIT,
then starts a new read-only transaction and checks the exact original access and
complete current metadata before returning the callback value. A cleanup-triggered
expiry/revocation persists but delivery is refused; the deleted pin is not required
for this final check. The extra post-COMMIT check also covers time spent waiting
for the write commit itself. An unknown commit withholds output.

EOF first completes explicit cleanup, then uses the same exact original access,
metadata and original idle/absolute timestamps for a fresh delivery check. Cleanup
failure still withholds the chunk, retains the owned session solely for cleanup
retry and poisons reads/opens. The two trigger tests independently cover one-shot
and EOF. This final flow supersedes the intermediate fdcdd48e note about one-shot
checking before its write commit; its source/evidence remain immutable.

## Why the former stream is too expensive

At 30 MiB with 64 KiB chunks there are 480 chunks. Two whole-file hashes per chunk
consume 960 source passes = 28,800 MiB hashed, excluding open work. Finishing those
passes in the 30-second session ceiling would require 960 MiB/s of hashing alone.
This is arithmetic from the old control flow, not measured mobile throughput.
No claim that a 30 MiB source completes on Android has been made or established.

## New integrity and freshness model

At open, the real reader still verifies the actual immutable blob identity, live
lease and exact current authorization. The facade copies bounded real bytes into
a private `Box<[u8]>`, hashes those actual bytes against the canonical blob and
checks the held FD's metadata stamp on both sides of preparation. Only this
authenticated immutable memory becomes the session's sequential source.

Each chunk copies a slice from that private snapshot. It still checks exact
persisted scope/project/head/grant generation/epoch/expiry and actual reader pin
before and after preparation of the slice, in the same owner transaction. It also
compares dev/inode/length/link count/mtime/ctime of the held FD against the open
stamp. An observed change invalidates the session. Idle15s, absolute30s, source
30MiB and eight-session limits are unchanged. The cleanup-tail fix stays in force.

We do not assume disk bytes or timestamps are immutable. Stamps provide observed
change detection, not cryptographic attestation. Even if metadata were spoofed,
no subsequent disk read can inject altered bytes: delivered memory was authenticated
at open and has no public mutation/deserialization path. This is a snapshot of the
exact content-addressed revision, not a promise that all backing-file bytes remain
globally unmodified at every instant. Authorization and revision are fresh on each
use; disk changes that are unobserved do not authorize delivering new disk content.

The explicit `is_current` retains its full held-file hash check. Calling it before
every chunk would reintroduce repeated full-file work; chunk already performs its
own fresh authorization and integrity checks. FFI/host must not treat is_current as
a mandatory per-chunk preflight. Its actual lifecycle polling cost remains to be
measured. The bounded 2 MiB one-shot view retains its separate whole-file checks.
No engine eligibility, format parsing, UTF-8 assumption, historical read or model
authority is inferred from these raw bytes.

Snapshot payload is capped at **64 MiB across one host**, checked before allocating
or pinning a new snapshot. Failed-cleanup sessions remain in the registry and
consume budget. FD buffers, allocator overhead and bounded chunk buffers add to
RSS; this is a payload budget, not a process-memory guarantee. Two 30 MiB sessions
fit, a third is refused even though the eight-session count is not exhausted.
This trades bounded additional memory for linear preparation and streaming cost.

## New tests and honest measurement boundary

The Reader suite now has 17 authored tests (not executed here). The two tail tests
are separate from the original13. New performance tests:

- create an actual original 30 MiB source, count bytes actually passed through
  `hash_file` and snapshot hashing, read all 480 chunks and compare every byte;
  assert each chunk hashes zero whole-source bytes and each open hashes at most
  4n; check second 30 MiB admission and third denial before pin creation;
- modify the real backing file and deliberately resample its stamp via a cfg(test)
  helper, proving chunks still return original authenticated bytes, never mutated
  bytes; explicit is_current then detects the real full-file hash mismatch.

The test counters increment at actual hash-update/digest work, are thread-local
and cfg(test) only. Static dataflow predicts about 3n hashed bytes per open (two
file verifications plus the snapshot hash), with no whole-file hashing on the
chunk path. Those are predictions and assertions, not observed measurements.
The pre-optimization regression source fails at the first repeated whole-file
chunk hash if executed; local attempts remained NOT_RUN127, not actual RED.

Run the `thirty_mib_stream_hash_cost` test with `--nocapture` to preserve actual
source/open/backup-open/stream byte counters. It does not disable grant expiry or
session limits to make a slow machine pass. Actual timing, mobile memory pressure,
Android/PFD behavior and the host consumer call pattern remain unverified.

## Required actual verification

reader-evidence/07-final-cleanup-and-stream-verification.log records targeted
cleanup, cost, Reader suite, complete core and scoped rustfmt attempts: all
NOT_RUN127 because cargo/rustfmt are absent. `git diff --check` exited0. Separate
static reviewer confirmed both final cleanup flow and snapshot trust/budget model,
with no confirmed new blocker; it did not compile or measure anything.

First rerun the old public cleanup probes and full package against pure fec40dc8,
then independently compile/run final 2e71384e, the cost counter, all Reader/core
tests and scoped format. Original 266 is not the new full-core result; no test
counts are summed across binaries or prior sources. The old four-file format
failure is preserved and new format acceptance is pending. No engine, paid action,
real model/search, credential change, user file or old unknown retry occurred.

Sealing note: full staged diff-check exits2 solely for the original copied probe
stdout's final blank line. Its bytes/hash are intentionally preserved. Excluding
that exact raw log, staged diff-check exits0. This whitespace fact is separate
from the old four source-format failures and does not imply new rustfmt passed.
