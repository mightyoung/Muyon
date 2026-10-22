# Dot review repair ledger

Review base: `30c033cd8542f566d40e9248bcc498e7efce7fc6`. Overall acceptance stays PARTIAL/HOLD; no merge or live provider retry is authorized.

Four independently reviewable batches:

1. Durable business review lifecycle: reproduce the pre-dispatch crash gap, distinguish a durably sealed unsubmitted review from an accepted unknown operation, and never clear/replay unknown writes. Cover research and supplier entry points, restart and late confirmation races.
2. Chat lifecycle and OCR: invalidate stale conversation callbacks, restore actual memory-only runtime configuration, and verify positive/negative inclined text and all four corner orientations.
3. Outbound authority/disclosure: recheck unresolved requests at confirmation/claim/write, recheck/revoke disabled skills through tool followups, and disclose exact immutable payload/history/endpoint before confirmation. Socket-free fixture tests only; production pricing proof remains unavailable.
4. CI/resources: run the actual new Rust/Android products in CI, establish resource provenance or replace extracted assets, and distinguish CI wiring from an actual successful remote check and model redistribution acceptance.

Each batch records a fixed commit, regression evidence and remaining gaps. Leader owns serialized Gradle/native/device verification; agents edit disjoint slices. Final handoff is a whole-branch integration Draft PR against develop, explicitly including inherited PR86/97/98/99 and HOLD dependencies; it does not choose a merge strategy or approve dependencies.

## Fixed commits and result

| User finding | Disposition | Evidence |
| --- | --- | --- |
| 1 · unsubmitted write recovery | FIXED_LOCAL | `2952ec33`: durable prepared/claimed/sealed review acceptance, no replay, trusted not_submitted; supplier/research actual Service recovery tests. |
| 2 · OCR direction | FIXED_LOCAL | `faba4d73`: real old-source device RED, then positive/negative angles and all four pixel-corner identities PASS. |
| 3a · stale chat preview | FIXED_LOCAL | `faba4d73`: mounted conversation/project generation rejects late replies and cancels stale previews. |
| 3b · lost configuration UI | FIXED_LOCAL | `faba4d73`: status comes from current Service credentials/configuration readiness; real tab-return test PASS. |
| 4 · preprepared unknown bypass | FIXED_LOCAL | `bb8b8a56`: confirm/claim/final-write checks; actual owner fixture RED/GREEN and cross-root normal/child regression. |
| 5 · disabled skill authority | FIXED_LOCAL | `bb8b8a56`: permanent old-plan revocation and chain/tool guards, scoped cross-session write-gate cancellation before mutation; actual Runtime order regression PASS. |
| 6 · incomplete outgoing disclosure | FIXED_LOCAL | UI `faba4d73`, immutable payload `bb8b8a56`: actual history/tools/endpoint displayed, missing preview refuses confirmation, dispatch/preview JSON equality tested. |
| 7 · missing product CI | WIRED; REMOTE GATE OPEN | `9c1fb4a9` adds actual product jobs; `6fa48732` corrects job-level runner context after a real zero-job validation failure. Fixed actionlint RED/GREEN. Android job still requires a reviewed model URL; no green claim. |
| 8 · extracted UI asset permission | CURRENT_SOURCE_REPLACED | `9c1fb4a9`: two extracted TTFs removed, five vector icons replaced; new candidate package/source checked. Historical commits/APKs and model provenance are not cleared for distribution. |

Final local candidate source is `9c1fb4a9e8aa0b85f1c896938278085ee8cdc0ad`.
Subsequent commits add CI validation repair and documents, without changing its
product source. [Full local verification](../../implementation/review-repair-proof-20261021/README.md):
157 Rust executions/16 suites, strict Clippy,7 Python tests, Android app/test build,
lint0 errors/33 warnings/6 hints, package checks and63/63 actual API26 device methods.
Independent static safety review closed three further issues found during repair:
sidecar initialization interruption, cross-session write race and overbroad skill
cancellation. No approval to merge or release follows from that scoped review.

## Remote and integration boundaries

The initial push encountered a concurrent remote update `94431082`, containing
only Claude's separate report. It was fetched and merged as `a5a0580b`, preserving
both histories without force push. That report contains additional findings
beyond the nine supplied Dot items; its remaining cancellation/settlement,
attachment maintenance, agent instructions and broader evidence/usability issues
remain separate review work, not implicitly resolved by this ledger.

First CI run `39541832611` failed before creating jobs because `runner.temp`
was used in job-level env. The fixed1.7.12 actionlint reproduced three errors
on the old YAML and accepted the corrected workflow. Retain that failed run;
model-input absence is a separate subsequent Android job blocker.

The integration branch contains the currently open PR86 (`3f1be180`), PR97
(`3abc1cae`), PR98 (`ddb34971`) and PR99 (`9c007371`) heads; ancestry was verified.
None of those PRs was merged, closed, replaced or approved. The Draft PR against
develop is for whole-branch review. The unique merge executor must decide whether
to merge the original PRs individually or explicitly supersede them with the
integration PR, and must retain all original HOLD dependencies until disposition.

Android CI configuration and model provenance remain blocked pending an approved
`MUYON_MODEL_INPUT_URL`. No URL was guessed, no substitute model added, no gate
skipped and no credentials/paid requests/I04 retry used. Overall PARTIAL/HOLD.
