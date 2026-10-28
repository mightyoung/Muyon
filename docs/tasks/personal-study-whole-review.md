# Personal study whole-app review

Independent source review, 2026-10-28. Reviewed the actual working tree based on
`f9be0200`, including the adapter fixes described in the earlier adapter review.
No production files were changed. No Cargo/Gradle/device commands were run, to
avoid interfering with the main agent's builds. Findings below are source-proven
paths; regression cases are proposed, not claimed as executed.

## Findings

### 1. P1 — Restoring onto a new installation can overwrite restored attempts

`crates/muyon-core/src/study/mod.rs:283–292`,
`crates/muyon-core/src/study/papers.rs:51–52`, and `mod.rs:45–51`.

Restore retains the backup's generated record IDs but resets its revision to the
destination's old revision plus one. New attempt/session IDs use that revision,
and `put` replaces an existing matching ID. A minimal reproducible sequence is:
import a paper (revision 1), start `attempt-2` (revision 2), export, restore into
an empty database (revision becomes 1), start another attempt. The new
`attempt-2` silently replaces the historical attempt and its answers.

Fix: advance the revision beyond both source and destination revisions and make
generated record IDs collision-safe. Regression: restore a backup with answered
attempts into an empty and an older destination, start another attempt/session,
and assert all restored records and answers remain unchanged.

### 2. P1 — Published study events feed back into planning and accumulate

`apps/study_android/app/src/main/java/com/mightyoung/muyon/study/adapters/Providers.kt:79–91,131–155`,
`crates/muyon-core/src/study/scheduler.rs:40–63,180`.

Calendar sync imports app-managed study events as ordinary busy commitments. A
subsequent proposal subtracts those events and reallocates the same unfinished
work elsewhere. Every proposal generates new block IDs using the revision;
publication derives remote event identity from those IDs and only inserts or
checks currently submitted blocks. It never discovers/reconciles superseded
app events. Publish, sync, confirm a new proposal, and publish again therefore
moves work away from its own old allocation and leaves both generations on
Google Calendar. Even re-evaluating an unchanged unsynced plan gives new IDs and
can duplicate identical appointments.

Fix: persist stable local/remote block identity and distinguish intact managed
events represented by the plan from independent busy events. Build a reviewed
publication reconciliation with explicit retained/created/superseded/conflicting
events; use remote signatures/ETags to protect manual edits. Never automatically
retry an uncertain write. Regression: unchanged republish, publish-sync-replan,
changed/removed blocks, remote manual edit, and uncertain-create retry must not
duplicate or self-displace work.

### 3. P1 — An invalid AI task ID throws on the main thread

`apps/study_android/app/src/main/java/com/mightyoung/muyon/study/MainActivity.kt:64–68,91`.

The AI handler posts its task merge to `runOnUiThread`; the merge deliberately
throws `require` for an unknown nonblank task ID. `background` catches exceptions
only on its worker, so the posted exception escapes and crashes the Activity.
Invalid model output is a supported failure case, not an exceptional user action.

Fix: construct and validate the complete immutable preview in the worker's
guarded block, then post only the finished preview assignment. Guard other posted
work that can throw. Regression: model returns an unknown ID or malformed task;
the app must show an error, preserve state, and remain interactive.

### 4. P2 — Supported backup exports are not consistently restorable

`apps/study_android/app/src/main/java/com/mightyoung/muyon/study/StudyFiles.kt:43–52,69–70`,
`crates/muyon-core/src/study/mod.rs:293–295`,
`crates/muyon-study-ffi/src/lib.rs:23–26`.

The state owner permits 24 MiB of state, while ZIP restore rejects `state.json`
over 16 MiB. Export counts only resource bytes against 256 MiB, whereas restore
counts resources plus state against 256 MiB. The FFI also caps the entire restore
command at 24 MiB, leaving less capacity than a 24 MiB state once command framing
is added. Successful exports can consequently fail their own restore path.

Fix: define shared/documented limits including state, resources, archive overhead
and command framing; ensure every accepted/exportable state is restorable.
Preflight export before writing a nominally successful archive. Regression:
state above 16 MiB, state near the native limit, and aggregate attachments plus
state near 256 MiB must either round-trip or fail export clearly before delivery.

### 5. P2 — Cloud backup paths buffer several copies of large archives

`apps/study_android/app/src/main/java/com/mightyoung/muyon/study/MainActivity.kt:58–61`,
`apps/study_android/app/src/main/java/com/mightyoung/muyon/study/adapters/Providers.kt:98–104,114–118`.

The Activity downloads up to 256 MiB into a byte array, despite the available
streaming `driveDownloadTo` helper. Upload builds an archive in memory, copies
it to a byte array, builds another full multipart buffer, and copies that buffer
again. Large accepted backups can exhaust Android's heap; `OutOfMemoryError`
is not handled by the `Exception` catch and kills the process.

Fix: use cache staging and streamed download/upload bodies, or choose a much
smaller enforced end-to-end cap that matches a measured memory budget. Regression:
restore/upload an incompressible near-limit backup under an emulator with a
representative heap, checking peak memory and cleanup of partial staging files.

### 6. P2 — An exam without a date is accepted and then cannot be repaired

`crates/muyon-core/src/study/mod.rs:126–133,303–332`,
`apps/study_android/app/src/main/java/com/mightyoung/muyon/study/Components.kt:62–69`.

The goal editor allows choosing exam and leaving the date blank, and core goal
validation requires only ID/title. Once saved, the immutable-exam guard prevents
adding the missing date. Scheduling treats the missing exam date as infinity.
This creates an unconstrained exam goal that ordinary editing cannot repair.

