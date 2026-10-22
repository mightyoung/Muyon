# Format-only follow-up — awaiting independent recheck

Source before correction: `ab9c381cc935be0cd52db5a8a455ce985bdba1db`.
Independent evidence branch: `task/document-core-verification-20261022`,
fixed commit `1c40b8fe6637c512fb491f66b79d0b6e25eeb3a1`.

Read the complete [independent compilation report](https://github.com/mightyoung/Muyon/blob/1c40b8fe6637c512fb491f66b79d0b6e25eeb3a1/docs/tasks/document-core-contracts-20261022/COMPILE-VERIFICATION.md)
and applied its complete raw [five-file rustfmt diff](https://github.com/mightyoung/Muyon/blob/1c40b8fe6637c512fb491f66b79d0b6e25eeb3a1/docs/tasks/document-core-contracts-20261022/independent-verification/documents-fmt.stdout.log).
No evidence-branch merge or changes to the original NOT_RUN/TDD history.

The old fixed source has independently executed documents **18/18 PASS** and
complete muyon-core package **165/165 PASS**. The latter includes the former;
these counts are not additive. That evidence does not retrospectively establish
the original RED/GREEN TDD cycle and does not verify this new formatted source.

Only the five reported Rust files changed: `documents/{anchor,capability,
identity,mod}.rs` and `tests/documents.rs`. No API or behavior change was intended.
The raw log contains duplicate hunks from recursive module formatting; identical
hunks were applied once, with each original context required to match exactly.
An output-separating blank line after EOF was excluded from the replacement.
Per-file original/result SHA-256 and unique hunk counts are preserved in
[application.json](format-followup/application.json). Original log SHA-256 and
local checks are in [checks.log](format-followup/checks.log).

`git diff --check` passed. This environment still has no rustfmt; the targeted
`rustfmt --edition 2021 --check` attempt returned **127 / NOT_RUN**. Therefore
this is a format correction derived from actual formatter output, **not a claim
that formatting passes**. Hand the new pushed SHA to the independent verifier
for the same five-file check and appropriate offline regression verification.

Carry forward the independent report's remaining boundaries:

- Full workspace tests were blocked at exit101 by absent offline cache entry
  `anyhow v1.0.104`; there is no workspace-wide green result.
- Workspace format check failed for these five files plus 52 other files
  unchanged from the fixed UI base. This follow-up does not modify the other 52.
- Real host/engine integration remains outside the delivered contract scope.

No installation, dependency download, credentials, permission change, real
model/search request, historical unknown retry, deployment or paid action.
Only this document branch is pushed; main/develop remain untouched and
Leader B remains the sole develop merger.
