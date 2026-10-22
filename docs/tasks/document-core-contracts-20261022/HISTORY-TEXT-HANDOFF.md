# Historical metadata authority / Text / Leader B combination handoff

Interface first: `473b7eb15fb199b5e20b96e52859b48ea09acef6`.
Historical/Text production source:
`64017cd443a32b131c0d0851ba9346625d95819c`.
This sealing commit adds two test cases and docs; production source is unchanged.

## Real core-owned historical policy

On the existing BusinessStore, no second document or blob truth:

```text
initialize_document_history_trusted() -> ()
issue_document_history_grant_trusted(current, historical, read_operations, expiry) -> ()
revoke_document_history_grant_trusted(current, historical) -> ()
document_history_access_in_transaction(tx, current, historical, required) -> DocumentMetadata
```

All methods return Result<_, ContractError>; exact Rust signatures and policy
are in [HISTORY-TEXT-INTERFACE.md](HISTORY-TEXT-INTERFACE.md). The access hook is
crate-local for the artifact/source owner, never model-callable.

The separate `document_history_grants_v1` policy table has explicit initialization
and exact DDL identity. No existing six-table document migration. It stores only
exact historical permissions under the real parent grant ID/generation/epoch,
current DocumentRef, historical DocumentRef, read operations, active state and
<=30-second expiry. This is a narrow child policy, not a copy of document data or
an artifact-owned authority table. Parent grant expiry/revocation/generation/head
change invalidates it. Host must explicitly decide historical access and derive
actor/group identity from real policy; current read authority alone is insufficient.

The history hook requires the same live transaction, real current head and current
parent grant/project scope, same document/scope, and an explicit active matching
historical permission for older revisions. It reads the exact canonical row from
document_revisions, cross-checking full DocumentRef and SQL revision key, and
checks both authorities again before returning. Current==historical uses ordinary
exact-current authority. Missing permissions/table/history or mismatched target
fail; it never substitutes latest metadata or changes the document head.

Artifact owner should consume the hook for every frozen output/source snapshot
in its own directory. **Do not automatically issue a historical grant during
artifact reads** or replace denied reads with publication-tail grant checks.
A page with a denied target fails atomically. This metadata API is not a byte
lease; the trusted reader/delivery owner must check historical authority at use.
Actual actor/group policy adaptation and byte delivery remain unfinished.

## Text decision and evidence-owner action

`DocumentFormat::Text` serializes as `text`. It is a distinct plain-text metadata
label, with default CapabilityMatrix status Unknown. No decoding, UTF-8 assumption,
PDF byte relabeling, geometry, OCR, rendering or support activation was added.
All previous format wire labels remain unchanged.

The evidence module at `741274f6ef628501cc8c75c61f156b9f003c81d7` currently uses
explicit Utf8Text with Unknown only. Its owner must consume Text deliberately,
continue verifying original bytes/hash/actual UTF-8 and reject contradictory
PDF/other formats. Text metadata alone is not successful format detection or
permission. This core branch does not alter evidence/ or process any source bytes
as Text; evidence-host integration and detection remain owner follow-up work.

## Module export patch — NOT applied here

[combination-module-exports.patch](integration/combination-module-exports.patch)
adds artifacts, evidence and bot_drafts to lib.rs. `git apply --check` passed;
that checks patch applicability only, not module presence or compilation.
Original lib.rs remains unchanged and compiles independently of absent modules.

Leader B alone should apply it on the designated combination branch after the
three real modules and their fixed dependencies have been imported. Known owner
references are artifact `4eec6d164e84d87c74b6bc92f45ecb1e3138f680` and evidence
`741274f6ef628501cc8c75c61f156b9f003c81d7`; obtain the bot_drafts owner's fixed
source separately. This author does not write Leader B's branch or declare these
modules combined. Conflict resolution must preserve all current behavior and
receive actual Rust verification.

## Prior COPY format patch and verification evidence

Parent-provided pure formatter commit
`93de8ad99fad105bc3ca32036de30803d87fd6c7` was inspected and cleanly cherry-picked
as `8544828763c82efe6990f5072c27894744e1b012`, before historical production changes.
No manual formatter guessing or old-style rollback. Its independent report is
at evidence commit `d4b6af74644ac8f1abe8ab343ccf3cf6e6d696c5`,
COPY-CLONE-COMPILE-VERIFICATION.md. That fixed formatted COPY source actually
passed COPY6/hooks9/core189 and scoped formatting; those counts are inclusive and
are not applied to the later historical/Text changes.

## Current checks and review

Eight new history/Text test cases cover implicit denial, exact explicit success,
target-specific permissions, parent/child revocation/expiry/epoch/generation,
project deletion, foreign transaction, scope/document/future version rejection,
write-operation refusal, canonical corruption/missing row, head advance, bad policy
schema, and Text wire/default capability behavior. Fixture visibility changes
are confined to cfg(test) helpers.

Independent read-only document_contract_review reviewed fixed 64017cd4 and the
two added test cases, confirmed policy/schema/data ownership boundaries and found
no blocking or statically confirmed compile issue. It also checked the unapplied
export patch. Review conclusion: static pass; Rust execution remains NOT_RUN/HOLD.

Actual local commands/results:

- `cargo test --offline --locked --manifest-path crates/Cargo.toml -p muyon-core --lib documents::history_tests`: NOT_RUN, cargo absent, shell127.
- Full muyon-core test: NOT_RUN, cargo absent, shell127.
- Scoped rustfmt: NOT_RUN, rustfmt absent, shell127. No claim that current source formatting passes.
- `git diff --check -- crates`: PASS.
- Export patch applicability: PASS; lib.rs diff empty.
- `python3 .../history-evidence/history_sql_smoke.py`: PASS for actual extracted
  DDL/5 SQL statements, synthetic persisted exact-target/generation policy reopen,
  bounded JSON projection, revoked-row exclusion and FK check. This is SQL-only,
  not Rust authority/head/expiry logic or a byte-delivery test.

Raw logs are under [history-evidence](history-evidence/). Original NOT_RUN/TDD and
compiler/format failure history is unchanged. Parent's existing authorized Rust
environment must compile/test/format the new fixed source before acceptance.

No engine or real user file, no model/search/fee/credential/permission expansion,
no main/develop or Leader B branch edits, no deployment or historical unknown
retry. Aggregate history/blob quota, provenance/group adapter, reader/cache
authorization, evidence routing and full engine/Office functionality remain open.