Fix: require a valid positive exam deadline before committing an exam goal; use
the same validation during restore. Regression: exam with absent/null/zero date
is rejected without changing revision; a dated exam remains immutable.

### 7. P2 — Question navigation does not persist the current position

`apps/study_android/app/src/main/java/com/mightyoung/muyon/study/DetailScreens.kt:73,86,94`,
`crates/muyon-core/src/study/papers.rs:88–90`.

Previous/Next only change Compose state. The database index changes only when
an answer is edited. Navigate to another question without answering, leave the
attempt and reopen it: it resumes at the last answered index. `rememberSaveable`
is not durable attempt storage, including after leaving this composition or a
cold restart.

Fix: add a validated progress/navigation command that saves the index without
rewriting an answer; invoke it on navigation. Regression: navigate several
unanswered questions, leave/reopen and cold-restart, and verify the exact index
and existing answers.

### 8. P2 — AI confirmation hides the fields that will actually change

`apps/study_android/app/src/main/java/com/mightyoung/muyon/study/Components.kt:84–87`,
`apps/study_android/app/src/main/java/com/mightyoung/muyon/study/MainActivity.kt:66–67,82`,
`crates/muyon-core/src/study/mod.rs:185–200`.

The shared import review renders only task titles and an AI-authored summary.
The actual suggestion can merge arbitrary task fields, including remaining
minutes, status, deadline, dependencies and goal, and confirmation writes the
whole resulting task. A suggestion with an unchanged title can therefore mark a
task done or change its progress without exposing that change to the reviewer.
The expected-revision check is present, but does not make hidden edits reviewable.

Fix: restrict allowed proposal fields and show explicit old/new values for every
changed field, with creation versus update clear. Regression: a same-title
progress/deadline/status update must show all actual changes before confirmation,
and cancel must leave the task unchanged.

### 9. P2 — Pending document operations are lost across Activity recreation

`apps/study_android/app/src/main/java/com/mightyoung/muyon/study/MainActivity.kt:24–29,31–38,85–94`.

`importKind` is an ordinary Activity field initialized to `plan`. If Android
recreates the Activity while the external document picker is open, the restored
ActivityResult callback processes a paper/resource/backup as a plan. Provider
continuations and preview results also live only on the Activity; asynchronous
callbacks can update an obsolete instance after recreation.

Fix: persist pending operation type through saved state and keep long-running
operation/result ownership in a lifecycle-aware holder. Do not launch permission
UI or apply UI results from destroyed instances. Regression: rotate/recreate
during each picker mode, Google authorization and AI response, then complete the
operation and verify the intended result appears once in the current Activity.

## Required behavior still absent or incomplete

- **Whole remaining plan / non-exam extension proposals:**
  `StudyTime.kt:15` provides only 28 days to the scheduler. No separate long-range
  feasibility evaluation exists. A goal well beyond 28 days can receive a false
  capacity shortage even when ample later capacity exists. Ordinary goal due
  dates affect candidate order but do not produce an extension proposal;
  `scheduler.rs:180` marks late only against the individual task deadline, so a
  task with only an overdue goal date can appear on-time. Calculate feasibility
  to relevant goal/exam horizons and expose explicit suggested goal/task
  extensions with old/new dates before confirmation.
- **Daily minimum diagnostics on zero-capacity days:** `scheduler.rs:192` iterates
  only days with allocated work. A fully busy/unavailable day has no entry and no
  `minimumGaps` warning. Iterate relevant planning days, including zero-capacity
  days, and include the date in the UI warning (`DetailScreens.kt:27`). Test a
  fully blocked day with an active goal minimum.
- **Wrong-answer-focused review:** the wrong-answer destination opens the entire
  original attempt, starting at its saved index, rather than filtering/jumping to
  its `result.wrong` questions (`StudyUi.kt:96–97`). Results identify wrong IDs,
  but a focused review path is not implemented.
- **Durable provider failure freshness:** core has `sync_error`, but no Android
  call site dispatches it. Failed refreshes preserve cached data correctly, yet
  the failure state is only a transient notice and can be overwritten by another
  successful local refresh. Persist provider failure metadata without replacing
  last successful data/timestamp.

## Checked without a new blocking finding

- Proposal confirmation checks the stored base revision; mutation invalidates a
  proposal. Proposals and deterministic scheduling do not mutate actual task
  progress. Locked-block reservations are deducted from new work allocations.
- Existing dated exam goals cannot be postponed by ordinary upsert. Grading
  leaves missing-key and essay questions pending and labels commentary as AI.
- The adapter review's speech-session accumulation/cancellation and notification
  permission callback integrations are now present. Model checksum preparation
  is present; this review does not claim APK/model or microphone device success.
- Calendar fetching paginates and finishes all calendars before committing its
  snapshot. Failed reads preserve local events. Managed-event ownership and
  signatures protect existing events from silent overwrite, but do not address
  the reconciliation problem above.
- Resource restore uses fresh destinations and preserves existing files during
  parsing failure; credentials are outside the exported state. Cancelling a
  successful preview can still leave orphan restored files, so staging cleanup
  should eventually cover cancellation and native restore rejection as well.

## Remaining validation boundary

The main agent owns build/test execution. Device/API checks are still necessary
for clean installation, permission denial/grant, reboot reminders, microphone
recording, Activity recreation, Google ownership/authorization, Drive streaming,
and external publication reconciliation. This report does not substitute source
inspection for those checks.
