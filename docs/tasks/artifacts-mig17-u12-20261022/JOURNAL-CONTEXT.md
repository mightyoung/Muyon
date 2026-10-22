# Private pending-journal context quality follow-up

Base 0e85c6e98c4e32efc8008092e480626f342a701d; independent continuation branch.
No production module formatting, non-Drop changes or owner hook wiring included.

Original journal_pending has only two internal Rust callers, no FFI/exported ABI.
The arguments came from:

- intent: the original explicit artifact save/local mutation/confirmation request;
- project and actor: existing ArtifactProjectAccess after same-transaction checks;
- JSON/digest: exact frozen SaveRequest::binding or local Request::binding output;
- domain: code-selected Artifact or Local namespace, never payload SQL;
- object_id: local component identity used for pending lock; Artifact ignored an
  empty-string placeholder. Other journal methods still use JournalDomain.

There is no compatibility requirement justifying a parameter-count exemption.
Use a private borrowed PendingJournal with named common frozen fields and a
PendingJournalTarget enum (Artifact / Local{object_id}). This statically requires
an object ID only for Local and removes Artifact's ignored placeholder. No new
serialization, authority, mutable values, transaction or storage schema exists.

The same exact INSERTs/parameter order remain at the same two caller locations:
authorize/validate -> pending write -> tail checks -> original transaction commit
-> later effect transaction. No frozen identity/digest, duplicate handling,
receipt publication, CAS, Unknown/QueryOriginal behavior or hook contract changes.

Verification: run existing actual41 before and after, review the focused diff and
SQL strings/parameter ordering. No mirrored unit tests for a grouping-only refactor.
Keep failure/NOT_RUN output if any. Independent review before fixed-SHA handoff.

## Result

- Fixed 0e85 archive baseline: actual41/41 PASS, exit0;
  evidence/journal-context-fixed-baseline.log. This isolated archive is the
  authoritative baseline; the earlier direct-worktree baseline log is retained
  separately and is not needed as proof while edits could have been in flight.
- Refactored actual41/41 PASS, exit0:
  evidence/journal-context-regression.log.
- Independent reviewer actual41/41 PASS, exit0 plus exact SQL/parameter review:
  JOURNAL-CONTEXT-REVIEW.md and evidence/journal-context-independent.log.
- Targeted Clippy all-targets with `-D clippy::too_many_arguments` PASS, exit0:
  evidence/journal-context-targeted-clippy.log. The actual module-only harness
  used run_source_combination.py with only its lint argument changed from
  `-D warnings` to `-D clippy::too_many_arguments` in a temporary runner. No source
  was rewritten or allow added. Other preexisting warnings remain visible; this
  targeted result is not an assertion that all-warnings strict Clippy passed.

Final tested Rust manifest SHA256:
`2a0525f7579933c532be8d4dfde98b6c6d85c6355842ad4ae2cec5269e50bcd5`.
Only save_journal.rs and local_interactions.rs production code changes.
The unrelated artifact_save_execute parameter exemption is unchanged, as this
follow-up is scoped to journal_pending. Core source invalidation callback request
and host/FFI/UI integration boundaries remain as previously handed off; no owner
hook, ABI or permissions were changed here.
