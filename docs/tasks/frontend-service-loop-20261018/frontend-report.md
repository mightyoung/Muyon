# Frontend binding handoff

Implemented on the integration branch, preserving Muse layout, four menus, puppy resources and local Save behavior.

- `MuyonLabShell` obtains the actual `MuyonLabApplication.chats`, observes its application-owned snapshot, and keys all submit/cancel/lookup/display actions by the captured conversation ID. No mock execution or success fallback is used.
- `ChatPage` has a distinct Send action, Cancel while active, and lookup-only recovery for UNKNOWN. It echoes the submitted text and independently renders answer, projection, original receipt, request/run IDs and error reason. Switching chats only changes the displayed map entry; screen disposal does not cancel native work.
- Synthetic schema12 / offline / no real model disclosure is always visible. The existing layout sample remains explicitly separate. Save remains a local note action.
- Input policy enforces nonblank / 4096 UTF-8 byte bounds before dispatch and blocks resubmission for active/UNKNOWN requests. Host admission remains authoritative.

## Verification

| Check | Result |
| --- | --- |
| Initial test attempt without compiler on PATH | NOT_RUN, exit 127; `frontend-logs/initial-kotlin-check.log` |
| Existing pure Kotlin state suite using `/workspace/toolchains/kotlin/kotlinc/bin/kotlinc` | PASS; `frontend-logs/state-checks.log` |
| New standalone frontend input/status/conversation dispatch checks | PASS, 21 assertions; `frontend-logs/frontend-checks.log` |
| `git diff --check` | PASS |
| Compose compilation, Android device / Binder / native tool execution | NOT_RUN by this frontend worker; integration owner must run composed build/device checks |
| Real model API | NOT_RUN, no call attempted |

The frontend tests exercise pure presentation/dispatch policy only. They do not certify Service authority, durable recovery, native invocation, receipt validity or Android rendering. The IPC owner owns request persistence, identity checking, event ordering, fresh disclosure checks and cancellation reconciliation.

Reproduction: run existing `run-state-checks.sh` with `MUYON_UI_KOTLINC` above. For the new checks, compile state main sources plus `FrontendChatChecks.kt` and a one-line main calling `com.mightyoung.muyon.androidlab.runFrontendChatChecks()` with `-jvm-target 17 -include-runtime`, then run that jar. No Gradle/application/shared runtime file was edited by this worker.
