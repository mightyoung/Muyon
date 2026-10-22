# Explicit click readonly intent — shell increment

Baseline: c0c2dc994df099c36c83813adf8410dac999d943. Product rule received
2026-10-22: an explicit user selection of a registered, clear-source local document
in the current project may authorize this session's readonly view without another
dialog. This does not authorize edits, export, background reads or restoration of
explicitly revoked permission. Transcript content is not embedded into runtime/tool
payloads.

## Implemented in owned shell files

The existing actual Activity -> exact Compose row onClick -> fence.select path now
passes a ReaderReadOnlySelectionIntent to the private Host port. It holds the exact
original request object (surface/generation/selection sequence/lifecycle epoch/frame0
and exact document/version/source/digest), has a unique intent ID, and consumeFor
succeeds once only for that same object. Repeated clicks are new intentions, not
replays. Frame advancement, lifecycle callbacks and stale dispatches do not generate
intent. No additional confirmation UI was added. This object records local intent;
it is not native authorization, proof of source, an account ACL or a principal.

ReaderChainCleanup replaces arbitrary strings at both exact cleanup ports. All
members terminate only the current reading chain/frame and its child grants. None
means document permission revoke. Background/route/scope/selection/cleanup failure
still stop and close exact resources; foreground alone never resumes or grants.
After confirmed lifecycle cleanup, another genuine click can request a new readonly
chain, subject to authoritative policy. Unknown cleanup still holds the surface.

## Exact Host integration request — not implemented here

The pending private adapter must implement:

- acceptSelection(request, observation, intent, invalidated): synchronously consumeFor(request)
  exactly once before asynchronous lookup, bind to the live Activity/owner/Service
  epoch and native single-use selection token. Reject stale selection before native
  destructive open. Do not serialize an allow=true field from this local object.
- Deliver policy/source invalidation on the dedicated invalidated callback, including
  after Opened (an open reply callback is not an invalidation stream). The shell
  posts this to the owner thread, checks the captured original selection object,
  stops/closes the exact current chain and clears displayed output. Old A callbacks
  cannot invalidate B or a freshly selected A. This cleanup does not undo the
  separate authoritative revoked-permission state.
- Independently resolve the authoritative current-project registered local record,
  exact version/source/digest, clear provenance and live principal. The metadata
  class being constructible or a URI/file existing is not evidence. Model/card JSON
  cannot supply registration, visibility, current identity or user consent.
- Apply the approved click policy only to this readonly intent. Check explicit
  permission revocation on every new chain/reauthorization; a new intent/grant ID
  never clears revocation. Do not turn stopReadingExact/closeFrameExact's
  ReaderChainCleanup into document ACL revocation. Stop child-grant renewal and
  close exact resources while retaining the independent authoritative policy state.
- Preserve original owner/version/epoch/selection and native per-attempt fencing,
  live observation, policy deadlines, invalidation and controlled FD/lease ownership
  from READER-REAUTHORIZATION-CONTRACT.md and BINDING-HOST-HANDOFF.md. Local intent
  consumption does not replace those checks or enable annotations/edit/export.

Runtime, Service, generated bindings and reader component files were not edited.
ActivityReaderSurface still uses host=null and an unavailable canonical catalog.
Thus no production file is opened, no native grant is issued, no permission dialog
is bypassed for an unverified source, and no verified flag/button is enabled.
Actual canonical listing, policy/principal/registered-source validation and private
controlled-FD adapter remain pending their owners. Full reading/UI is incomplete.

## Verification and limits

Commands from repository root:

```bash
KOTLINC=/workspace/ui-shell-tools/kotlin-2.2.20/kotlinc/bin/kotlinc \
 bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/shell/run-reader-surface-checks.sh
KOTLINC=/workspace/ui-shell-tools/kotlin-2.2.20/kotlinc/bin/kotlinc \
 JSON_JAR=/workspace/ui-shell-tools/json-20250517.jar \
 bash apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/ui/shell/run-host-shell-checks.sh
```

Reader checks PASS exit0 (reader-consent-green.log). Host/configuration/candidate/
cold-history regressions all3 runners PASS exit0 (reader-consent-host-regression.log). Initial test-first API RED
(reader-consent-api-red.log) is compile failure for missing types/signatures, not a
behavioral reproduction of permission revocation. Extended GREEN includes wrong
request/repeated consumption, A/B/A identities, no lifecycle/frame minted intent,
foreground explicit reselect after confirmed cleanup, and a synthetic Host policy
fixture rejecting two fresh intents for an explicitly revoked document. The fixture
proves shell does not display a denied reply; it does not test production/native
policy, which remains absent. Post-review API RED is retained as reader-consent-invalidation-api-red.log; it too
is a missing-signature compile RED. New GREEN tests invalidate an already displayed
resource and reject old invalidation callbacks against B and renewed A.
Prior stale resources/fresh samples/unknown holds
and thread/route/scope tests also pass. Independent review recorded separately in
READER-CONSENT-REVIEW.md and reader-consent-independent.log.

Android command from apps/muyon_android:

```bash
GRADLE_USER_HOME=/workspace/ui-shell-tools/gradle-cache \
 MUYON_UI_GRADLE=/workspace/ui-shell-tools/gradle-8.13/bin/gradle \
 ./gradlew --offline --no-daemon --console=plain :app:compileDebugKotlin \
 :app:compileDebugAndroidTestKotlin :app:connectedDebugAndroidTest
```

Actual exit1: AGP com.android.application 8.11.1 unresolved before product Kotlin
compilation (reader-consent-android.log). No Android compilation/APK/lifecycle/device/
controlled-PFD/policy/>30s reading acceptance is claimed. Prior SDK install failed
with read-only filesystem; not retried or bypassed. This failure is a toolchain
block, not an approval-review denial. No real model/search/native document request,
old unknown retry or fee/hold modification occurred. main/develop untouched by this
worker, normal feature-branch push only.
