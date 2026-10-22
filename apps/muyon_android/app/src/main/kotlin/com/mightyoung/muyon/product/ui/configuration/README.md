# UI configuration — partial offline delivery, 2026-10-22

Branch: `task/ui-agent-configuration-20261022`. Verified origin candidate:
`f4781e16ddf4e542b983fbd77f266a0071148255`. Initial checkout was clean `work`
at `cc7c8d14d30e3d3c4c7c6cb2bf2059a99e46e003`; no AGENTS.md found in
workspace ancestors/candidate. Read task index, HANDOVER-LEADER and latest
REVIEW-REPAIR-20261021. Leader B remains sole develop merger. No main/develop
changes, force pushes, deletion, deployment, paid/model/search requests, credentials
or privilege changes. Historical two unknown requests / ¥0.002620 hold untouched.

## Fixed inputs and scope

- Bot dependency merged conflict-free on this task branch only:
  `79cf88974f6a44cb8e30df0e81d827a9376303b1` (merge `5378c456dce4c2d26a0331329b06313e903f020f`).
  It owns the only Bot draft, suggestions, selection invalidations and creation observations.
- Group Rust interface read at `2cc5df1c900cd2977e8bdf4ca623e82f673a50b7`;
  no duplicate Kotlin governance engine, queue or budget ledger. Group UI is a
  controlled display/local selection surface; no FFI added.
- Theme public contract read at `290fcdc593cb67de66a4238d5ce93acd6ad5e1e3`.
  Uses FoundationTheme/controls without changing ui/system or adding theme tokens.
  At final verification that branch publishes README contract only; actual component
  source is an outstanding dependency. This branch alone is not Android-buildable.
- Full UI specification and actual PNG 06/09 read/viewed from archive
  `399e3094740c8fcf1783797f0d0ae1f076dfd123`; later brand archive announcement
  `400e206135690c284c8402521e3135cfb7bfaee8` acknowledged. PNGs are design
  references, not application runtime evidence. No mascot/logo generated/copied.
- New authored source only `product/ui/configuration/`, with corresponding JVM and
  Android instrumentation checks. No MainActivity/ChatScreen/agents/setup/
  group_governance/ui/system/ui/cards source changed; inherited Bot dependency is
  explicitly separate from authored changes.

## Delivered behavior / host contract

`BotConfigurationEditor` only buffers editable text and delegates all meaningful
validation/selection/unknown rules to BotSetupDraft. Name → purpose → optional
local role suggestions and explicit host skill/material selections → user edits →
final preview. User edits survive back and later; role suggestions cannot overwrite
manual buffers or locked draft fields. Empty/invalid input stays visible with an
error and cannot advance. Unavailable capabilities stay disabled, metadata changes
must be explicitly acknowledged. No auto skill selection, grant, save, create or
start is reachable. Save/create/start buttons have null callbacks.

`BotConfigurationScreen(editor, hostSnapshot, onLeaveWithDraft, onQueryOriginalIntent)`:
host must retain editor on UI thread while navigating, validate account/project scope,
and supply a **new immutable draft.snapshot() after each host-side choice or creation
observation**. Explicit value parameter prevents stable-editor strong skipping.
Caller also triggers observation refresh after querying the original intent. Queries
are capability-gated nullable callbacks, not a create seam. PENDING/UNKNOWN freeze
editing; only original intent query is shown. CREATED and closed drafts are Info,
not Unknown. No process persistence is claimed. Uncommitted text is in the retained
editor buffers, not a durable DraftSnapshot; do not reconstruct editor on tab return.

`GroupConfigurationScreen` receives host-resolved display projection, nullable selected
wire mode, coordinator text and local edit callbacks. No mode is chosen by default.
Wire values exactly match Rust: host_only/fixed/per_task; host_only requires absent
coordinator, fixed requires one. Conversion/validation remains Rust host responsibility;
the UI does not serialize or submit a GroupConfig. Fixed/per-task explicitly show
UnsupportedMode / unimplemented execution. Human administrators are separate from
coordinators. Unknown budget values stay unknown, actual/reserved/ceiling are separate,
stop conditions visible, original request query callbacks only. Save/run stay disabled
in every mode. Display strings never authorize/compute a budget or policy intersection.

## Verification (actual results)

Temporary official Kotlin compiler 2.1.20 downloaded/unpacked under `/tmp/muyon-kotlin`,
using existing Java21; no repo dependencies/lock or system configuration changed.

1. Wrote JVM regression checks before implementation. Initial missing-source compile
   failure was not counted as behavioral RED. Empty API scaffold then compiled and
   failed `back retains user edits...` at first next(), exit1. Implemented against
   that real behavioral RED; final **5/5 PASS** (exit0), independently rerun.
2. Existing Bot dependency checks **11/11 PASS** (exit0).
3. `git diff --check` exit0. Untracked authored files also checked before staging.
4. Android compile and full connected test commands both **NOT_RUN, exit2** because
   existing Gradle8.13 executable unavailable. No SDK/device/Compose screenshot,
   keyboard/200% text/accessibility or successful full Android suite claim.
5. Four added instrumentation tests cover retained edits/back/later, disabled create/
   start, unknown original-intent query, receipt refresh unknown→created, and no-default
   group modes/disabled run. They are **unexecuted**, not acceptance evidence.
6. Non-author independent review found two issues (state mislabeling and host refresh
   observation); repaired here. Exact review/final limits in REVIEW.md.

Reproduction from repo root:

```sh
KOTLINC=/tmp/muyon-kotlin/kotlinc/bin/kotlinc bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/configuration/run-offline-checks.sh
KOTLINC=/tmp/muyon-kotlin/kotlinc/bin/kotlinc bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/agents/setup/run-offline-checks.sh
(cd apps/muyon_android && ./gradlew :app:compileDebugKotlin --offline)
(cd apps/muyon_android && ./gradlew :app:connectedDebugAndroidTest --offline)
git diff --check
```

## Remaining blockers / sole shell integrator handoff

- Compose source must be combined with actual Foundation implementation, then compiled
  and instrumented on Android. Current partial source is not production UI acceptance.
- ui-shell owns screen routing, scope-bound retained editor/ViewModel, immutable host
  snapshot publication, lifecycle/back/keyboard ordering and original receipt callbacks.
  No shell entry was added here. Current BackHandler handles editor steps only;
  host must verify IME dismissal before navigation on device.
- Bot durable restore/save/create and group trusted snapshot/FFI/persistence/real gateway,
  cost proof, stop implementation, leader handoff are absent. Keep action gates closed.
- Group preview controls accept parent local state only. Human-management authorization,
  exact current schema/revisions, fixed/member identity and host_only coordinator clearing
  must be validated by trusted Rust boundary before any future save, never inferred here.
- Original brand assets can be supplied by shell later; function pages intentionally
  contain no substitute mascot or logo. No hardcoded business records/amounts added.
- Independent integration, runtime visual review, remote CI terminal state and Leader B
  review remain required. This task does not merge itself or declare all UI complete.

Temporary-copy mutation probes (no tracked source mutation): skipping forward transition
was detected (exit1); dropping manual role on back detected (exit1). Removing the UI
wrapper's redundant pending guard survived (5/5 pass) because the underlying
BotSetupDraft editable guard still rejects transitions. Reported as a surviving
redundant-guard mutation, not claimed as full mutation coverage.

Post-review follow-up: a fourth instrumentation method now covers a retained mounted
editor receiving host snapshot changes REVIEW→UNKNOWN→CREATED. Source reviewed only;
execution remains NOT_RUN with the same environment blocker.
