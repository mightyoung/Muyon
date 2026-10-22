# Reader surface independent review

Reviewer `/root/review_shell`, 2026-10-22 UTC. Base `f04f4ef237a386b250deb903b9373229febd62ce` plus the working-tree surface/Activity/UI changes, preparing authorized contract `eb853296278cca3ec2eed7985ca64272e17e2544`. Exact input SHA256, command and directly captured output are in [reader-surface-independent.log](evidence/reader-surface-independent.log). Hashes were identical before/after execution. No production file was changed by this reviewer.

## Independent actual execution

The final `run-reader-surface-checks.sh` compiled actual DocumentReaderModels, ReaderSurfaceFence and test main with Kotlin2.2.20 `-Werror` JVM17. Runtime exit0, PASS. `git diff --check` PASS. The fixture Host/resources are synthetic and do not issue grants/open real files.

Observed assertions cover A/B/A distinct selection identity, page/frame identity, stale request rejection before Host calls, one-use dispatch samples, fresh owning-thread physical sampling, background/focus/scope/route/destroy cleanup, no auto-resume, missing-host unavailable and uncertain-cleanup hold. Final added assertions require selection acceptance before open, no repeat acceptSelection for a frame transition, and terminal stop against the original document selection event rather than a later frame request. Duplicate stale close is idempotent; background duplicate does not close the active resource; stale cleanup failure hides/stops the current output; foreign reply stops the exact accepted chain; unknown close does not retry its underlying close action.

## Static construction and ordering review

MainActivity constructs ActivityReaderSurface from the actual Activity after super.onCreate. The wrapper owns a main Handler and real LifecycleEventObserver, reads actual decor attachment/visibility/focus and Activity lifecycle/window mode, and treats unsupported/PiP/multiwindow states as ineligible. MainActivity pre-notifies pause/stop before superclass callbacks and forwards focus/mode changes, real health workspace, project preference changes, connection loss and destroy. Navigation away from documents immediately leaves the active route; Compose disposal carries its exact route token so stale disposal cannot stop a newer route. These are source observations, not Android runtime results.

A genuine exact row selection invokes synchronous acceptSelection before asynchronous open; page transitions retain that original document-selection event and separately close only the frame. Terminal changes stop the original selection event. Local visibility observations use observationId, not a claimed host reauthorization attempt. Resource/visibility state is invalidated before cleanup; close outcome uncertainty holds rather than reopening. The future private Host must still enforce serialized native selection/lifecycle/policy fences and admission freshness; local object identity and clocks do not authorize native operations.

No outstanding Important was identified in this bounded source review. The earlier four findings—double close, wrong-thread duplicate closing current resource, stale cleanup failure leaving output active, and foreign reply losing original cleanup identity—are closed in source and targeted synthetic assertions.

## Deliberate unavailable gates and limits

Production ActivityReaderSurface supplies host=null. availableSelections returns no records with an explicit catalog-unavailable explanation, not an empty-store claim. Main/shell do not manufacture ReaderDocumentRef/source/digest rows, a principal, a grant, consent, policy decision or successful authorized reader. Existing research navigation remains separate and unchanged. Thus this is genuine Activity/UI surface preparation and local pre-call fencing, not completed shared/continuous authorized reading.

The pure runner excludes ActivityReaderSurface, MainActivity, Compose, Handler and Android lifecycle execution. The parent actually attempted Android Gradle; [reader-surface-android.log](evidence/reader-surface-android.log) fails at AGP8.11.1 resolution. Reader surface/lifecycle instrumentation source remains NOT_RUN. No device/FD/PDF/window/Back/TalkBack acceptance is claimed. Actual Host/policy/FFI broker, native freshness clock/deadline and readonly reauthorization port remain missing; UI preparation does not release those gates or extend any grant TTL.
