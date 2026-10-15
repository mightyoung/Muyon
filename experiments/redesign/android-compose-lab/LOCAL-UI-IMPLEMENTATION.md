# Original local frontend increment · 2026-10-15

The user's later09:05 instruction authorizes reasonable original frontend behavior when complete recovery is unavailable. Missing screenshots and Widget trees therefore qualify fidelity claims; they do not stop implementation. This increment uses the existing four-destination Muyon contract and the reference application's already inventoried conversation/input/sheet operating concepts. Layout, spacing and component grouping are original and adjustable, not measured reference pixels. No third-party source, font, icon or illustration is imported.

## Working local interactions

| Surface | Implemented behavior | Explicit boundary |
|---|---|---|
| Assistant | Create local conversations; enter raw text; save a user note; browse notes; open record details | Saving means current-memory user text, not submission, task creation or an assistant response; send remains disabled |
| Conversation sheet | Search titles/saved text, select a conversation, create one, stage and confirm/cancel rename | Per-conversation unsaved input, scroll and last input focus stay separate; no server history is claimed |
| Input options | Open/dismiss a capability sheet; show local note availability and disabled model/attachment controls | No file picker, model call, credentials, permission grant or execution action |
| Tasks | Select all/running/waiting-for-confirmation filters and retain the selection | No task service connected; no fabricated tasks and no claim that an empty backend result was fetched; refresh disabled |
| Data | Search only user-saved notes, inspect their exact content, return to the originating conversation | Unsaved composer text is not a saved record; no knowledge-base, file or business data is read |
| Settings | Switch system/light/dark local theme; show actual in-memory conversation/note counts | Preferences and content are not durable; closing/recreating the app may lose them |
| Navigation | Assistant/tasks/data/settings and899/900dp bar/rail boundary retained | WorkBuddy's exact tab order/layout is not claimed; Rust remains NOT_CONNECTED |

`LocalUiState` and its note/conversation IDs are UI memory, not production Rust DTOs. Notes have only local ID and user text, with no role/result/receipt/status authority. All host-dependent actions remain unavailable. A late scroll update explicitly targets its original conversation instead of overwriting whichever conversation is active later. Automatic scrolling is limited to a newly saved local note in the mounted page; returning to a conversation does not intentionally scroll to its end.

## Actual verification and pending checks

- Existing16 named state checks remain present and pass.
- Added22 named local-UI checks actually compile and execute using the already installed official Kotlin2.2.20 compiler, JVM target17 and Java21 runtime. The initial no-op implementation compiled and failed16/22 named checks; the final state implementation passes22/22. These are named cases, not a claim of22 independent security boundaries.
- Cases cover exact UTF-16 drafts; blank-save rejection; local note preservation and nonduplication; ordered IDs; conversation creation/selection; independent draft/focus/scroll memory including a late inactive scroll callback; search; staged/cancelled/confirmed rename; exact note detail/return binding; invalid IDs; local theme/filter retention and disconnected host capability.
- A later callback regression was reproduced with the old captured-memory wiring: the existing raw-draft case failed after draft→scroll→focus, and the existing conversation-memory case failed after focus→scroll→draft (**2/22 named cases failed**, compiled assertion failures). The fixed pure callback binding captures only the conversation ID and reads the latest state on each event; draft/focus reducers merge just their field. Both event orders now preserve raw input, focus and scroll, and a late event for conversation1 cannot overwrite conversation2. Total named-case counts remain16+22; this proves callback/state sequencing, not Android event delivery. Logs: `adapter-snapshot-red.log`, `adapter-snapshot-green.log`.
- Final local command: `MUYON_UI_KOTLINC=/tmp/muyon-native-ui-tools-20261015/kotlinc/bin/kotlinc MUYON_UI_OUTPUT=/tmp/muyon-native-ui-tools-20261015/local-ui-checks bash experiments/redesign/android-compose-lab/run-state-checks.sh`. Logs stay in that tool directory as `local-ui-red.log`, `local-ui-green.log`, `local-ui-final.log`; no binaries/logs are committed.
- Workflow YAML, every embedded shell step, both local shell scripts, owned-path diff, no-permission manifest and `git diff --check` were checked. The dedicated workflow now requires both the16/16 and22/22 success markers in addition to Gradle exit0.
- Four instrumentation test methods are source only: retained draft/focus/899→900, local save/details/return, two conversation drafts/rename cancellation, preferences/unavailable capabilities. They await normal remote source compilation. **No Android instrumentation execution, installation, rendering, IME, TalkBack or device interaction occurred.**

The earlier CI run38707183090 proves the prior451b3a2c baseline compiles. It does not prove this increment compiles; the root sole pusher will run the same independent normal CI against its new exact head. No local Gradle/SDK installation or build was performed. Complete reference fidelity, durable storage, native Rust integration and connected business behavior remain separate work.
