# Coverage and incremental value

Baseline is B06 handoff `6635bc6be057fd36c0e0c6c0aafaf034aca2ecaa`, not current production or a claim that an old candidate shipped. The local checkout initially pointed at old main `cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003`; the experiment branch explicitly starts from B06. No AGENTS.md or tracked `.agents` instructions were found in the checkout; `/workspace/.agents` is empty. Actual adapters were read only. Only the two user-authorized new directories are changed.

Research report `libfile_53ebb3e0d5fc8191831301d90ee175a9`, version 0, was materialized with the Library official helper and metadata verification. Exact local bytes: 24,596 bytes, SHA-256 `208a6100f36c7aca3ea8a96a26556ba1a4895082aaf11475214ab82371b3f2a0`. No guessed URL or direct download was used. Report is guidance, not proof of any observed Muyon failure.

## Existing coverage retained

`existing-coverage.json` lists every one of the 24 Rust test IDs and all seven exact lab blob identities at `e85bc0039185453f3f46d1a77494bb00b588c44a` and `379b1a6d8d5a5830fb3a74924fd5c41cfb234e1c`. All lab blobs match. The B06 branch does not contain that crate; it was inspected with `git show`, not copied/cherry-picked or modified. Cargo is unavailable, so these 24 are NOT_RUN here, not added to the passing count.

| Existing test group / IDs (full list in JSON) | Already establishes in isolated candidate | New work decision |
| --- | --- | --- |
| `atomic_precommit_crash_rolls_back_tombstone_and_outbox`, `commit_crash_reopens_in_other_process_and_blocks_read` | deletion tombstone/outbox crash boundaries | No replacement of existing tests; new crashes concern correction intent and replace SQL |
| `replay_is_bound_to_complete_payload`, cleanup/partial failure/stale-worker tests | deletion identity, leases, bounded failure state and completion | No duplicate fix; not interpreted as authorization for arbitrary unknown replay |
| `every_member_current_field_is_checked_at_final_consume`, both revoke/consume order tests, shared-fence test | strict final per-member checks and governed consume transaction | No substring/current-member repair |
| `body_forks_without_revision_change_are_not_consumed_or_quoted`, independent gates, source authority, actual SQLite read errors | actual memory/source body hashes and revision-independent failure closure | No hash/revision repair |
| quote UTF-8/redaction/source-range tests | validated provenance and redacted source projection | No new span projection implementation |
| automatic-write/read separation and deletion management tests | independent controls | Unchanged; synthetic fixture does not replace production policy |

Production Dart already has `assistant_runtime_test.dart` / `empty final response is not a successful answer`, `assistant_reply_test.dart` / `two empty replies fail clearly`, and `ai_test.dart` / `empty JSON replies are retried once, then reported`. These are different assistant/business routes, not a memory reconciler `[]` contract. They are NOT_RUN here because Dart/Flutter is unavailable. Existing gateway/ledger/credential tests are detailed in ADAPTER-LOG-AUDIT; no claim that those checks were rerun.

## New falsifiable assertions

| Gap | New assertion / executable evidence | Limit |
| --- | --- | --- |
| Retirement then failed insert | actual SQLite trigger abort; transaction rolls back, durable correction remains NOT_COMMITTED, old overruled truth is blocked across reopen | synthetic store, not Hy/Muyon replacement code |
| SQL commit then vector failure | status COMMITTED_INDEX_PENDING, one SQL current row, explicit fallback returns new fact despite stale old vector; explicit index-only repair | fake vector, no production retriever certification |
| Interrupted correction | child exit before insert vs after SQL commit, durable reopen and observer sees no half replacement | bounded SQLite experiment, not all power-loss/fsync or concurrency cases |
| Late repair after deletion | failed SQL and failed vector repairs cannot revive the corrected/deleted fact | new replacement recovery boundary, not a reimplementation of deletion outbox |
| Empty model response | None/empty/Unicode whitespace fail; literal [] succeeds as NO_CHANGE; malformed/wrong shapes fail; no implicit mutation | local parser schema only |
| Unknown | no automatic invocation retry, durable unknown refuses replacement; independent tests continue | only synthetic state; I04 never executed |
| Oracle sensitivity | three intentionally broken controls are rejected | negative fixtures, not product defect reproduction |
| Actual log paths | actual gateway fixture + static matrix; no fake logger | dynamic NOT_RUN; no zero-leak conclusion |

No fake-model test is counted as production implementation evidence. No real frontend/backend or installed-device acceptance was attempted, and no host/UI/AIDL/Gradle/adapter/Hy source was changed. The sole integration owner `01a14da8-37ed-76fa-9fb2-7c14c0dae0d5` owns any production follow-up. The ledger semantic completion ambiguity and potential open error-text boundary are minimal reproduction/patch suggestions only; neither is dynamically confirmed here.
