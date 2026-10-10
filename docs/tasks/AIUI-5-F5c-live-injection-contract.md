# F5c live injection contract

Status: proposed integration, native implementation under explicit exclusive state/surface/publication ownership. Parent is sole integrator. F3b owns apps adapter and PR18 Widget tests.

## Fixed constructor

```dart
UiSurfaceController(
  ValidatedUiPlan plan, {
  UiEventSink? onEvent,
  UiObjectOpen? onOpenObject,
  UiRecomputePort? recomputePort,
  UiPublishTokenProbe? publishTokenProbe,
  bool Function()? readOnlyProbe,
});
```

`recomputePort` and `publishTokenProbe` must both be provided or both omitted; incomplete injection throws ArgumentError. Omission retains existing explicit behavior without a default evaluator. A throwing readOnlyProbe fails closed. This task does not modify the workspace owner's injection files.

F3b pinned live port at `11c6af36d94da4df4bc893f06b74400fcd779eb8` is compatible:

```dart
late UiSurfaceController controller;
final port = UiLiveFormulaRecomputePort(
  currentPlan: () => controller.current,
  registry: registry,
  computations: {'total': definition},
  parameterStateKeys: {'qty'},
);
controller = UiSurfaceController(
  initial,
  recomputePort: port,
  publishTokenProbe: () => UiPublishToken(
    baseSnapshotRef: controller.current.snapshot.ref,
    draftRevision: controller.session.draftRevision,
    hostGeneration: hostGeneration,
    sourceGeneration: sourceGeneration,
    permissionGeneration: permissionGeneration,
    scopeKey: scopeKey,
  ),
);
```

The generation/scope variables are trusted host counters and opaque scope, not model properties; use the real host state. Tests may provide explicit fixture counters. Read current accepted snapshot/session at every probe. Do not retain the original base or rebuild the controller after edits.

## Batch channel decision

No new batch injection port and no plan field in UiRecomputeResult. Controller calls `rebuild(input)` exactly once. It derives the same-layout forward raw plan from its frozen accepted base, advances plan revision and snapshot/intent refs, keeps stable nodes/bindings and removes event capabilities absent from nextIntent.allowedActionRefs. The existing validator admits the raw batch. The adapter's independently prepared/validated batch is not passed across this port and is not claimed as controller authority. Do not call adapter.prepare again to compute a second result.

Controller public owner methods are synchronous `UiPublishOutcome publish(UiVersionBatch batch)` and asynchronous `Future<UiPublishOutcome> recompute()`. Legal non-view edit events start recomputation; explicit adoption starts it when draft revision changes. View edits do not start formula evaluation. Read-only/outdated/recomputing/pending admission uses the same coordinator in controller and direct session event dispatch. Existing pending locks/receipts remain in the same controller.

## Atomic integration

The coordinator exposes opaque owner/base/epoch-bound `beginRecompute()` requests and synchronous `completeRecompute(request, batch, probe, fence: ...)`; the async standalone convenience wrapper is retained. Surface awaits only host work. It prepares all session layers before the final comparison, then synchronously publishes and installs using the actual accepted capability. Only afterward does it notify listeners. `current` derives from the sole coordinator pointer.

`UiPublicationEpoch` advances monotonically; immutable fences capture its value. The session's actual mutation clock feeds both prepared-rebase checks and the publication fence. Final-probe view/source/manual/adopt/restore changes invalidate preparation even when the business draft token is unchanged. Legacy plan/patch adoption synchronizes coordinator/session, preserves publication floor and invalidates outstanding requests. A same external controller host rebuild preserves mounted field controllers and focus on snapshot advance.

## Evidence and open review

Original head `480b0e0bd34b28a6a1e124c87d042ac0677223af` has two completed successful CI runs: 38029997319 and 38029994065. Later heads must be checked independently.

Real RED logs outside Git: unreadable repair expected applied/actual invalid; final session mutation expected staleToken/actual published; four core bridge/fence/request tests fail with original16 passing; mounted field edit expected one host input/actual zero. Compilation failure from an earlier fixture attempt is excluded. After implementation the core/session targeted set is31 PASS and mounted protocol test1 PASS, including sequential publication and first-notification agreement.

Mounted protocol test uses a deferred host result fixture; it does not evaluate formulas or substitute for F3b's actual registry/database assertions. PR18 two Widget tests, actual 30/40 results/extracted2/database unchanged, are still F3b acceptance work. The integrator's full five-item review report is pending here; the unreadable repair is reproduced/fixed, but the four older blockers must be reconciled against their exact evidence before claiming closure. No merge to develop/main or production switch.

Complete package regression after implementation: API190 PASS; UI499 PASS. Strict analysis: no own-file/UI diagnostics; only the two previously documented external-owner infos remain. Original pending duplicate return semantics are preserved; no test expectation was weakened. Full CI at the new source head remains a separate gate.
