# UI action cards — implementation and handoff

Status: controlled card implementation delivered; offline checks pass; Android compile/render/host acceptance HOLD. This is one UI lane, not all-UI completion.

Branch: `task/ui-action-cards-20261022`.

- Verified candidate: `f4781e16ddf4e542b983fbd77f266a0071148255`.
- Explicitly authorized fixed foundation prerequisite: `2aa95ba7ab74ea11f9a89a42d2568650363e6c17`.
- Prerequisite combination merge: `f7d28a913a6bbc32e723ec53431d9c8d5d12dc58`.
- Cards implementation: `5ce7b1b902d0c498fcd75fb0fd5fb94a05a20d73` (seven new card-owned files, 767 lines).
- Independent review: [INDEPENDENT-REVIEW.md](INDEPENDENT-REVIEW.md).
- Public API and exact host mapping: [component README](../../../apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/ui/cards/README.md).

## Repository and source checks

Initial `/workspace/Muyon` checkout was clean on `work` at `cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003`. No AGENTS.md existed in the candidate tree or workspace ancestor scan. Read Leader handover, current Android refactor task/test plans, and relevant prerequisite reports. Started the designated new branch at the verified candidate; no user edits were overwritten. No main/develop checkout, writes, merges or pushes occurred.

`git ls-remote origin` at implementation commit confirmed main `cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003`, develop `0ab2c4f667681b9aacb017f8cd2eea6f576cf78e`, candidate unchanged, and no existing action-cards task ref. Only the task ref is to be pushed normally; no force or branch deletion. Leader B remains the only develop integrator.

Read the full UI specification and inspected the actual 03/04/05/07 design PNGs extracted into `/tmp/action-card-design` from design archive `399e3094740c8fcf1783797f0d0ae1f076dfd123`. Later archive `400e206135690c284c8402521e3135cfb7bfaee8` and its brand-original availability were checked. No design-history merge or image copying was needed for this lane. No generated logo, screenshot imitation or production fixture data was introduced.

## Delivered behavior

- Attachment per-stage facts, partial/failed/unknown distinction, available-page and failure-detail callbacks. No inferred percentage/full-read success.
- Evidence/source panel with quote, provenance, cited-versus-candidate relation, version and original anchor. External links have a separate typed category. No claim that locating a source proves a conclusion or independent support.
- Controlled native single/multiple selection; field edits are local draft events. Save draft, preview business submission and explicit send are separate callbacks. Saving/unknown locks modifications and no click synthesizes a save receipt.
- Trusted confirmation projection with target/change/expected+proposed version/recipient/cost scope. Modification and disclosure are distinct; disclosure requires actual nonblank content. Dismiss preview is local, not an execution cancellation.
- Receipts distinguish terminal/unknown/pending, preserve reserved-versus-actual cost including null/unknown, and keep cancellation request separate from cancellation outcome/rollback. Unknown only queries the original identity, no retry.
- Immutable material references and draft/saved/history/conflict report presentations. Conflict offers compare/view only; new-version preview is not a save.
- Full typed scope, mounted generation, component/message identity, component+state revisions, attempt and opaque digest accompany events. Query/cancel also carry the original request action/intent/binding separately from current CAS identity.
- FoundationButton/Tag and theme consumed from the exact merged prerequisite without modifying system files or copying tokens. The shell must apply FoundationTheme. Source reader/annotation resolution remains a common capability, not a research-specific PDF engine.

## Actual validation

Toolchain used only for standalone offline checks: JetBrains Kotlin JVM 2.2.20 (public compiler archive in `/tmp/action-cards-tools`), JRE 21, `-Werror -jvm-target 17`. No repository build/dependency configuration or credentials changed. The test runner itself performs no downloads or host calls.

```sh
KOTLINC=/tmp/action-cards-tools/kotlinc/bin/kotlinc bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/cards/run-offline.sh
python3 apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/ui/system/checks/test_contrast.py
bash apps/muyon_android/gradlew -p apps/muyon_android --offline :app:testDebugUnitTest :app:compileDebugAndroidTestKotlin :app:lintDebug
git diff --check
git diff --cached --check
```

