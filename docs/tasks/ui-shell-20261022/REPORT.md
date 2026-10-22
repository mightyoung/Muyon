# UI shell integration — partial source delivery, 2026-10-22

Current follow-up: original brand placement and neutral Material role dependency
are source-complete; see [follow-up report](BRAND-FOUNDATION-BATCH.md). Real original-
request read-only snapshot source wiring is also completed in
[read-only batch](READ-ONLY-SNAPSHOT-BATCH.md), with typed actions still unavailable. Other
runtime/Android acceptance gaps below remain open. Earlier checkpoint verification
counts are preserved as historical results; current foundation checks pass2 tests.

Branch: `task/ui-shell-20261022`, isolated worktree `/workspace/muyon-ui-shell`.
Base `f4781e16ddf4e542b983fbd77f266a0071148255` verified by fresh origin head lookup.
Original `/workspace/Muyon` clean `work` checkout retained. No AGENTS.md in the
workspace ancestors or candidate tree. Read latest candidate progress,
REVIEW-REPAIR-20261021, ordinary-chat handoff and actual confirmation/storage code.
Main/develop remain unchanged; Leader B retains sole develop merge authority.

## Fixed dependencies and source ownership

- Design archive read at `400e206135690c284c8402521e3135cfb7bfaee8` (initial UI images
  read at `399e3094740c8fcf1783797f0d0ae1f076dfd123`; those images/spec unchanged
  between the two). Actual 01/02 PNGs inspected, not replaced by descriptions.
  Archive is not merged into feature history. Brand originals located, not regenerated.
- Foundation `2aa95ba7ab74ea11f9a89a42d2568650363e6c17` merged only after parent
  explicitly coordinated the exact dependency. Main root uses FoundationTheme.
- Configuration `e2a2981ae9a77408b01575fff5c105924ef9b9d1` subsequently merged after
  parent authorization; ancestry reuses the same foundation and includes Bot draft
  `79cf88974f6a44cb8e30df0e81d827a9376303b1`. No duplicate state machines/tokens.
- Authored production changes only MainActivity.kt, ChatScreen.kt and new ui/shell/.
  Authored instrumentation tests live in matching ui/shell/. All other production
  directories are unchanged beyond the explicitly authorized dependency merges.
- Cards `0519403abdf0f23e9104a022c3c4c8629ef1e1f3`, then reviewed wording fix
  `0a8c9fede203ecb5f3a65fb3bd01bd104e429838`, and repaired chat cancellation
  contract `52576777716ea215ef1428b4dc0bcd65fde17f00` subsequently combined after
  parent coordination, reusing existing foundation ancestry. They are not instantiated
  into production: this batch has no typed-card producer/host action binding. It does not call old requestCancel(scope), fabricate a component identity,
  or treat local cancellation intent as remote cancellation success.

## Delivered source behavior

- Modal menu covers 78% of available width, retaining the real composed body behind
  the gray scrim. Dialog window isolates keyboard focus; scrim/close/back dismiss.
  Main Agent and actual opened pinned agent/group identities appear above ordinary
  opened conversations. No sample conversations or transcript summaries. Pin writes
  require an actual local commit; failure stays visible. Selected entries expose
  selected semantics and a non-color marker; pinned entries say 已置顶.
- Conversation identity centered between left navigation and right operations, in a
  naturally sized row above the scroll area. Existing plus-menu operations preserved.
  Capsule composer uses foundation theme roles and keeps the original preview gates.
- A short user bubble is created only from frozen actual preview input after the
  original-request marker has committed. It is matched by original request,
  selection key and actual conversation UUID. Workflow/tool continuation previews
  do not invent a user message. Original result provenance/query remains visible;
  assistant result area retains full available reading width.
- Drafts are stored in a separate local shell preference namespace, isolated by
  length-prefixed conversation/project identity, at most 4096 characters per draft.
  They stay out of the Activity saved-state Bundle. A failed write leaves current
  input and a separate persistent draftSaveError, cleared only by successful write.
  Small saveable navigation/scroll state is retained across destinations. No false
  saved-business receipt is generated. Per-keystroke local commit performance still
  needs real-device measurement.
