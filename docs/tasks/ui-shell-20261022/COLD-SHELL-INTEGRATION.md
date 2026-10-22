# Cold-preparation consumer: strict shell decoder and passive UI

Fixed host input1b097e3b519f74dad462390dabe8cd05e942c0ab was ordinarily composed as
9b5abdc3f13b2a70df244ced07b089ac5cf576b5 on task/ui-shell-20261022 after parent assignment.
Read COLD-PREPARATION-CONSUMER.md and the earlier shell PERSISTENT-HOST-DECODER-PLAN.md.
Runtime/Service/persistence owner source is unchanged from that fixed input. This adds
shell-only decoder/state rendering, not the missing fifth native/generated binding.

## Production behavior

HostSetupSnapshot now carries a passive HostDraftPersistence projection. It requires
explicit typed persistence fields and exact finite historical-outcome keys. Stored and
export/editor revisions are canonical bounded decimal strings, separate from integer
local CAS. Null/missing, malformed UUID, owner/status/action mismatch, contradictory
pending+terminal same attempt, impossible proposed/committed cursor, cold+ack, history
claiming noncommit as committed, and same-CAS edited content fail closed.

Same-CAS storage observations are permitted without accepting same-CAS name/purpose/
role/step/suggestion changes. Stored cursor cannot regress; a known outcome for the
same attempt cannot reverse phase/binding or lose history. A pending pointer cannot
silently switch to another attempt. UI does not synthesize a current acknowledgement
from revision equality. A cold outcome never acknowledges current editor, including
actual native-projected0/0 history. A live host acknowledgement also requires matching
current memory/editor facts and all current unsent text buffers before the screen
calls the visible editor saved; otherwise it describes only the acknowledged host version.

The host codec remains responsible for full namespace/registry/archive-digest binding;
those raw fields are not present in the shell history projection. Shell validates the
released projection and its relationships, not independent full native receipt proof.
The trusted host's current-editor acknowledgement and cold flag are instance evidence;
UI never derives them from numbers or treats a receipt as execution/creation authority.

HostSetupScreen displays actual unavailable/editing/unknown/saved and historical
committed/not_committed facts. Proposed revision is explicitly not committed storage.
Unsent text remains separately retained. No local file store/reducer, fake business
identity, actual fee, permission or successful save callback is introduced.

**All three persistence operations remain closed:** save, restore and query_original_save
may be decoded as host-advertised facts but are absent from controller mutation whitelist.
All three UI buttons stay disabled. Plain readOriginal sends operation=read with exact
original local_draft_id; it never sends query_original_save. It cannot perform the native
lookup that may fence an original preparation. The only explicit query in the new tests
is a clearly isolated synthetic-boundary fixture call, not an app callback.

Service still has verified=false and prepare throws local_draft_prepare_binding_pending.
No Runtime/Service edit, unconditional bool flip, reflection, placeholder ProductCore,
generated-binding repair or ordinary URI/PFD authority shortcut is made by shell.

## Actual test evidence

From repository root:

```bash
KOTLINC=/workspace/ui-shell-tools/kotlin-2.2.20/kotlinc/bin/kotlinc \
JSON_JAR=/workspace/ui-shell-tools/json-20250517.jar \
bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/shell/run-host-shell-checks.sh
```

Actual Kotlin2.2.20 -Werror JVM17 compiles fixed Runtime/canonical Bot/archive/codec/session/
normalized save state plus shell. Three main runners PASS, exit0:

- Existing memory controller CAS/manual buffer/token/re-entry/closed-callback checks.
- Original-request candidate identity/scope/closed actions/unknown actual-charge checks.
- New cold shell consumer: actual Runtime + native codec + canonical archive with a
  synthetic private local port. Open/plain read call lookup zero times; even this fixture's
  verified host cannot bypass the shell's persistence dispatch gate. A fixture-explicit
  original reconciliation emits real cold historical committed0/0 projection, then ordinary
  read observes storage-only changes at same CAS with no additional lookup. History does
  not mark current editor saved. Typed malformed/contradictory/history binding and rollback
  cases reject. Additional live-ack/noncommit decoder cases are test-only shape mutations;
  they are not real product save/native integration results.

Raw original behavior RED: evidence/cold-shell-red.log (old decoder cannot accept actual
cold projection, compiled successfully). Reviewer-driven coherence regression RED:
cold-shell-coherence-red.log (same attempt pending+terminal accepted), then fixed final
cold-shell-final-green.log. Intermediate cold-shell-green.log is retained separately.
Independent final result and source hashes: COLD-SHELL-REVIEW.md and
 evidence/cold-shell-independent.log. No environment/compiler failure is counted as RED.

Actual combined-source Android command from apps/muyon_android:

```bash
GRADLE_USER_HOME=/workspace/ui-shell-tools/gradle-cache \
MUYON_UI_GRADLE=/workspace/ui-shell-tools/gradle-8.13/bin/gradle \
./gradlew --offline --no-daemon --console=plain :app:compileDebugKotlin \
 :app:compileDebugAndroidTestKotlin :app:connectedDebugAndroidTest
```

Exit1 before product compilation, unresolved com.android.application8.11.1. Raw
cold-shell-android.log. Product Android/Compose/Service/generated-binding compilation,
actual SQLite/FFI five-method integration, device/IME/rotation/TalkBack and UI screenshots
remain NOT_RUN. Instrumentation gate expectations are source only; no behavioral TDD
or APK claim. Prior SDK read-only error is not retried or bypassed. Raw Gradle trailing
whitespace is preserved; scoped source/docs whitespace checks exclude that raw log.

## Remaining integration gates

B must supply actual fifth FFI/generated binding. Host owner must release that exact
Service composition and verified gate with native/Android acceptance; shell must not
interpret synthetic verified fixtures as that release. Enabling explicit save/query/
restore requires a later reviewed controller transition slice, including original attempt
routing, unknown no-replay, exact export/current editor receipt and explicit restore's
intentional reducer-revision reset. Restore is currently blocked, so the existing
anti-rollback rule remains strict rather than globally weakened.

Reader still needs the original owner's controlled FD/access/revision/annotation durable
intent bridge; this batch does not implement it. Overall UI completion and joint Android
acceptance remain open. main/develop untouched; no force push, deletion, deployment,
paid CI, credentials, privilege/network settings, real model/search request, historical
unknown operation query/retry or ¥0.002620 hold change.
