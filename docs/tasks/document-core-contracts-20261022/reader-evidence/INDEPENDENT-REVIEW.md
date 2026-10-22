# Independent static review

Reviewer `/root/document_contract_review`, read-only, no source edits, no tool
installation or cargo/rustfmt execution.

Reviewed 477835f0, subsequent 6dca6927 and final production 09099780:
no statically confirmed borrow/type error, authorization bypass or cleanup
blocker. Reader pin creation is in the real authorization transaction; chunk
validation includes actual file hash and tail grant. EOF cleanup failure withholds
the chunk, retains the actual reader and poisons the registry. One-shot pin creation
and deletion share one transaction, so callback/tail/cleanup errors roll it back.
Generation/epoch/expiry/project-deletion tests are independent. Blob byte_length
projection is bounded before allocation and its oversized-ledger test rejects
without a new pin.

Final test-only `b3592e9bc1b0d9c3c52800e5ec1f566e36b8a297` review: no obvious
static error or confounded coverage in the post-pin grant failure and deferred FK
COMMIT rejection tests. The latter accurately does not claim an already-durable
unknown-response crash. Explicit cleanup retry was already covered. Static review
passed; runtime acceptance is NOT_RUN pending the Rust environment.

Separately reviewed `8f24e8f5384489e2ee7d86b8494ee1ca47c0cd8b` against B's
82169330: exactly one repeat.take-to-repeat_n test expression, unchanged padding
and assertions, no Reader/candidate delta. Static review passed, not a Clippy pass.

## Later independent finding and actual old-source rejection

The original static review missed the cleanup-to-delivery authority window.
Independent real evidence 4fae7905fd40a6a6234699c6f00a1c1555adab66 shows two
cleanup probes returning59bytes after expiry (actual RED), despite Reader13/core266
passing on old ff3cc. Original format also failed. The earlier static conclusion
does not close that runtime-confirmed finding.

Read-only reviewer confirmed intermediate fdcdd48e closes the trigger counterexample
statically; later final 2e71384e improves one-shot to commit cleanup first then check
accurate metadata/access in a fresh read-only transaction, covering COMMIT wait
and preserving committed revocation. EOF rechecks after cleanup with original
session times. No new blocking issue found, but no actual GREEN was run.

Performance review of 1dc2ea68 against fdcdd48e: actual source bytes are hashed
against canonical blob before a private immutable Box enters the session. Chunk
copies cannot receive later disk mutations even when stamp is spoofed. Real
grant/head/lease and stamp checks remain before/after chunks; payload budget64MiB
is checked before allocation/pin; previous30MiB/8session/15s/30s limits remain.
Actual hash byte counters cover file and snapshot work; static expected open~3n,
chunk0 whole-file hash, with cost and spoofed-stamp regressions. Explicit
is_current and bounded one-shot retain full-file hash. No confirmed static
borrow/type or trust-model blocker found; no measured runtime/mobile benefit.

Final read-only confirmation: pure tail branch
fec40dc8aeec350ef6d77005d4efb79fd186eb7a contains only the Reader tail fix, two
regressions and NOT_RUN log over original ff3cc; no performance delta. It can be
verified independently. Reviewer made no edits or tool installations and did not
execute Rust. Static review passed; actual fixed-source acceptance remains HOLD.
