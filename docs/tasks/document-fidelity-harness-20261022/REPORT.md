# DOC-02 / DOC-05 / DOC-07 — offline foundation delivery

Outcome: runnable, original Python-standard-library inspection/preservation harness, four synthetic fixtures, original hashes/member inventory and conservative per-dimension reports. This is the safety/verification foundation, **not an Office editing engine**. No Rust/lib/production UI changed.

Branch `task/document-fidelity-harness-20261022`, isolated worktree `/workspace/document-fidelity`.
Fixed base `3ecb544ad0a47ccc38fe830777f35588b92e8afc` (`task/ui-shell-20261022`), verified remote before work. Remote Android candidate verified `f4781e16ddf4e542b983fbd77f266a0071148255`. Original `/workspace/Muyon` work branch was clean and left untouched. No AGENTS.md found in workspace or fixed source tree. Current shell HANDOFF/NEXT-BATCH and task REVIEW/README/leadership records read; user's newer explicit cloud execution authorization governs historical cloud restrictions.

Commits:

- `8b04dace8455c94edc761cfc486050b49ab44116`: initial harness, fixtures, tests and evidence.
- `b834dcb6cee13d09a935d3da4953bc556c75a676`: zlib exception, local ZIP flags, relationships and MIME fixes.
- `cd9fd9abc397b7f83bfb77bcbf43fc5e979c152a`: final independently reviewed processing code; nonblocking regular-file open, actual central-directory allocation bound and ambiguous-main rejection.
- Later sealing commit contains evidence/docs and repeatable mutation test utility only; final tip supplied by handoff/remote verification. No merge performed.

Pre-push remote recheck: UI shell advanced concurrently to `b6fcc030410d1718d00fbad15627423d4f809e2f`. Fetched/read-only diff confirms only UI/brand/foundation and their own docs changed, no overlap with this harness or task docs. Kept mandated fixed base3ecb544a; did not merge/rebase or edit UI files. Remote Android candidate/main/develop remain at recorded snapshots. Evidence: pre-push-remote.log and ui-advanced-scope.log.

Read both complete Library sources before implementation; identities/line counts recorded in RESEARCH-PROVENANCE.json. Research is design evidence, not vendor engine compatibility or license approval. No APK/proprietary implementation or source-available vendor skills copied. No paid/unreviewed SDK/engine installed, no user files used as fixtures.

Capabilities: capped file snapshot/hash; actual ZIP central/local header, compression/CRC, expanded/count/ratio/depth limits; path traversal/symlinks/duplicates/encryption rejection; extension/content-type/main-root/root-relationship checks; malformed/DTD/entity XML refusal including UTF-16; macro/external-link/embedded-object and active field/formula risk heuristics with rejection. Unknown parts remain inventoried. Comparison fails any source part missing or changed, including opaque parts; identical payloads mean byte preservation only. PDF is incomplete static byte preflight only, never safe/parsed/rendered. Marker-free PDF is quarantined. All render/recalc/visual/formula/annotation dimensions are not_run; safety and overall fidelity unknown. No source input writes or extraction.

Validation (Linux, Python3.12.14; exact environment in evidence/tool-environment.log):

| Command | Result / evidence |
|---|---|
| `python3 -m unittest discover -s tools/document_fidelity/tests -v` | PASS 27 tests, author final-code-green.log and independent-final-tests.log |
| `python3 tools/document_fidelity/tests/run_mutations.py` | PASS 3/3 mutants killed; final-mutations.log; only /tmp copies mutated |
| `PYTHONPATH=. python3 docs/tasks/document-fidelity-harness-20261022/evidence/independent-review-probes.py` | PASS final probe script: no ZipFile allocation for2054 forged entries; FIFO prompt JSON reject; metadata/encryption/DEFLATE failures handled; four fixture byte/hash/manifest checks; independent-final-probes.log and author corrected rerun |
| `python3 -m tools.document_fidelity.harness tools/document_fidelity/fixtures/minimal.xlsx --candidate tools/document_fidelity/fixtures/minimal.xlsx` | Exit0, exact-part preservation pass only; fidelity unknown and engine dimensions not_run; xlsx-self-compare.json |
| `python3 -m tools.document_fidelity.harness tools/document_fidelity/fixtures/minimal.pdf` | Exit0 report produced, quarantine/safety unknown/structure not_run; pdf-preflight.json |
| `bash scripts/verify.sh` | FAIL exit1 before any suite: flutter command not found; repository-verify.log. No downloads attempted by this failed command |
| Scoped code/Markdown diff check | PASS; raw full diff check FAIL exit2 on original RED unittest whitespace and valid fixed-width PDF xref trailing spaces, preserved deliberately; raw-diff-check.log. No whole-diff clean claim |

TDD evidence retained, including initial scaffold errors (red.log), corrected assertions-only initial RED22 failures (red-assertions.log), fixture RED, all regression RED/GREEN, author probe logger compatibility failure and corrected rerun. Failed or not-run evidence is not rewritten as success. Raw logs retain incidental trailing whitespace.

Fixture SHA-256:

| Original fixture | SHA-256 |
|---|---|
| minimal.docx | 3490b0855765c574079fcd1274aa1c8e0b7782f69ada87dab206c68b9069ee87 |
| minimal.xlsx | 546c5390f410064f74ac7f6c206f838d267261b79e7f34d6421d1660c8336363 |
| minimal.pptx | 37b1b3d41242ca3359371ae636635e43bdb8fb46d9ac77119cf2bdce7c5ad733 |
| minimal.pdf | affae7b5719e0a7a284e173bc6d430f9bb1be3b7092d9c8a947ee2b5ee87f00f |

See tools/document_fidelity/README.md and fixtures/manifest.json for exact subset/parts; ADR-ENGINE-EVALUATION.md for candidate/version/license/SBOM/fonts/resource/semantic/visual/negative-case gates. No candidate chosen or licensing conclusions invented. Synthetic PPTX has no master/layout/theme; desktop open and full schema compatibility NOT_RUN.

Independent review: original issues fixed through two immutable fix commits; final reviewer reports no known unresolved findings in reviewed scope. See REVIEW.md and raw independent evidence. A separate repeatable mutation utility was added after processing-code review; it only runs the already-described tests against temporary copies and cannot alter production documents. The same independent reviewer subsequently reviewed this utility and REPORT/REVIEW read-only and found no issues; no additional testing was claimed.

Remaining blockers: Flutter/Dart unavailable for repository suites; no integrated engine adapter, real render/recalc/semantic/comment or visual checks; no full OOXML/PDF parser/schema/security certification; complex corpus/desktop/device acceptance and engine/license selection are future gates. Existing Android SDK/AGP issues from shell handoff were not retried or bypassed. A soffice executable path is present in this environment but not invoked or relied on. No real model/search requests, no retry/refund of historical2 unknown requests / ¥0.002620 reservation. No credentials/permissions expanded, deployment, paid CI, force push, branch deletion, main/develop changes, merge or UI owner file writes. Leader B remains sole develop merger.