- Configuration preview entry retains the same editor per local application/project
  scope in an Activity ViewModel across tab changes/rotation. This is explicitly a
  local preview identity, not a trusted execution scope. No account/group snapshot
  is manufactured. Bot buffers and group selection remain in memory; process exit
  cannot restore configuration drafts. Group mode starts null; fixed/per_task do
  not run. Unknown costs/admins/permissions remain unknown. Save/create/start/query
  capabilities without a trusted host mapping remain unavailable. IME Back is
  handled before preview step/navigation changes in host source.
- Public document entry lists the planned PDF/Word/PPT/Excel common reading and
  limited editing scope without claiming implementation. Public reading/editing
  buttons remain disabled. A real route preserves the existing project-material
  entry; no reader engine, commercial SDK or broadened permission was introduced.
- Default Main Agent can reopen even if the optional local agent catalog is corrupt.
  Existing catalog and business records are never overwritten/reinitialized.

## Actual verification

Initial menu/draft test targets were written before corresponding source, but
Android behavioral RED/GREEN could not run. Later configuration/public-document
integration targets were added in the adapter implementation stage; they do not
establish a completed test-first behavioral cycle. Missing-tool output is NOT a behavioral RED and is not a passing TDD
cycle. Six new instrumentation methods cover menu selection/pins/local group label,
modal body/draft retention, isolated local draft restore/limits and preview entry
retention/closed execution gates and public-document capability gates. They remain UNEXECUTED.

Commands from repository root unless specified:

1. `python3 -m unittest discover -s apps/muyon_android/checks -p 'test_*.py'`
   — PASS 17 tests, exit0; `evidence/python-checks.log`. These are existing package/
   CI/evidence gates, not rendered UI acceptance.
2. `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/ui/system/checks -v`
   — PASS 1 actual-palette contrast test, exit0; `evidence/foundation-checks.log`.
3. `KOTLINC=/workspace/ui-shell-tools/kotlin-2.2.20/kotlinc/bin/kotlinc bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/configuration/run-offline-checks.sh`
   — PASS 5/5, exit0; `evidence/configuration-offline.log`.
4. Same KOTLINC with `.../product/agents/setup/run-offline-checks.sh`
   — PASS 11/11, exit0; `evidence/bot-offline.log`.
5. Initial repository `./gradlew :app:connectedDebugAndroidTest` and compile/lint
   attempts — NOT_RUN exit2, missing Gradle8.13. Preserved test-first logs and
   `evidence/android-validation.log`.
6. To make a real compile attempt, official Gradle8.13 downloaded under writable
   `/workspace/ui-shell-tools`, official distribution SHA256 checked:
   `20f1b1176237254a6fc204d8434196fa11a4cfb387567519c61556e8710aed78`.
   Existing Java21 used; no persistent system config/credentials/security settings.
   `(cd apps/muyon_android && GRADLE_USER_HOME=/workspace/ui-shell-tools/gradle-cache MUYON_UI_GRADLE=/workspace/ui-shell-tools/gradle-8.13/bin/gradle ./gradlew --no-daemon --console=plain :app:compileDebugKotlin :app:compileDebugAndroidTestKotlin :app:lintDebug)`
   — FAILED exit1 during plugin resolution, com.android.application8.11.1 not found
   from configured Google/Maven/Gradle plugin repositories, before product compile.
   `evidence/android-with-gradle.log`. Final combined tree repeated offline, same
   prerequisite failure exit1; `evidence/android-final-combined-offline.log`.
   A harmless direct official AGP POM read succeeded; root cause of the Gradle
   resolver difference is unproven. No proxy/security settings or mirrors changed.
