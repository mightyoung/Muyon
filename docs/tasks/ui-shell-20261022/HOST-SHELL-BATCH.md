# Host-backed memory configuration and original-request candidates

This slice continues overall UI development from98baa979, following the complete
U01–U17 gap plan. It is not overall product completion or APK acceptance.
Exact host dependency a1752fc7f3a0471413c5afd2a32bf152078b21fd is combined by ordinary
merge097b86d7 on task/ui-shell-20261022. No main/develop integration.

## Production changes

- MainActivity obtains actual workspace from health and existing conversation UUID
  from the current conversation preference. Missing identity closes configuration
  instead of making an application/package identity. Business initialization is unchanged.
- Bot configuration uses HostSetupController and the real finite chat_setup_draft
  endpoint as its sole reducer. Name/purpose/role buffers remain unsent until explicit
  confirmation. Actual steps, revision, local template token and cancellation/resume
  are projected from host. UI creates no agent, intent, component binding or receipt.
- Each mutation captures the displayed local draft identity/revision, and template
  adoption captures that suggestion token. Duplicate/busy/stale actions do not issue
  another IPC operation. Unknown mutation requires reading the original ID; no replay.
- ViewModel retains text and passive recovery identity, never a live controller.
  Leaving closes controller and invalidates callbacks. Re-entry first reads the same
  ID. Changed/expired scope retains the old identity and explains non-recovery;
  reopening the current host draft requires explicit abandonment of this view's
  recovery binding, and does not claim a fresh ID (open may reuse same-scope draft).
  Text buffers survive local navigation/Activity recreation, not process death.
- Host updates replace only text buffers without unsent edits. Manual role text
  blocks adopting a stale suggestion. Missing capability/material metadata and
  save/create/start are accurately unavailable. Group preview remains non-executable.
- The explicit original-request snapshot gesture reads chat_card_candidates. Strict
  decoder checks exact request/scope, original native child conversation, finite kind,
  null binding, disabled actions and observation consistency. The displayed candidate
  can explicitly read chat_snapshot with its captured original ID. No typed-card
  action is enabled; native configuration identity is descriptive only.
- A failed local-record refresh retains last observed real content and labels it as
  previous content; project changes still clear their own scope. No fake history.

## Verification and evidence

Actual Kotlin2.2.20 + org.json20250517, JVM17, -Werror:

```bash
KOTLINC=/workspace/ui-shell-tools/kotlin-2.2.20/kotlinc/bin/kotlinc \
JSON_JAR=/workspace/ui-shell-tools/json-20250517.jar \
bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/shell/run-host-shell-checks.sh
```

Both executable runners PASS; evidence/host-shell-final-green.log. They compile the
actual ProductChatRuntime/SendGate/HttpsTransport/BotSetupDraft and new consumers.
Local setup forbids every native call. Candidate fixtures use a private fake native
port and in-memory dummy test vault only; transport throws, no real configuration,
model/search request, historical unknown lookup, reservation or ledger mutation.
Tests cover exact CAS/stale and duplicate clicks, local template token/manual text,
unknown-after-apply original read, same-CAS immutability, closed-view delayed result,
re-entry original-ID recovery, released session, original request/config after later
prepare, scope mismatch, duplicate observation mismatch and closed action capability.

Initial implementation RED/GREEN: host-setup-controller-red.log / -green.log,
request-candidates-red.log / -green.log. A later real regression exposed completion
publication order: busy=false preceded snapshot/needsRead updates. Raw failure is
host-shell-completion-publication-red.log; source now publishes busy=false last,
and final runner reruns the exact regression. Do not erase or count that RED as PASS.

The config-draft-store-{red,green}.log and config-draft-restore-red.log files are
superseded prototype investigations, not current production features/tests. That
append-only file-store prototype is kept outside this worktree under task tools;
no second persistence truth or restore reducer is shipped. Persistence is being
implemented by the original host owner and needs its reviewed exact API.

Actual Android attempt (from apps/muyon_android):

```bash
GRADLE_USER_HOME=/workspace/ui-shell-tools/gradle-cache \
MUYON_UI_GRADLE=/workspace/ui-shell-tools/gradle-8.13/bin/gradle \
./gradlew --offline --no-daemon --console=plain :app:testDebugUnitTest \
 :app:compileDebugKotlin :app:compileDebugAndroidTestKotlin \
 :app:connectedDebugAndroidTest :app:lintDebug
```

Exit1 before product compilation: com.android.application8.11.1 could not resolve
from configured Google/Maven/Gradle plugin repositories. Raw host-shell-android-build.log.
Previously the official sdkmanager attempt at writable task SDK root failed creating
its internal bin directory with Read-only file system/os error30. That step remains
stopped; no workaround, permission escalation, license acceptance or SDK relocation
retry. This is filesystem failure, not approval-review denial. Android compile,
instrumentation, IME/back/TalkBack/rendering/screenshot/APK validation remain NOT_RUN.
Updated instrumentation targets are source only, not a passing behavioral TDD cycle.

Independent review records and rerun output are in HOST-SHELL-INDEPENDENT-REVIEW.md
and evidence/host-shell-independent.log. Review found and closed loss of recovery
identity on leaving, and wording that incorrectly promised a new draft for open.

## Continuing dependencies and ownership

This fixed slice should be reviewable now rather than waiting indefinitely for APIs.
Overall UI development continues. Document preview/page/zoom/sidecar annotations
are owned by the separate product/ui/documents reader worker. Its real interface and
authorized document identity/storage producer are pending; shell will wire the exact
reviewed interface, not manufacture revision/digest/anchors or a second document
store. Existing research/PDF route remains. Host persistence follows in its next API.
Typed cards still lack producer binding/revision facts. Full task/source/attachment/
receipt/report actions stay gated until those exact facts exist. Formal save/create/
run and group fixed/per_task execution are not supplied by this memory API.

No real model/search request, paid CI/dependency, deployment, credentials, privilege
change, force push, deletion or develop/main merge. Historical two unknown requests
and held ¥0.002620 are untouched. Parent's complete gap/owner plan remains authoritative.
