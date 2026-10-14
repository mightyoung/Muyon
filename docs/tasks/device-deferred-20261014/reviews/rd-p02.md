# RD-P02 independent fixed-source review

Verdict: **C0 for bounded inclusion as a provisional host experiment**. No blocker found within its expressly limited synthetic/in-memory scope. This is not product contract freeze, runtime acceptance or production recovery approval.

Fixed source / remote branch / author HEAD all match `44b54efd7ebcf2f3221f8509ad331ad98a42e779` (`task/device-deferred-rust-recovery-20261014`). Source exported with git archive to `/tmp/rd-p02-independent-review-20261014`. Independent build target `/tmp/rd-p02-independent-target`; existing Rust1.99.0 only, no installations/licenses/device/model actions. Author worktree read-only, clean. Changed paths versus `b17ac548f7a8d2d6151cbdaf6af527722c67ee50` are only the isolated rust-recovery experiment and RD-P02 task document (9 files). Every changed archived file, including restored source, compared byte-for-byte against fixed git objects; see fixed-source-check.json.

Read recovery-minimal-contract.md, task document, crate source/tests, mutation implementation and evidence/README. No fixture ID/expected-output input to production reducer. `expected` in reconcile is the caller's original Identity (compared with receipt), not a fixture golden lookup. No source reads the oracle/proof files. Tests state concrete inputs and independent assertions; three removed guards change behavior and fail named assertions. verification-evidence.json is retrospective metadata, not driving reducer branches.

## Fresh execution

Command base:

```
CARGO_HOME=/tmp/muyon-spike01-toolchain/cargo
RUSTUP_HOME=/tmp/muyon-spike01-toolchain/rustup
CARGO_TARGET_DIR=/tmp/rd-p02-independent-target
/tmp/muyon-spike01-toolchain/cargo/bin/cargo +1.99.0 test --offline --locked --manifest-path /tmp/rd-p02-independent-review-20261014/experiments/redesign/device-deferred/rust-recovery/Cargo.toml
```

Fresh full suite: exit0, **19 passed / 0 failed / 0 ignored**. Independent inverse mutations in the archive (not author worktree), same --offline --locked base plus `TEST -- --exact`:

| Mutation | Expected named assertion | Actual |
| --- | --- | --- |
| Remove exact domain rejection | all_three_domain_fields_are_required | exit101, 1 failed, equality assertion |
| Reconnect clears receipts | epoch_is_only_display_fence | exit101, 1 failed, equality assertion |
| New intent removes old unknown | unknown_survives_reconnect_and_new_intent | exit101, 1 failed, equality assertion |

Restored original source bytes in finally; source SHA256 `8ed5f0b6c28944d739c4f206f8708f9ec69c7c1c7af5d1c252fc96514864e0db` matches fixed source and author evidence. Restored full suite exit0, **19 passed / 0 failed / 0 ignored**. Raw independent logs and machine counts/hashes are verification.json and *.log in this report directory. Author's initial RED/D03a24 regression are historical claims, not re-executed here and not added to independent counts.

## Semantics checked and bounds

- Domain equality checks store/scope/stream before watermarks, with seq as event identity within that domain. Known applied/buffered identity payload conflicts are rejected without overwriting the existing payload. Dedup history is in memory, unbounded in this lab; caller's initial checkpoint has no previous payload evidence. Thus fork authentication or complete persisted history coverage is not proven.
- Gaps buffer at most the configured event count and request Pull from committed cursor. Overflow enters snapshot-required and blocks new incremental application until reconnect/resync. Filling a gap drains consecutive events; committed pair never advances merely because received/applied do. Reconnect restores committed projection+cursor and drops uncommitted dedup/buffer state for replay.
- commit pairs projection/cursor in one in-memory method. It is not a physical durable transaction, crash test, fsync or ACK implementation. Task and README retain that qualification. Snapshot parsing/installation, legitimate filtered advance proof, byte budgets and authority narrowing are deferred.
- Epoch equality controls display only; reconcile has no epoch predicate. Complete original intent/action/attempt/scope/parameter equality plus exact supplied ledger receipt/effect match is required, conflicting known receipt ID cannot overwrite a previous effect, and no receipt body is displayed. Ledger is caller-injected synthetic data, not authenticated source/permission/digest evidence.
- Unknown survives reconnect and synthetic new intent registration. There is no executor/dispatch API or network effect, so reconnect cannot resubmit business; this is structural lab evidence, not tested production exactly-once behavior.
- user_new_intent requires an existing unknown, nonempty synthetic instruction seam, distinct unused intent, matching scope/action/parameters; it registers only. User instruction provenance, real authority, capabilities, CAS and original/new durable linkage remain future gates. A nonempty string is deliberately not claimed to be a production authorization token.

Conditions on inclusion: keep module unpublished/isolated and its provisional/memory/synthetic notices; do not wire public mutable State to untrusted product clients as an authority API, count fixtures as migrated, or label memory commit/Verified/NewIntent as real persistence/business success. Production adapters must add authenticated ledger/current permissions, durable atomic checkpoint and dedup, bounded bytes/history, explicit conflict/resync handling and M03's unique representation.

Android actual load **NOT_RUN**. M03 **blocked_contract**. Device/release gates remain required later. No merge/push/commit of review report, no develop/main changes, no old OC audit rerun.
