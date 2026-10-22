# Persistence formatter follow-up — new fixed source awaits recheck

Formatting base: `f043c6b9b8d850acb590a9a3e567d1f2634a95cd`.
Independent verification branch: `task/document-core-verification-20261022` at
`0035845b5e9fedf8bf3cddd24da050b231500858`.

Read the complete [independent actual compilation report](https://github.com/mightyoung/Muyon/blob/0035845b5e9fedf8bf3cddd24da050b231500858/docs/tasks/document-core-contracts-20261022/PERSISTENCE-COMPILE-VERIFICATION.md)
and applied the complete original [scoped formatter diff](https://github.com/mightyoung/Muyon/blob/0035845b5e9fedf8bf3cddd24da050b231500858/docs/tasks/document-core-contracts-20261022/independent-verification/persistence-20261022/scoped-fmt.stdout.log).
No evidence branch was merged and no historical report/NOT_RUN log was edited.

The independent verifier actually compiled the OLD fixed source and observed:

- document_storage: 15 passed;
- tail-hook unit tests: 3 passed;
- old documents contracts: 18 passed;
- complete muyon-core package: 183 test executions passed, including all above.

These are not additive counts or a verified original TDD cycle. The previous
whole-digest LowerHex compile error was absent in that source's actual compile;
its historical failure remains recorded. This independent run did not retry the
full FFI workspace, resolve its known offline dependency gap or establish production
host/engine/gateway integration.

Only the seven files named by the failed formatter check were changed:
documents/{annotation,capability,identity,mod,storage,storage_tests}.rs and
tests/document_storage.rs. anchor.rs, old tests/documents.rs, document_edit/,
lib.rs, main/develop and all prior evidence remain unchanged.

Applied hunks by exact original line position and exact context. Duplicate module
formatter hunks were deduplicated by position/content; a formatter separator at
EOF was excluded. Per-file before/after SHA-256, unique hunk counts and raw diff
SHA-256 are in [application.json](persistence-format-followup/application.json).

Local `git diff --check` passed. The local seven-file `rustfmt --edition 2021
--check` attempt is **NOT_RUN, shell127**, because this environment still lacks
rustfmt. Actual log: [checks.log](persistence-format-followup/checks.log).
Applying real formatter output is not a locally executed formatting check.
The new pushed fixed SHA must be checked in the existing authorized verifier
environment before reporting formatting passed or applying old test evidence to it.

No behavior/API/SQL/schema/lockfile/dependency change, tool installation,
credential/permission change, engine, user-file, real model/search, deployment,
paid action or historical unknown request was introduced. Existing warnings,
unbounded cumulative history/blob storage, actor/group/reader-adapter gaps and
Leader B's sole develop merge ownership remain as previously documented.
