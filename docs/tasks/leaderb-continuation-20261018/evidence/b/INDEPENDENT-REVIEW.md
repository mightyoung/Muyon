# Independent Hy candidate review

Candidate: `379b1a6d8d5a5830fb3a74924fd5c41cfb234e1c` in `/workspace/leaderb-b`, based on F2 `3f1be180bb009a91e659c113ba5b1916e5360332`. Reviewer made no source edits, branch changes, cherry-picks, pushes or merges.

Fresh verification: cargo locked/offline full suite **24 passed, zero failed**, including child-process crash/reopen and SQLite contention tests; cargo fmt check exit0; fixture verifier exit0 (writer20/diff16 consistency, deterministic regeneration, four deliberately invalid mutations rejected); authored candidate-vs-F2 whitespace check exit0. Full commands, exits, source SHA256 before/after and log digests are in `candidate-review.json`, with logs `candidate-review-0.log` through `candidate-review-7.log`. HEAD and source hashes unchanged after execution; worktree clean.

Crate tree equals original tested e85bc003: `3ae05bff435b20d320570a021702b72fc7dd9201`. Fixture tree equals original tested e85bc003: `de87f264180a4ec3d3a4acd49c9912a62317fcc6`. All 102 paths changed relative to F2 have blob identities exactly equal to archive `07397c65bdd100f6e316573591cc1e6d1ea0a0a3`. Candidate changes only declared Hy docs/evidence and two isolated experiment directories; no existing runtime/checker/workflow/Android/Dart changed.

Toolchain restored under `/workspace/leaderb-tools/{cargo,rustup}` with Rust stable 1.99.1, Cargo1.99.1, rustfmt and existing Debian cc14.2.0. Installation logs: `rustup-download.log`, `rustup-install.log`, `rustfmt-install.log`. Explicit locked dependency fetch succeeded before offline tests. Build output was isolated at `/workspace/leaderb-build/b-review`.

No new blocking defect identified in declared isolated scope. Atomic tombstone/jobs/receipt transaction; complete payload digest conflict handling; attempt/lease conditional acknowledgements; independent current member/source gates and byte digests; shared BEGIN IMMEDIATE consume/revoke boundary; and structured UTF8 redaction remain intact. Final tombstone regression executes among the 24 tests.

Archive-wide whitespace check genuinely returns exit2 on preserved raw logs; output retained in `candidate-archive-raw-whitespace.log`. Authored diff check excludes only raw evidence *.log and passes; this is not represented as globally whitespace-clean. All original evidence caveats remain, including initial overwritten RED output and missing complete early GREEN snapshot.

Limits: one scope/use, one direct source identity lineage, synthetic vector/cache rows, trusted expiry flags, caller retry clock and logical SQLite cleanup. Production permission authority, recursive/multisource lineage, actual sink inventory/adapters, expiry scheduler, final external-send fencing, domain-external ForgettingReceipt/restore, UI and secure physical erasure remain unimplemented. Writer/diff fixture checks are consistency only: model_calls=0, DUT_runs=0, benefits UNVERIFIED. REMORY efficacy gates remain; RSI stays closed.

The earlier path compatibility comparison used F2 relative to old base a3ee7df and Hy task paths, plus the separate develop-to-old-base diff. It was not a claim that full develop contained F2. Parent subsequently performed actual ordered cherry-picks; reviewer independently verified the resulting candidate blobs and tested the fixed candidate above.

I04 legacy task.db→HTTP→original-state reopen remains denied before execution and was never attempted here. PR86/develop hold remains; this report only supports the isolated Hy candidate and does not authorize integration past that hold.
