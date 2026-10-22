# Configuration offline runner missing input

Fixed base (actual latest develop read/fetch):
022389b4d1d6fbf1f1bd7eead59259774886170d.
Independent worktree /workspace/muyon-configuration-runner; branch
task/configuration-runner-input-20261022. Source-only implementation commit:
3a3614911dc183180686d1b68cb9367c792eeba2.

The standalone runner explicitly lists Kotlin inputs but omitted the existing
SetupDraftArchive.kt needed by BotSetupDraft.kt. Gradle product compilation
already includes that source; this is a developer-check runner defect, not a
production configuration feature fix. Add exactly one compiler-input line.
No production source, five original assertion groups, compiler/tool versions,
permissions, build thresholds or runtime feature gates changed.

## Actual test-first verification

Before source edit, ran original repository script using existing Kotlin2.2.20
and JDK17 in task directories: exit1, unresolved SetupDraftArchive,
ArchivedSetupEdits,RestoredBotSetupDraft. RED.log/exit preserved.
After only the missing input line was added, ran the same original script:
exit0,5/5 PASS. GREEN.log/exit preserved. All five original assertion source
bytes unchanged (SHA256 and comparison in ASSERTIONS-UNCHANGED.json).
Commands/environment are in evidence/command.json; no external wrapper input
list or bypass used for the fixed GREEN. bash -n and git diff --check passed.

No new tests or mirrored implementation assertions added; the original runnable
five-group suite is the regression. Adjacent existing Bot checks and independent
rerun are recorded below after completion. No Android/Rust/product rebuild,
provider/model/search operation,tool install,Library/Drive action,upload,new PR,
merge,main/develop edit,force push,branch deletion or deployment.

## Historical evidence is distinct

A separate report-only correction was pushed on the prior evidence branch:
f655ae2e9ad4f28a954e13cf3a188139015d57df (parent9cf5646e...).
It corrects the type names and discloses retained SDKXML/strip/analytics/fixture
unbind warnings, changing no original logs/images/APK/license bytes. The original
3aae runner exit1 and external same-source5/5 evidence stay unchanged.
This source fix does not retroactively pass old runs or relabel/rebuild the sealed
3aae APK (430153964 bytes,SHA256
2f3b67f53e25085aecce68a433b96921691d3b187813544fc761f0f55113b8bd).

## Adjacent checks

Existing agents/setup/run-offline-checks.sh, same JDK/KOTLINC/PATH environment:
exit0,17 offline checks PASS. No production/source change was needed.

## Independent rerun

Non-author reviewer ran the actual fixed original repository runner at source
commit3a3614911dc183180686d1b68cb9367c792eeba2: exit0,5/5 PASS.
Independent raw log/exit preserved; review in INDEPENDENT-REVIEW.md.
