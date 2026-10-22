# Independent fixed-source composition review

Reviewed candidate `bc8fea61744530c1f2e38e65b0273a434c3bd5a8` against merged baseline `c130008bbc40d78e85d10058030da9da4aca38f0`, in `/workspace/Muyon-post-pr101-office-bot-20261022`.

**Conclusion: no Critical or Important composition defect found in the reviewed two-slice delta. A Draft PR can be opened for this fixed candidate, with pending checks and acceptance limits stated accurately. This is not merge, release, Android runtime, or complete OOXML fidelity approval.**

## Source custody and retained baseline

- Compared every path changed from `214b4031` in Office `01e6b787ba1709c344f6d29246f50b6061742e42` and Bot/Host `0b06222981619e598f264e76b618d80f6228f35a` with the candidate Git objects. All imported file bytes match their respective pin, including original evidence logs. The only excluded owner path is Office's branch-specific `.github/workflows/muyon-product.yml` trigger change. The resulting union exactly equals the candidate's 99 changed files; no extra or missing paths.
- `metadata_value_contract_test.dart`, both coverage diagnostic/test files, and `.github/workflows/ci.yml` remain byte-identical to merged baseline `c130008b`, retaining the aeb contract repair and original CI gates.
- No `muyon-core`, `experiments`, scripts, packages, or workflow change occurs in this delta. No new Reader/policy, retirement prerequisite, source-notification hook, or stale Service trial wiring is imported. In particular, the later source-hook Artifact notification RED does not apply to this source graph.

## Interfaces and authority boundaries

- Generated Kotlin delta adds the three Office free functions, two records, sequence converter, externs/checksums and call scaffolding. All five existing draft interface/implementation signatures and their extern/checksum/call lines are unchanged. `LocalDraftPrepareRequest` and its converter are byte-identical by brace-bounded comparison with the baseline.
- ProductService's prepare call uses the actual generated `LocalDraftPrepareRequest` and the original captured ten fields. `expectedStoredRevision` remains the base record revision; exported memory/editor revisions and archive are not substituted or freshly exported. Native provider and FFI draft logic are unchanged.
- `verified=false` is retained. Existing Runtime/session checks still refuse production save/restore/query through the unverified port; this real source call does not certify Service/native invocation or turn on persistence. No second owner, store, driver, or handwritten ABI appears.
- Office FFI functions operate on byte inputs using the pure Rust engine and return text or candidate/hash metadata. They do not publish, write user files, authorize business effects, or invoke a model. ReaderContent uses its existing host current/open checks and closes the descriptor stream, now calling the bounded Rust preview. The editing functions have no newly connected UI publication path.

## Office correction inheritance

Read the original static findings and subsequent independent final review; checked the imported fixes at their actual call sites. Inline Spreadsheet rPh suppression remains cell-scoped. DOCX/XLSX check input, escaped/splice size and replacement part/expanded budgets before relevant output allocations. Public rewrite uses the reader replacement view before compression and bounded archive writes; untouched members retain raw-copy behavior. The earlier inline-phonetic/output-budget findings are not present in their original form. This check does not replace a full XML/OOXML security or semantic audit.

## Findings and validation limits

- Critical: none found in scope.
- Important/blocking source finding: none found in scope.
- Minor: no required source correction identified by this composition review.

The owner reports contain historical failures, NOT_RUN checkpoints, later Rust results, and dependency-resolution failures; these are retained as historical evidence rather than relabeled as this combination's passes. Parent is executing fresh Rust/Python verification for this exact candidate; no result from that still-active work is asserted here. Draft text must attach the actual fixed-SHA outcomes and preserve failures/NOT_RUN. Actual matching native regeneration/binding comparison, Android compile/lint and any Service/device acceptance must be reported separately; five-method static ABI preservation is not native execution. No Office visual fidelity, formula recalculation, durable edit publication, or full product acceptance is established.

Reviewer used only local read-only Git/file inspection and metadata comparisons; no tests, build, network, credentials, real model, old I04, denied artifact download, push, merge or installation. The sole written deliverable is this external review report. An initial local comparison extractor used the next documentation marker and included the newly inserted Office record beyond the old converter; its assertion was a review-script boundary error, not a product mismatch. The corrected brace-bounded comparison confirmed both old prepare blocks unchanged.
