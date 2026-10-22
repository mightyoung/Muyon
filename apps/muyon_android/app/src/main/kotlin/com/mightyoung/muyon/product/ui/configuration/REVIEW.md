# Configuration UI independent review — 2026-10-22

Independent reviewer: `/root/configuration_review`, separate from implementation author. Reviewed working tree on `task/ui-agent-configuration-20261022`; review is of the current files, not an immutable final commit. Only this report was written by reviewer; no production/test files changed or commits made.

Scope: BotConfigurationEditor.kt, BotConfigurationScreen.kt, GroupConfigurationScreen.kt, ConfigurationChecks.kt, run-offline-checks.sh and newly added ConfigurationScreenTest.kt. Bot dependency fixed at `79cf88974f6a44cb8e30df0e81d827a9376303b1`; group Rust contract read at `2cc5df1c900cd2977e8bdf4ca623e82f673a50b7`; theme public API read at `290fcdc593cb67de66a4238d5ce93acd6ad5e1e3`.

## Findings and repair recheck

1. **Medium, corrected in reviewed source:** initial BotConfigurationScreen rendered every noneditable draft with `FeedbackKind.Unknown`, including a CREATED receipt and explicitly cancelled draft. That mixed known closed/created state with an unknown creation result. Recheck confirms explicit cancelled → Info, CREATED → Info, PENDING → Loading, UNKNOWN → Unknown branches. No create or start callback is introduced. This correction is statically confirmed; rendering remains unverified.
2. **Medium, corrected at interface-contract level:** initial screen accepted only the mutable plain-Kotlin editor and relied on parent recomposition to observe host-side creation/choice changes. In-place draft mutation is not observable Compose state; unchanged editor arguments can be skipped. Recheck confirms a required immutable `hostSnapshot: DraftSnapshot` parameter, scope/draft identity check and explicit host requirement to publish a new snapshot after creation observations or `offerChoices`. The value parameter changes when status/revision changes, while the local counter refreshes UI edits. Screen renders from one live draft snapshot during the UI-thread invocation. The host must actually observe and publish the required snapshots; no host integration exists in this slice. Compose runtime update behavior still requires an instrumentation test.

No remaining blocking code finding identified within this offline slice by static review. This is not whole-product approval or Android UI acceptance.

## Independent validation

From `/workspace/Muyon`:

```sh
KOTLINC=/tmp/muyon-kotlin/kotlinc/bin/kotlinc bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/configuration/run-offline-checks.sh
git diff --check
```

Both initial and repaired-source independent runs: **5/5 PASS**, exit 0. Covers user role/back retention, no authority inferred from name, preview cannot create/start, blank input blocks advance, unknown original-intent freeze, and unavailable choice rejection. `git diff --check`: exit 0.

From `/workspace/Muyon/apps/muyon_android`:

```sh
./gradlew :app:compileDebugKotlin --offline
```

**NOT_RUN**, exit 2: `set MUYON_UI_GRADLE to the existing Gradle 8.13 executable.` An earlier command issued from the repository root failed because `./gradlew` is not there; the corrected command above is the relevant environment result. No Android compile, full suite, Compose test, emulator/device or screenshot result is claimed.

ConfigurationScreenTest.kt now adds four instrumentation cases: back/later draft preservation, querying unknown original intent, a host-published status transition through the same mounted editor, and group no-default/disabled run. All four were read, not executed. The fourth method added during review, `hostReceiptRefreshChangesUnknownToCreatedWithoutRecreation`, keeps the editor reference fixed, publishes immutable snapshots through `mutableStateOf`, and asserts REVIEW → UNKNOWN → CREATED feedback plus absence of the obsolete unknown message and next-step action. It uses only passive local observations of the same original intent; it makes no create/start call and does not remount the editor. Static incremental review found no new issue. The pending state is traversed inside one runOnIdle block rather than asserted as a separate rendered frame. Runtime correctness remains NOT_RUN and must be verified before UI acceptance.

## Contract and boundary assessment

- Bot uses the actual BotSetupDraft for steps, suggestions, revision validation, selection and creation observations. Buffers preserve user edits without adding an independent authority/unknown model. Editable actions reject pending/unknown; only the original intent query is exposed. Save/create/start callbacks are absent and their buttons disabled.
- Group wire strings match Rust `Mode::as_str`: `host_only`, `fixed`, `per_task`. UI distinguishes human administrators from coordinator members, states fixed/per_task execution unsupported, host_only empty coordinator and fixed required coordinator constraints, and shows host-supplied permission/budget/stop fields with unknown fallbacks. It does not call Rust, persist settings, validate trusted snapshots or run groups. The host remains responsible for actual Rust validation and all authority checks.
- Group mode callback is local draft selection only. No production group scheduler, accounting owner, FFI or gateway has been added. Rendering the provided historical request IDs is read-only; query callbacks must be resolved by the trusted host to the original receipt path.
- Initial theme-contract review found only README.md at `290fcdc593cb67de66a4238d5ce93acd6ad5e1e3`. That source-availability blocker is resolved by the actual foundation dependency `2aa95ba7ab74ea11f9a89a42d2568650363e6c17`, merged by `88e68f8b504db2742e169a351b77634fb68c1549`; see the final incremental review below. Actual Android composition/API compatibility has still not been compiled because Gradle/Android runtime verification remains unavailable.
- No real model/search request, credential configuration, payment, deployment, branch merge/push or historical unknown retry was performed by this reviewer. Historical two unknown requests and ¥0.002620 reservation remain untouched.

Disposition: **PARTIAL / HOLD for integration and visual acceptance**. Author may deliver the independently reviewed offline source and tests with the above limits. Require successful actual Android compilation, execution of all four instrumentation cases including the runtime update test, device/font-size/accessibility and screenshot verification, plus trusted host integration before claiming production configuration works.


## Final dependency/background incremental review

Reviewed actual merged foundation source from `2aa95ba7ab74ea11f9a89a42d2568650363e6c17`, dependency merge `88e68f8b504db2742e169a351b77634fb68c1549`, and configuration background follow-up `7ecae524d655db9f892ba64932a0de9e680b5ce4`. This increment was static review only; no Android installation, test execution or commit was performed by this reviewer.

- `FoundationTheme`, `FoundationButton`, `FoundationTextField`, `FoundationSelection`, `FoundationTag` and `FoundationFeedback` actual signatures and enum values match the configuration call sites, including positional arguments, nullable callbacks, named `kind`/`enabled` arguments, and status messages. Their preconditions are satisfied by the visible hardcoded labels/details. Null callbacks are disabled by actual foundation controls; the configuration's save/create/start actions remain unavailable.
- Both screen Columns now apply `background(MaterialTheme.colorScheme.background)` inside `FoundationTheme`. Actual theme sets that property from the soft light/dark palette. This resolves relying on an external surface's background and does not modify foundation-author files. Color appearance and rendered contrast were not measured by this reviewer.
- All four ConfigurationScreenTest methods were reread against the actual controls. The same-editor host snapshot update case and local draft/group capability boundaries remain as previously described; no new issue identified in this increment.
- The author reports correct-directory compile and connected-test attempts still returned exit 2 / NOT_RUN because Gradle 8.13 is missing, and Python `test_contrast.py` passed 1/1. These are author-reported incremental results, not independently rerun here; the prior independently observed compile NOT_RUN and offline 5/5 results above retain their exact scope.

Final disposition remains **PARTIAL / HOLD for integration and visual acceptance**. Theme source absence is resolved. Missing actual Android compile/runtime/device/accessibility/screenshot evidence and trusted shell integration remain open; four instrumentation methods present in source do not count as four passing tests.
