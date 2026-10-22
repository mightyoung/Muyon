# Screenshot continuation independent review

Scope: uncommitted changes to ConversationShell.kt, ShellInputDock.kt and
ConversationShellTest.kt against `90df4d09d75537786d64e703dd94ca2abe7319c2`.
Read-only production review; only this report and the named independent log written.
No commit, SDK download/license acceptance, APK execution or real service call.

## Static conclusion

No blocking or Important finding in this bounded accessibility change.

- TextField adds a stable “消息草稿” contentDescription using additive semantics.
  Existing editable text, input actions, onValueChange and send enabled/callback
  remain unchanged. It does not clear TextField semantics or turn typing into send.
- Page title and two navigation sections use the existing heading semantics API.
  Layout, token values, tab selection, modal focus exclusion and navigation actions
  are unchanged.
- Nonblank menu notice has LiveRegionMode.Polite. The error text remains visible;
  this change adds an announcement hint without introducing polling or callbacks.
- Two added instrumented tests target stable purpose after typing, disabled preview,
  heading properties and polite live-region properties. The Compose signatures and
  imports have no obvious static mismatch. Tests use a plain local draft with no
  ProductClient or model call.

## Actual independent checks

Executed from /workspace/muyon-ui-shell with fixed Kotlin2.2.20:

```bash
KOTLINC=/workspace/ui-shell-tools/kotlin-2.2.20/kotlinc/bin/kotlinc \
 JSON_JAR=/workspace/ui-shell-tools/android-json-0.0.20131108.vaadin1.jar \
 bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/shell/run-reader-surface-checks.sh

KOTLINC=/workspace/ui-shell-tools/kotlin-2.2.20/kotlinc/bin/kotlinc \
 JSON_JAR=/workspace/ui-shell-tools/android-json-0.0.20131108.vaadin1.jar \
 bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/shell/run-host-shell-checks.sh
```

Reader runner exit0 / one PASS; host runner exit0 / three PASS
(controller, request candidates, cold persistence projection). The reader runner
has no JSON dependency; host compiles against the real Android org.json fork.
`git diff --check` exit0. Source/script hashes sampled before and after both runs
are identical. Raw output and hashes: `evidence/screenshot-continuation-independent.log`.
These are regression checks of pure logic, not execution of the changed Compose UI.

Reviewed source SHA256:

- ConversationShell.kt: `d46ca6efcf97a3d1f34d233a7cf83742ab52cb9d14c427627ca4a01bbddcc00a`
- ShellInputDock.kt: `a19e2dfd8d490ab2f2168de1535f3da4c84fe3f6a732e73ce57e2b1630258a3f`
- ConversationShellTest.kt: `f6df3af2ca2de6322eff475c633c7d46232d8d78068cbe6fe4d4dbb5cf5f5489`

## Android and screenshot limits

Inspected the author's actual `evidence/a11y-test-first-android-block.log`: build
failed resolving com.android.application8.11.1 before source/test compilation.
The new Android tests are **NOT_COMPILED / NOT_RUN**, with no behavioral RED or
GREEN claimed. This reviewer did not rerun Android Gradle or bypass the pending
SDK installation decision. TalkBack traversal, spoken text and dynamic polite
announcements still need actual device validation; property assertions alone do
not prove them.

No screenshot was captured for this change or for214b4031/90df. Earlier07fd
screenshots remain historical evidence with synthetic test roles, not validation
of this patch. Device/runtime/screenshot acceptance remains blocked on the actual
Android environment and exact-source execution.