| Check | Observed result |
| --- | --- |
| Standalone card projection/safety runner | PASS, exit 0, 43 actual assertions; independently rerun with same result |
| Fixed foundation palette/structural check | PASS, exit 0, one unittest; does not verify UI rendering |
| Product Gradle unit/Android compile/lint command | exit 2: `NOT_RUN: set MUYON_UI_GRADLE to the existing Gradle 8.13 executable.` No Gradle, SDK/adb found in environment |
| Diff whitespace checks | PASS |
| Android behavior source | 13 tests authored; NOT_RUN |
| Android rendering source | Four light/dark × 100%/200% fixture tests authored at 320dp; NOT_RUN; zero actual PNG evidence |
| Full product test suite/APK/device/TalkBack | NOT_RUN because required toolchain/product inputs unavailable; no aggregate pass claimed |

Test-first evidence: projection tests were written and compiled before CardModels existed; initial RED was missing source/API (compile failure, not a behavioral RED). Compose tests were written before ActionCards but could not execute due to missing Gradle; no behavioral Compose RED/GREEN is claimed. During test assertion-count refactoring a mismatched helper lambda caused a compile failure; corrected, then the final strict runner passed. All of these limits are retained rather than describing an unrun test as passed.

After implementation, three independent temporary source mutations compiled successfully and failed assertions (not compilation). Exact mutated predicates/sets:

1. Allow unknown receipts to expose cancellation: broaden `status == ReceiptStatus.Running` to include `ReceiptStatus.Unknown` — killed by query-only assertion without cancelRequested.
2. Remove `saveStatus != DraftSaveStatus.Unknown` from canEdit — killed by unknown draft preview lock assertion.
3. Add `PreviewReportSave` to conflict report actions — killed by exact conflict action-set assertion.

These sensitivity checks are post-implementation mutation evidence, not a substitute for a pre-implementation behavioral RED. Temporary sources/compiler jars/raw logs remain outside the repository under `/tmp`; no raw execution log was added by this lane. Dependency-origin evidence files were inherited unchanged with the authorized fixed foundation commit.

## Remaining blockers and handoff

1. Install/provide approved Gradle/Android SDK and existing product native/model inputs in the verification environment, then compile and run the authored behavior/capture tests. Actual capture command/selector and target app output path are in the component README. Image rendering, small-screen/focus/keyboard/large-font and accessibility acceptance remain unverified.
2. Contract source `c7c0d4729d034eb3d644e8945a56ca7dba467ff4` was read, not merged. Parent subsequently identified a same-scope old-attempt cancellation hazard in scope-only requestCancel and is fixing it. Do not consume that old signature. The later repaired source `52576777716ea215ef1428b4dc0bcd65fde17f00` (fix `4d3b80115dc79ab5829d7e3d82afc1086a302fdb`) was fetched and its `requestCancel(scope, pendingIdentity, expectedRevision): PendingSubmission` implementation inspected. It compares full pending identity and state revision, with current-revision duplicates idempotent. Parent subsequently closed this Important after independent static plus original RED/GREEN verification and released the new signature for offline cancellation-intent wiring. The adapter must capture original identity and expected revision from the same displayed snapshot, never read a newer attempt at click time or retarget/retry after rejection. Cards already carry complete original identity and current CAS revision; the unique shell adapter must map to this repaired contract, reject stale attempts atomically, and preserve cancellation as local intent only. No contract implementation was merged or edited by this lane.
3. Unique ui-shell owner must map trusted immutable host snapshots, durable receipts/CAS, source reader permissions/anchors, draft storage, outbound gates, business preview/authorization and version append/conflict rules. Existing finite chat contract does not yet contain attachment/evidence/report payload schemas; these projections must come from trusted host data. No ChatScreen/MainActivity wiring was attempted here.
4. These components do not close provider/device/release/I04 holds. The two old real requests remain unknown; reserved ¥0.002620 remains unresolved. No real lookup, retry, model/search request, paid action, deployment, credential or permission change occurred.

No action was denied by approval review; build/render actions are NOT_RUN due to missing tools, not pending permission. Remote push outcome is checked separately before final delivery.
