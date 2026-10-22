# Independent review: private pending-journal context

Reviewed branch `task/artifacts-journal-context-20261022`, base
`0e85c6e98c4e32efc8008092e480626f342a701d`, and its working-tree production diff.
Scope is the two owned source files named below. No production edits or commits
were made by this reviewer. No confirmed correctness, authorization, privacy or
compilation issue was found in this grouping-only refactor.

## Parameter and control-flow equivalence

- `PendingJournal` borrows the same frozen intent, project ID, actor ID, binding
  digest and request JSON. It owns no authority or mutable request and adds no
  serialization or external API. Its fields and target are visible only inside
  the artifacts parent module. Rust compilation verifies the shared borrow
  lifetime and the local String-to-str coercions.
- The artifact caller selects `Artifact` and passes the original `intent`,
  `access.project_id()?`, `&access.actor_id`, `digest`, `json`. Removing its ignored
  empty object-ID placeholder changes no SQL argument.
- The local caller selects `Local { object_id: &a.object.object_id }` and passes
  the original `intent`, project, actor, `&digest`, `&json`. The object ID remains
  the final parameter of the local INSERT; the type now requires it for Local.
- Both INSERT strings are byte-for-byte unchanged (independently asserted against
  the fixed base). Their parameter order remains intent/project/actor/digest/JSON,
  followed only for Local by object ID. No SQL schema or row-state change exists.
- Both calls remain in their original transaction locations, after the original
  authorization/validation and before the original tail check and durable commit.
  Effect execution, duplicate handling, frozen binding, CAS, receipts and
  Unknown/QueryOriginal paths have no changes in the focused diff.
- Only the pending helper's `too_many_arguments` exemption was removed. The
  separate `artifact_save_execute` exemption and the other existing exemptions
  remain unchanged. Only these two production files differ from the base.

## Actual independent verification

Ran the existing real-source module-combination runner with the pinned local
Rust toolchain, offline locked dependencies and reviewer-isolated
`CARGO_TARGET_DIR=/tmp/artifacts-independent-target`. Dependency versions,
sources and checksums matched the repository lock. Result: **41 passed, 0 failed,
exit 0**, including save/local duplicate and receipt-tail rollback regressions.
Evidence: [journal-context-independent.log](evidence/journal-context-independent.log).
`git diff --check` also passed. No new mirrored tests were added for a parameter
grouping refactor; no RED-to-GREEN claim is made.

Current/tested full Rust manifest SHA256:
`2a0525f7579933c532be8d4dfde98b6c6d85c6355842ad4ae2cec5269e50bcd5`.
The reviewer recomputed it after execution and matched the log exactly.

| Reviewed production file | SHA256 |
| --- | --- |
| `artifacts/save_journal.rs` | `db07ab04238ec0a2bea3decae8422b8561eced4b3d18d972e1918d06f93596cc` |
| `artifacts/local_interactions.rs` | `f37b6c0e9072c83806ef65fa4e367049d8db802c6b9748f3787c24ae43017144` |

Review conclusion: no required correction in this scoped change. Full-workspace
formatting, Clippy/core-hook work and integration acceptance are separate owner
work; this review does not claim their completion or rerun them.
