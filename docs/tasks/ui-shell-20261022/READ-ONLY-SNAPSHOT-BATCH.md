# Explicit original-request read-only snapshot integration

Fixed producer combined after parent handoff: initial
`ac55ef65a65baf9499fe2e4b3a63a0baaf827887`, then parent-released fee correction
`98e5b6529cfbd9313c5fea73db168eebcfd4cfbc`. Ordinary merges preserve ownership.
Runtime/Service files exactly match the latter producer source; shell did not edit
those files or any Rust/core ledger. Original held/charged accounting unchanged.

## Actual source behavior

The existing original-request details section offers an explicit local read button.
No read runs automatically on mount, original lookup, refresh, configuration or
restoration. A user click first reads existing local health to capture actual
workspace, then calls chat_snapshot with the captured original request, actual
conversation UUID, nullable project and integer generation returned by chat_scope.
Both stages retain existing mounted callback guards and additionally compare the
still-selected original request/conversation/project/generation. Native child
request conversation stays separate; no replacement intent or component ID invented.

A cross-conversation/session/generation request or recovered historical request
without read origin is unavailable before the producer's local lookup. The UI
therefore allows an explicit read attempt with a real selected scope rather than
misusing display-name origin labels as authority. Workflow display labels can include
suffixes; only the producer's original provenance can establish availability.
Existing global original-result query remains independent and unchanged.

New consumer accepts only schema1/read_only, exact workspace/conversation/project/
generation/request, agent_id=null, intent_id=null, binding=null and capabilities=[].
Foreign/changed/malformed context is unavailable. No CardBinding/CAS/digest/task/
source facts are fabricated; richer actionable cards remain unavailable. The plain
panel has no submit/execute/cancel action. It is a local historical observation,
never current business state, an execution grant or a saved receipt.

Fees: preserve original nonzero reserved amount as integer micro-CNY text, or unknown.
Unknown native default charged0 and positive charged values both remain actual
unknown. Actual charge is accepted only for native completed with attempted Boolean
true and a bounded unsigned integer string. String "true" is not proof. Consumer
records this settlement observation and panel checks it again before displaying.
Cancelled/tool_pending/tool_consumed/failed may have internal accounting, but remain
actual unknown in this conservative projection. No cost/refund/ledger mutation.

Local cancellation intent is labelled only as recorded intent, unconfirmed outcome
and no rollback implication. Full cancellation execution is not wired. Refresh
failure/loading retains previous observations for the same original. Changed original
request hides old observation immediately; identity effects clear view buffers.
Configuration callback invalidation explicitly resets the read busy flag, discards
old callbacks and permits a later manual read. No automatic retry or callback revival.

## Verification actually executed

- Initial API scaffold compiled against real org.json; consumer checks failed at
  `valid original scoped snapshot must remain visible`, exit1. This is a behavioral
  RED, not a missing-source error. `evidence/snapshot-consumer-red.log`.
- Implemented pure consumer checks GREEN, followed by fee-proof and final runner
  checks PASS exit0. Tests cover exact context and malformed generations/schema,
  request mismatch, nonnull bindings/nonempty capabilities/fake intent, unknown
  costs including ledger0 and positive charge, ULong bounds, completed+Boolean true,
  string true refusal, child conversation separation and unavailable pending state.
  Logs: snapshot-consumer-green.log, snapshot-consumer-final.log and
  snapshot-consumer-runner.log. These are offline executable checks, not Android.
- Real producer runtime checks rerun using fixed source98e5, Kotlin2.2.20/JDK21
  and actual org.json20250517: PASS includes native-shaped charge proof, scope,
  absent/pending/unknown, original history, detach, malformed input, search/workflow/
  followup provenance, release and bounded cache. `evidence/host-projection-final.log`.
  Fake private port and forbidden transport only; no actual provider/model/search,
  installed Service/credential or live historical-query operation executed.
- Two Compose panel test targets added: unknown/default0 remains actual unknown,
  local cancel intent is not terminal cancellation, only explicit read callback,
  loading/unavailable preserves observed record and disables read. UNEXECUTED.
  Total shell instrumentation targets now10; no passing Android claim.
- Actual full Android task attempt from apps/muyon_android:
  `GRADLE_USER_HOME=/workspace/ui-shell-tools/gradle-cache MUYON_UI_GRADLE=/workspace/ui-shell-tools/gradle-8.13/bin/gradle ./gradlew --offline --no-daemon --console=plain :app:testDebugUnitTest :app:compileDebugKotlin :app:compileDebugAndroidTestKotlin :app:connectedDebugAndroidTest :app:lintDebug`
  FAILED exit1 before product compilation: AGP com.android.application8.11.1 plugin
  unresolved from configured repositories. `evidence/snapshot-final-android.log`.
  Actual Gradle is present/runs. Earlier SDK read-only filesystem error remains;
  installation not retried, relocated, escalated or bypassed. This is NOT an
  approval-review denial. No Android stub, alternate provider or paid CI workaround.
- Source/document whitespace checks PASS; raw Gradle trailing spaces intentionally
  retained, so whole-archive raw-log whitespace remains nonzero as previously noted.
- Non-author review identified config-invalidated spinner issue; corrected before
  final review. Confirmed final scope/request guards, discarded stale callbacks,
  strict fee observation and unavailable capability gates. Independent consumer
  runner outcome appended when complete; no Android review substituted by static review.

Reproduce pure checks from repo root with existing official tools/artifact:

```sh
KOTLINC=/workspace/ui-shell-tools/kotlin-2.2.20/kotlinc/bin/kotlinc JSON_JAR=/workspace/ui-shell-tools/json-20250517.jar bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/shell/run-snapshot-checks.sh
KOTLINC=/workspace/ui-shell-tools/kotlin-2.2.20/kotlinc/bin/kotlinc JSON_JAR=/workspace/ui-shell-tools/json-20250517.jar bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/chat/projection/run-offline.sh
```

org.json artifact comes from official Maven Central, version20250517, SHA256
`3ea61b2a06e31edf1c91134fe9106b0ebb16628be169f3db75bc7a2b06b45796`;
download/check performed in writable tool directory, not added to app dependencies.
No credential/security/network settings changed.

## Remaining boundaries

Real Android Service build/device/IME/back/rotation/accessibility/screenshots and
whole-product acceptance remain open. Typed card/source/task identity/revision/
digest contracts, durable configuration create/save/host receipts and public common
Office/PDF capabilities still lack required host facts; they remain unavailable.
This completes the bounded real read-only snapshot source wiring, not all UI work.
Historical2 unknown requests / ¥0.002620 reservation untouched; no new real request,
no automatic original lookup, no main/develop change/merge, force push, deletion,
deployment, paid CI, credentials or permission changes. Leader B alone merges develop.

Final independent result: review_shell reran the exact pure consumer runner against
final source, exit0, with output:

```text
PASS shell read-only snapshot: exact scope/request, child identity, null/unsigned costs, unavailable binding, status coherence; no client/network code
```

Final static disposition: no new blocker. Removing a display-label equality gate
only enables an explicit local read attempt; producer still rejects wrong session,
conversation, project and generation before local lookup. No card action/write/
external request or automatic query opened. Negative/blank identities and stale
original-view guard checked. Runtime/Service remain unchanged from fixed98e5.
No Android/Compose/device pass inferred from this result.