7. Official SDK repository manifest and command-line tools23 downloaded/verified
   against official manifest SHA1 `e025545c62a8e64c7559119566a569fb1dec5f60`.
   Exact attempted action:
   `/workspace/ui-shell-tools/sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root=/workspace/ui-shell-tools/sdk --install 'platforms;android-36' 'build-tools;35.0.0' < /dev/null`
   — DENIED/FAILED exit1, tool says `Failed to create bin dir`, `Read-only file
   system (os error 30)`; internal bin target not printed. Stopped this installation
   immediately, no relocation retry/older tool bypass/escalation. No SDK platform
   installed, no license accepted. `evidence/sdk-license-block.log` (diagnostic name
   retained; actual failure is filesystem, not a demonstrated license prompt).
8. Official Kotlin2.2.20 compiler used for steps3/4, downloaded in task-writable
   directory. No Android stubs or substituted Android build were used.
9. Scoped authored source/document whitespace check — PASS. Whole staged
   diff-check reports trailing spaces emitted by Gradle in the original logs;
   raw evidence is retained unmodified and this whole-archive check remains exit2.
   Final independent static review in REVIEW.md.
10. Final combined dependency checks additionally executed: cards runner **43
   assertions PASS**, then corrected cards **45 assertions PASS**, and
   component-contract runner **20 groups PASS**; raw outputs
   `evidence/cards-offline.log`, `evidence/cards-final-offline.log` and
   `evidence/component-contract-offline.log`.
   These check offline dependencies, not shell UI or live business adapters.

## Remaining blockers and explicit non-completion

Actual Android compilation, lint, all instrumentation/device behavior, 78% pixel
measurement, IME/back/rotation, small screen, 200% text, TalkBack, focus and screenshots
are OPEN. No APK produced and no old f478 device evidence inherited. SDK installation
is stopped after a filesystem denial; a permitted SDK/bin installation arrangement
and Android license disposition need parent coordination, without bypassing denial.
Gradle plugin resolution also remains unresolved. No new CI dispatched or paid quota.

This is a minimal source integration batch, NOT all requested UI completion. Outstanding:
brand resource placement is now source-complete in the follow-up; remaining items:
typed cards/attachment/business-confirmation production host bindings (dependency
source is combined, not a real runtime snapshot);
trusted configuration persistence/create/host snapshots/FFI/query mappings; actual common document reader/annotation/editing resolver (only the neutral
entry/capability gates are wired, no private research-only engine/new SDK).
Existing latest-request projection remains: this batch does not create persistent
multi-turn history or auto-fetch/retry historical requests. Original request markers
remain queryable; rendered transient result buffers may require the existing original
lookup after page recreation, as before. Menu opening itself keeps the mounted body.

Foundation adapter risk found independently: the provided theme leaves some Material
roles at defaults (secondaryContainer/onSecondaryContainer, surfaceContainerLow).
Existing workflow FilterChip / local research panel can retain non-neutral defaults.
New shell/bubbles use neutral surfaceVariant; system owner must coordinate role fix.
No local modification to system/ was made. Follow-up exacta2213ce2 source dependency
closes this role mapping issue; actual rendered verification remains open.
No image shown is runtime evidence.

Historical two unknown requests and ¥0.002620 reservation untouched; no model/search
request, resubmission, refund, credential setup, permission expansion, deployment,
main/develop merge, force push, branch deletion or changes to user's original checkout.

Cards cancellation wording Important closed by parent and non-author static review:
combined exact corrected source0a8c9fede203ecb5f3a65fb3bd01bd104e429838 now says
only local intent recorded, no confirmed cancellation. Final45 assertions actually
rerun in this environment. Cards still are NOT live-bound by shell.
No local alteration of ui/cards/ was made. Required cross-owner producer patch plan
is in HOST-ADAPTER-PATCH-PLAN.md; missing identities are never fabricated.

Final full project command after authored adapters and combined dependencies:
`./gradlew --offline --no-daemon --console=plain :app:testDebugUnitTest :app:compileDebugKotlin :app:compileDebugAndroidTestKotlin :app:connectedDebugAndroidTest :app:lintDebug`
with the same explicit temporary Gradle/cache settings — FAILED exit1 before
product compilation, same AGP8.11.1 resolution prerequisite. Retained as
`evidence/android-final-suite.log`. No individual Android test executed.
