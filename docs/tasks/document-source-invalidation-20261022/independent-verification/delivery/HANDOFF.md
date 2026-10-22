# Atomic document source invalidation handoff

Fixed implementation patch commit: `b9b18149604bb96d4c3c531e2283764ac4030015`.
Branch: `task/document-source-invalidation-20261022`.
Baseline: `b4940ddc1600acced5e268053450b48395df93f6`.
Required real Artifacts/Evidence owner dependency: `0e85c6e98c4e32efc8008092e480626f342a701d`.
This delivery packages an **unapplied** implementation patch, not a production-integrated or compiled feature. No Artifacts owner source, root lib.rs, Reader behavior, transaction-owner source, or B branch was modified.

## Integration and exact verification tree

`CORE-SOURCE-INVALIDATION.patch` adds two documents modules and changes only documents/mod.rs and documents/storage.rs. SHA256: `b6ddc8a034e318ef02b641044c19b8b41497bd64a4b3622ec64b148cbf7833a9`.
`UNAPPLIED-B-HARNESS-DEPENDENCIES.patch` supplies only actual Artifacts/Evidence module composition for the two same-source harnesses; B owns applying it. No fake hook, global allow, or library export is introduced.

To prepare a NEW disposable validation tree:

```sh
python3 docs/tasks/document-source-invalidation-20261022/prepare_validation.py /tmp/muyon-source-invalidation-validation-new
```

The script uses the exact baseline and dependency blobs, applies both patches, checks the four resulting core file hashes, and records the complete dependency/core/harness manifest. It rejects an existing destination. It installs nothing and runs no engine or external service. A prepared tree already exists at `/tmp/muyon-source-invalidation-validation`; its copied manifest is `prepared-source-manifest.json`. Root lib.rs is byte-identical to B baseline. B must integrate the actual owner dependency and module composition before this core patch; the original core branch deliberately does not reference missing modules.

## Behavior

Head publication/COPY, grant issue/update, and revoke call the real owner invalidation method in their original SQLite transaction. Replacement parses the old grant DocumentRef before overwrite and processes both old/new identities. Hook/notification errors propagate, rolling back the original mutation. New tests use real resolver proofs and synthetic Text source bytes.

An uninitialized source namespace remains compatible, including legacy six-table databases. Present malformed namespace/schema, or a missing source table after the notification marker was installed, fails closed. The owner validates source schema; core does not duplicate source permission truth.

Affected project/actor/object IDs enter the same-database notification table atomically. Trusted Host calls `pending_document_source_notifications_trusted(after, limit)` only after commit, publishes each local invalidation through Runtime, then calls `ack_document_source_notifications_trusted(events)`. Exact-generation acknowledgements cannot erase a later event; uncertain delivery stays pending. Acknowledged rows retain generations to avoid ABA. This metadata queue grants no read authority and does not replace live checks.

**Runtime/FFI consumption is not implemented here.** Notification delivery cannot be claimed until its owner wires the post-commit poll/deliver/ack path. No real message was sent. Source hook returns all affected objects in a Vec: 256-row pagination is not a global mutation-memory bound. Queue cardinality follows distinct objects; no total disk quota is claimed.

## Verification

`verification.log` preserves exact commands and outcomes on the dependency-complete prepared tree. Focused 12-test source suite, workspace tests, and scoped rustfmt are **NOT_RUN (127: cargo/rustfmt absent)**. No actual RED/GREEN or new pass count is claimed. These new tests include schema compatibility/corruption, atomic rollback and precommit visibility, old grant target replacement, preserved manual fields, stale acknowledgements, 258 authentic bindings/pagination, and foreign transaction/limit rejection.

Both patches pass `git apply --check` on fixed B baseline; core patch also passes against the current Reader owner tree `4c9072af48d7a6eceb9abb70594b03ab4bc412be`. Diff whitespace check exits 0; this does not substitute for rustfmt. The prepared source hashes match `patch-manifest.json`. Independent static review is archived separately. Baseline strict-gate issues, including the three non-Drop drop(g) expressions, remain B-owned and were not touched.

Presentation pureformat `dfa63451c0d65417b425f5bf1e92a3b43e0b6052` was separately recovered cleanly on the original owner branch as `4c9072af48d7a6eceb9abb70594b03ab4bc412be`; parent runtime evidence `c68f1f1c59e859b6c87996f45cddae5c2baa8379` applies to that presentation work, not this new hook patch.

Remaining gates: independent Rust compilation/tests/fmt on the manifest-fixed source, B dependency/patch integration, and Host/Runtime post-commit delivery/ack adapter. There was no denied or uncertain write in this slice.
