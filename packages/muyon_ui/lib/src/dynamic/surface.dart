import 'dart:async';

import 'package:flutter/material.dart';
import 'package:muyon_module_api/ui_contract.dart';

import '../confirmation.dart';
import '../navigation_layout.dart';
import '../primitives.dart';
import 'patch.dart';
import 'catalog_library2.dart';
import 'component_adapter.dart';
import 'fallback.dart';

typedef UiEventSink = Future<void> Function(UiEvent event);
typedef UiObjectOpen = Future<void> Function(
  ObjectRef object, {
  required String nodeId,
});

enum UiDispatchOutcome {
  applied,
  stale,
  invalid,
  unsupported,
  routed,
  duplicate,
}

enum UiReceiptStatus { succeeded, failed }

/// Published by the attached host/fixture port, never read from a UIPlan.
class UiBusinessReceipt {
  const UiBusinessReceipt({
    required this.eventId,
    required this.operationKeyRef,
    required this.draftRevision,
    required this.status,
    required this.message,
    required this.isSimulated,
  });
  final String eventId, operationKeyRef, message;
  final int draftRevision;
  final UiReceiptStatus status;
  final bool isSimulated;
}

/// Correlated, frozen UI request. The host must still prepare/authorize its tool.
class UiPendingAction {
  UiPendingAction(
    this.event,
    this.plan,
    this.binding,
    Map<String, Object?> inputs,
  ) : inputs = Map.unmodifiable(inputs);
  final UiEvent event;
  final ValidatedUiPlan plan;
  final ActionBinding binding;
  final Map<String, Object?> inputs;
}

/// Authority frozen once for a rendered tree and its callbacks.
class UiRenderCapture {
  UiRenderCapture._(this._owner, this.plan)
    : surfaceId = plan.plan.surfaceId,
      revision = plan.plan.revision,
      catalog = plan.catalog;
  final UiSurfaceController _owner;
  final String surfaceId;
  final int revision;
  final UiCatalog catalog;
  final ValidatedUiPlan plan;
}

class UiSurfaceController extends ChangeNotifier {
  UiSurfaceController(
    ValidatedUiPlan plan, {
    this.onEvent,
    this.onOpenObject,
    this.recomputePort,
    this.publishTokenProbe,
    this.readOnlyProbe,
  }) : _publication = UiPublicationCoordinator(plan) {
    if ((recomputePort == null) != (publishTokenProbe == null)) {
      throw ArgumentError('Provide both recomputePort and publishTokenProbe');
    }
    session = UiSessionState(plan.snapshot, canDispatch: _allowsEvent);
    session.accept(plan);
  }
  final UiPublicationCoordinator _publication;
  final UiRecomputePort? recomputePort;
  final UiPublishTokenProbe? publishTokenProbe;
  final bool Function()? readOnlyProbe;
  bool get recomputing => _publication.recomputing;
  bool get outdated => _publication.outdated;
  List<String> get publicationErrors => _publication.publicationErrors;
  bool get isReadOnly {
    try {
      return readOnlyProbe?.call() ?? false;
    } catch (_) {
      return true;
    }
  }

  bool _allowsEvent(UiEvent event, UiActionDefinition action) =>
      _publication.allowsDispatch(
        action,
        readOnly: isReadOnly,
        pending: _pending.values.any((p) => p.event.nodeId == event.nodeId),
      );

  /// Host work is awaited before the synchronous publication/install section.
  Future<UiPublishOutcome> recompute() async {
    final port = recomputePort, probe = publishTokenProbe;
    if (_disposed) return UiPublishOutcome.disposed;
    if (port == null || probe == null || isReadOnly) {
      return UiPublishOutcome.invalid;
    }
    final request = _publication.beginRecompute();
    if (request == null) return UiPublishOutcome.disposed;
    final base = current;
    try {
      final input = UiRecomputeInput(
        previousSnapshot: base.snapshot,
        currentUiState: {
          for (final key in base.snapshot.initialUiState.keys)
            key: session.resolve(BindingRef.uiState(key)),
        },
        token: probe(),
      );
      final result = await port.rebuild(input);
      if (!_publication.isCurrentRequest(request)) {
        return _disposed
            ? UiPublishOutcome.disposed
            : UiPublishOutcome.staleToken;
      }
      if (result.token != input.token || result.errors.isNotEmpty) {
        final failed = _publication.failRecompute(request);
        if (!_disposed) notifyListeners();
        return failed;
      }
      final snapshot = result.nextSnapshot!, intent = result.nextIntent!;
      // Same-layout progression only. Old disallowed event authority is removed.
      final plan = base.plan.copyWith(
        revision: base.plan.revision + 1,
        snapshotRef: snapshot.ref,
        intentRef: intent.id,
        nodes: [
          for (final node in base.plan.nodes)
            node.copyWith(
              events: {
                for (final entry in node.events.entries)
                  if (intent.allowedActionRefs.contains(entry.value.actionRef))
                    entry.key: entry.value,
              },
            ),
        ],
      );
      return _publishPrepared(
        UiVersionBatch(
          token: result.token,
          snapshot: snapshot,
          intent: intent,
          plan: plan,
        ),
        request,
      );
    } catch (_) {
      final failed = _publication.failRecompute(request);
      if (!_disposed && failed == UiPublishOutcome.invalid) notifyListeners();
      return failed;
    }
  }

  /// Raw host candidates share the same preparation, validator and final fence.
  UiPublishOutcome publish(UiVersionBatch batch) {
    if (_disposed) return UiPublishOutcome.disposed;
    if (publishTokenProbe == null || isReadOnly) {
      return UiPublishOutcome.invalid;
    }
    final request = _publication.beginRecompute();
    if (request == null) return UiPublishOutcome.disposed;
    return _publishPrepared(batch, request);
  }

  UiPublishOutcome _publishPrepared(
    UiVersionBatch batch,
    UiRecomputeRequest request,
  ) {
    if (!_publication.isCurrentRequest(request)) {
      return _disposed
          ? UiPublishOutcome.disposed
          : UiPublishOutcome.staleToken;
    }
    try {
      final checked = validateUiPlan(
        batch.plan,
        batch.snapshot,
        batch.intent,
        current.catalog,
      );
      if (!checked.isValid) {
        final failed = _publication.failRecompute(request);
        if (!_disposed && failed == UiPublishOutcome.invalid) notifyListeners();
        return failed;
      }
      final fence = session.publicationFence;
      final prepared = session.prepareRebase(checked.validatedPlan!);
      final outcome = _publication.completeRecompute(
        request,
        batch,
        publishTokenProbe!,
        fence: fence,
      );
      if (outcome == UiPublishOutcome.published) {
        // Fence + identical raw references guarantee this local install cannot fail.
        final installed = session.commitPreparedRebase(
          prepared,
          accepted: current,
        );
        assert(
          installed,
          'Prepared session must install with the published capability',
        );
      }
      if (!_disposed) notifyListeners();
      return outcome;
    } catch (_) {
      final failed = _publication.failRecompute(request);
      if (!_disposed && failed == UiPublishOutcome.invalid) notifyListeners();
      return failed;
    }
  }

  ValidatedUiPlan get current => _publication.current;
  late final UiSessionState session;
  final UiEventSink? onEvent;
  final UiObjectOpen? onOpenObject;
  final _receipts = <String, UiBusinessReceipt>{};
  Map<String, UiBusinessReceipt> get receipts => Map.unmodifiable(_receipts);
  final _pending = <String, UiPendingAction>{};
  UiPendingAction? pendingAction(String eventId) => _pending[eventId];
  final _lockedOperations = <(String, int)>{};
  final _recoveredOperations = <String>{};
  Set<String> get operationRefs => Set.unmodifiable({
    ..._recoveredOperations,
    for (final key in _lockedOperations) key.$1,
  });

  /// A projection is never enough authority to retry. The host decides future
  /// attempts from real receipts and gives them fresh operation references.
  void lockRecoveredOperations(Iterable<String> refs) =>
      _recoveredOperations.addAll(refs);
  void adoptExtracted(String field) {
    if (_disposed) return;
    final before = session.draftRevision;
    session.adoptExtracted(field);
    if (session.draftRevision != before && recomputePort != null) {
      unawaited(recompute());
    }
    notifyListeners();
  }

  final _seenEvents = <String>{};
  int _eventCounter = 0;
  bool _disposed = false;
  String? portError;

  UiEvent eventFor(UiNode node, String kind, [Object? payload]) => UiEvent(
    eventId:
        '${current.plan.surfaceId}:${current.plan.revision}:${++_eventCounter}',
    surfaceId: current.plan.surfaceId,
    nodeId: node.id,
    observedRevision: current.plan.revision,
    kind: kind,
    payload: payload,
  );

  UiRenderCapture captureRender() => UiRenderCapture._(this, current);

  UiEvent eventForCapture(
    UiRenderCapture capture,
    UiNode node,
    String kind, [
    Object? payload,
  ]) => UiEvent(
    eventId: '${capture.surfaceId}:${capture.revision}:${++_eventCounter}',
    surfaceId: capture.surfaceId,
    nodeId: node.id,
    observedRevision: capture.revision,
    kind: kind,
    payload: payload,
  );

  Future<UiDispatchOutcome> dispatchCaptured(
    UiRenderCapture capture,
    UiNode node,
    String kind, [
    Object? payload,
  ]) async {
    // This entire identity check executes before the first await or dispatch.
    if (_disposed ||
        !identical(capture._owner, this) ||
        !identical(capture.plan, current) ||
        !identical(capture.catalog, current.catalog) ||
        capture.surfaceId != current.plan.surfaceId ||
        capture.revision != current.plan.revision ||
        !capture.plan.plan.nodes.any(
          (candidate) => identical(candidate, node),
        ) ||
        !node.events.containsKey(kind)) {
      return UiDispatchOutcome.stale;
    }
    return dispatch(eventForCapture(capture, node, kind, payload));
  }

  bool acceptPlan(ValidatedUiPlan next) {
    if (identical(next, current)) return !_disposed;
    if (_disposed ||
        !identical(next.snapshot, current.snapshot) ||
        !identical(next.intent, current.intent) ||
        !identical(next.catalog, current.catalog)) {
      return false;
    }
    var result = UiValidationResult.unchanged(next);
    for (final entry in current.appliedPatches.entries) {
      final supplied = next.appliedPatches[entry.key];
      if (supplied != null && supplied != entry.value) return false;
      result = result.recordPatch(entry.key, entry.value);
    }
    final merged = result.validatedPlan!;
    if (!session.canAcceptPlan(merged) || !_publication.adoptPlan(merged)) {
      return false;
    }
    session.accept(merged);
    notifyListeners();
    return true;
  }

  UiValidationResult applyPatch(UiPatch patch) {
    if (_disposed) return UiValidationResult.rejected(['surface_disposed']);
    final result = applyUiPatch(
      current,
      patch,
      current.snapshot,
      current.intent,
      current.catalog,
    );
    if (result.isValid && !identical(result.validatedPlan, current)) {
      if (!acceptPlan(result.validatedPlan!)) {
        return UiValidationResult.rejected(['surface_accept']);
      }
    }
    return result;
  }

  UiBusinessReceipt? receiptFor(UiNode node) {
    final receipt = _receipts[node.id], binding = node.events['confirm'];
    return binding?.operationKeyRef == receipt?.operationKeyRef &&
            binding?.expectedDraftRevision == receipt?.draftRevision
        ? receipt
        : null;
  }

  bool isPending(UiNode node) =>
      _pending.values.any((p) => p.event.nodeId == node.id);
  bool canConfirm(UiNode node) {
    final binding = node.events['confirm'];
    final action = current.catalog.actions[binding?.actionRef];
    return !_disposed &&
        action != null &&
        _publication.allowsDispatch(
          action,
          readOnly: isReadOnly,
          pending: isPending(node),
        ) &&
        onEvent != null &&
        binding != null &&
        binding.operationKeyRef != null &&
        binding.expectedDraftRevision != null &&
        current.catalog.actions[binding.actionRef]?.route ==
            UiActionRoute.business &&
        !session.isCancelled(node.id) &&
        !isPending(node) &&
        binding.expectedDraftRevision == session.draftRevision &&
        !_lockedOperations.contains((
          binding.operationKeyRef!,
          binding.expectedDraftRevision!,
        )) &&
        !_recoveredOperations.contains(binding.operationKeyRef);
  }

  Future<UiDispatchOutcome> dispatch(UiEvent event) async {
    if (_disposed) return UiDispatchOutcome.stale;
    if (_seenEvents.contains(event.eventId)) return UiDispatchOutcome.duplicate;
    final matching = current.plan.nodes.where((n) => n.id == event.nodeId);
    if (matching.length != 1) return UiDispatchOutcome.invalid;
    final node = matching.single;
    if (event.kind == 'cancel' && isPending(node)) {
      return UiDispatchOutcome.stale;
    }
    final dispatchPlan = current;
    final action = current.catalog.actions[node.events[event.kind]?.actionRef];
    final guardedBinding = node.events[event.kind];
    final payloadType =
        current.catalog.components[node.component]?.events[event.kind];
    if (action?.route == UiActionRoute.business &&
        guardedBinding != null &&
        event.surfaceId == current.plan.surfaceId &&
        event.observedRevision == current.plan.revision &&
        (payloadType == null
            ? event.payload == null
            : matchesUiValue(payloadType, event.payload)) &&
        (_lockedOperations.contains((
              guardedBinding.operationKeyRef,
              guardedBinding.expectedDraftRevision,
            )) ||
            _recoveredOperations.contains(guardedBinding.operationKeyRef))) {
      return UiDispatchOutcome.duplicate;
    }
    if (action != null && !_allowsEvent(event, action)) {
      return UiDispatchOutcome.stale;
    }
    final rowObject = action?.localAction == UiLocalAction.openRow
        ? session.rowObject(node, event.payload)
        : null;
    final outcome = session.dispatch(event, current, current.catalog);
    if (outcome == UiEventOutcome.applied) {
      _seenEvents.add(event.eventId);
      if (action?.localAction == UiLocalAction.editField &&
          node.events[event.kind]!.inputRefs.length == 1 &&
          !(current
                  .snapshot
                  .editSpecs[node.events[event.kind]!.inputRefs.single]
                  ?.view ??
              false) &&
          recomputePort != null) {
        unawaited(recompute());
      }
      notifyListeners();
      if (rowObject != null && onOpenObject != null) {
        // A synchronous listener may have advanced the plan during notification.
        if (_disposed || !identical(dispatchPlan, current)) {
          return UiDispatchOutcome.stale;
        }
        try {
          await onOpenObject!(rowObject, nodeId: node.id);
        } catch (_) {
          if (!_disposed) {
            portError = 'Local object navigation failed.';
            notifyListeners();
          }
        }
      }
      return UiDispatchOutcome.applied;
    }
    if (outcome != UiEventOutcome.unsupported) {
      return UiDispatchOutcome.values.byName(outcome.name);
    }
    final binding = node.events[event.kind]!;
    final route = current.catalog.actions[binding.actionRef]!.route;
    if (onEvent == null) return UiDispatchOutcome.unsupported;
    if (route == UiActionRoute.business) {
      if (session.isCancelled(node.id)) return UiDispatchOutcome.stale;
      final key = (binding.operationKeyRef!, binding.expectedDraftRevision!);
      if (_lockedOperations.contains(key) ||
          _recoveredOperations.contains(key.$1)) {
        return UiDispatchOutcome.duplicate;
      }
      final inputs = <String, Object?>{};
      final context = current.snapshot.actionContext!;
      for (final ref in binding.inputRefs) {
        if (context.draft.containsKey(ref)) {
          final value = session.resolve(BindingRef.uiState(ref));
          if (value != context.draft[ref]) return UiDispatchOutcome.stale;
          inputs[ref] = value;
        } else {
          inputs[ref] = ref; // Existing host-confirmed record reference only.
        }
      }
      _lockedOperations.add(key);
      _pending[event.eventId] = UiPendingAction(
        event,
        current,
        binding,
        inputs,
      );
    }
    _seenEvents.add(event.eventId);
    portError = null;
    notifyListeners();
    try {
      await onEvent!(event);
    } catch (_) {
      if (_disposed) return UiDispatchOutcome.routed;
      portError = 'Event port unavailable. Original answer retained.';
      // Transport failure is not a host receipt. Keep the operation locked and
      // pending until the host reconciles its actual result.
      notifyListeners();
    }
    return UiDispatchOutcome.routed;
  }

  bool acceptReceipt(UiBusinessReceipt receipt) {
    if (_disposed) return false;
    final pending = _pending[receipt.eventId];
    if (pending == null ||
        pending.binding.operationKeyRef != receipt.operationKeyRef ||
        pending.binding.expectedDraftRevision != receipt.draftRevision) {
      return false;
    }
    _pending.remove(receipt.eventId);
    _receipts[pending.event.nodeId] = receipt;
    // The host operation reference stays locked even on failure: only a fresh
    // host context/recovered receipt can decide whether retrying is safe.
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _publication.dispose();
    super.dispose();
  }
}

Widget renderUiPlan(
  ValidatedUiPlan plan, {
  required UiEventSink onEvent,
  UiSurfaceController? controller,
}) => DynamicUiSurface(plan: plan, onEvent: onEvent, controller: controller);

class DynamicUiSurface extends StatefulWidget {
  const DynamicUiSurface({
    super.key,
    required this.plan,
    this.onEvent,
    this.controller,
  });
  final ValidatedUiPlan plan;
  final UiEventSink? onEvent;
  final UiSurfaceController? controller;
  @override
  State<DynamicUiSurface> createState() => _DynamicUiSurfaceState();
}

class _DynamicUiSurfaceState extends State<DynamicUiSurface> {
  late UiSurfaceController controller;
  final fields = <String, TextEditingController>{};
  @override
  void initState() {
    super.initState();
    controller =
        widget.controller ??
        UiSurfaceController(widget.plan, onEvent: widget.onEvent);
    controller.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant DynamicUiSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller) ||
        (widget.controller == null &&
            !identical(widget.plan.snapshot, oldWidget.plan.snapshot))) {
      controller.removeListener(changed);
      if (oldWidget.controller == null) controller.dispose();
      for (final c in fields.values) {
        c.dispose();
      }
      fields.clear();
      controller =
          widget.controller ??
          UiSurfaceController(widget.plan, onEvent: widget.onEvent);
      controller.addListener(changed);
    } else if (!identical(widget.plan, oldWidget.plan)) {
      controller.acceptPlan(widget.plan);
    }
  }

  @override
  void dispose() {
    controller.removeListener(changed);
    if (widget.controller == null) controller.dispose();
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Object? resolve(UiNode n, String slot) {
    final ref = n.bindings[slot];
    return ref == null ? null : controller.session.resolve(ref);
  }

  SnapshotFact fact(UiNode n) =>
      controller.current.snapshot.facts[n.bindings['value']!.id]!;
  BusinessStatus factStatus(UiNode n) => fact(n).state == FactState.conflict
      ? BusinessStatus.warning
      : BusinessStatus.neutral;
  List<Widget> children(
    UiNode n,
    Map<String, UiNode> nodes,
    UiRenderCapture capture,
  ) => [
    for (final id in n.children)
      Padding(
        key: ValueKey(id),
        padding: const EdgeInsets.only(bottom: 16),
        child: render(nodes[id]!, nodes, capture),
      ),
  ];

  Widget render(
    UiNode n,
    Map<String, UiNode> nodes,
    UiRenderCapture capture, {
    bool useAdapter = true,
  }) {
    if (useAdapter && identical(capture.catalog, library2UiCatalog)) {
      return renderLibrary2Component(
        UiAdapterContext(
          capture: capture,
          controller: controller,
          node: n,
          nodes: nodes,
          renderChild: (child) => render(child, nodes, capture),
          legacy: () => render(n, nodes, capture, useAdapter: false),
        ),
      );
    }

    final renderController = controller;
    // Each closure holds this invocation's capture, never a mutable field.
    void dispatch(UiNode node, String kind, [Object? value]) {
      controller.dispatchCaptured(capture, node, kind, value);
    }

    switch (n.component) {
      case 'PageScaffold':
        return PageScaffold(
          title: n.properties['title']! as String,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children(n, nodes, capture),
          ),
        );
      case 'MasterDetail':
        final content = children(n, nodes, capture);
        return MasterDetail(
          master: content.isEmpty ? const SizedBox.shrink() : content.first,
          detail: content.length > 1
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: content.skip(1).toList(),
                )
              : null,
        );
      case 'Field':
        final key = n.bindings['draft']!.id;
        final text =
            controller.session.resolve(n.bindings['draft']!)?.toString() ?? '';
        final input = fields.putIfAbsent(
          key,
          () => TextEditingController(text: text),
        );
        if (input.text != text) {
          input.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${n.properties['label']}: ${resolve(n, 'value')}'),
            Text(
              'Fact state: ${fact(n).state.name}${fact(n).unit == null ? '' : ' · ${fact(n).unit}'}',
            ),
            TextFormField(
              key: ValueKey('${n.id}-field'),
              controller: input,
              decoration: InputDecoration(
                labelText: n.properties['label'] as String,
              ),
              keyboardType: n.properties['inputType'] == 'text'
                  ? TextInputType.text
                  : TextInputType.number,
              readOnly: !n.events.containsKey('change'),
              onChanged: n.events.containsKey('change')
                  ? (v) async {
                      final outcome = await renderController.dispatchCaptured(
                        capture,
                        n,
                        'change',
                        v,
                      );
                      if (outcome != UiDispatchOutcome.applied &&
                          mounted &&
                          identical(controller, renderController) &&
                          identical(fields[key], input)) {
                        final accepted =
                            controller.session
                                .resolve(n.bindings['draft']!)
                                ?.toString() ??
                            '';
                        input.value = TextEditingValue(
                          text: accepted,
                          selection: TextSelection.collapsed(
                            offset: accepted.length,
                          ),
                        );
                      }
                    }
                  : null,
            ),
          ],
        );
      case 'Table':
        final rows = <(String, Object?)>[
          (n.properties['label']! as String, resolve(n, 'value')),
          if (n.bindings.containsKey('alternate'))
            (
              n.properties['alternateLabel'] as String? ?? 'Comparison',
              resolve(n, 'alternate'),
            ),
        ];
        if (resolve(n, 'sort') == 'value') {
          rows.sort(
            (a, b) => a.$2 is num && b.$2 is num
                ? (a.$2 as num).compareTo(b.$2 as num)
                : '${a.$2}'.compareTo('${b.$2}'),
          );
        }
        return Table(
          children: [
            for (final row in rows)
              TableRow(children: [Text('${row.$1}: ${row.$2}')]),
          ],
        );
      case 'SegmentedPill':
        return IgnorePointer(
          ignoring: !n.events.containsKey('change'),
          child: SegmentedPill(
            labels: const ['Original order', 'Sort by value'],
            selected: resolve(n, 'selected') == 'value' ? 1 : 0,
            onChanged: (i) =>
                dispatch(n, 'change', i == 0 ? 'original' : 'value'),
          ),
        );
      case 'SourceList':
        final expanded = controller.session.isExpanded(n.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton(
              key: ValueKey('${n.id}-expand'),
              onPressed: n.events.containsKey('tap')
                  ? () => dispatch(n, 'tap')
                  : null,
              child: Text(
                expanded ? 'Hide original source' : 'Show original source',
              ),
            ),
            if (expanded)
              SelectableText(
                resolve(n, 'source')?.toString() ??
                    'Source changed. Original span is stale.',
              ),
          ],
        );
      case 'ObjectChip':
        return Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ObjectChip(
              key: ValueKey('${n.id}-detail'),
              label: n.properties['label']! as String,
              onPressed: n.events.containsKey('tap')
                  ? () => dispatch(n, 'tap')
                  : null,
            ),
            StatusBadge(status: factStatus(n)),
            Text(fact(n).state.name),
          ],
        );
      case 'StatusBadge':
        return Wrap(
          spacing: 8,
          children: [
            StatusBadge(status: factStatus(n)),
            Text(fact(n).state.name),
          ],
        );
      case 'ScopeChip':
        return ScopeChip(
          label: n.properties['label']! as String,
          objects: [fact(n).object.objectId],
        );
      case 'WarnBanner':
        return WarnBanner(
          message:
              '${fact(n).field}: ${fact(n).value ?? "Unknown"} · ${fact(n).state.name}',
          actionLabel: n.events.containsKey('tap') && controller.onEvent != null
              ? 'Explain'
              : null,
          onAction: () => dispatch(n, 'tap'),
        );
      case 'ConfirmCard':
      case 'BatchConfirmCard':
        final binding = n.events['confirm'],
            receipt = controller.receiptFor(n),
            pending = controller.isPending(n);
        final active = controller.canConfirm(n);
        final cancelled = controller.session.isCancelled(n.id);
        final item = ConfirmItem(
          kind: ConfirmationKind.write,
          what: n.properties['label']! as String,
          who: fact(n).object.objectId,
          payload: '${controller.current.snapshot.actionContext?.draft ?? {}}',
          digest: '由宿主核对实际提交内容',
          consequence: '请求宿主确认；界面本身不授予写入权限。',
        );
        void decision(ConfirmationChoice choice) {
          if (choice == ConfirmationChoice.once && active) {
            dispatch(n, 'confirm');
          } else if (choice == ConfirmationChoice.reject &&
              !pending &&
              n.events.containsKey('cancel')) {
            dispatch(n, 'cancel');
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (n.component == 'ConfirmCard')
              ConfirmCard(
                item: item,
                allowPersistentChoices: false,
                status: receipt?.status == UiReceiptStatus.succeeded
                    ? BusinessStatus.success
                    : receipt?.status == UiReceiptStatus.failed
                    ? BusinessStatus.failed
                    : cancelled
                    ? BusinessStatus.rejected
                    : pending
                    ? BusinessStatus.running
                    : binding != null &&
                          binding.expectedDraftRevision !=
                              controller.session.draftRevision
                    ? BusinessStatus.expired
                    : BusinessStatus.pending,
                onDecision: active ? decision : null,
              )
            else
              BatchConfirmCard(
                items: [item],
                state: cancelled
                    ? BatchState.rejected
                    : receipt?.status == UiReceiptStatus.succeeded
                    ? BatchState.completed
                    : BatchState.pending,
                onAllowAll: active ? () => dispatch(n, 'confirm') : null,
                onIndividual: null,
                onReject: active && n.events.containsKey('cancel')
                    ? () => dispatch(n, 'cancel')
                    : null,
              ),
            if (pending)
              const Text('Request pending: waiting for host receipt.'),
            if (cancelled)
              const Text('Confirmation cancelled. No request sent.'),
            if (binding != null &&
                binding.expectedDraftRevision !=
                    controller.session.draftRevision)
              const Text('Draft changed. Refresh host confirmation.'),
            if (receipt != null)
              Text(
                '${receipt.isSimulated ? "Simulated receipt" : "Host receipt"} · ${receipt.status.name} · draft revision ${receipt.draftRevision}: ${receipt.message}',
              ),
          ],
        );
      default:
        return const Text('Interactive component unavailable.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!supportedUiCatalogs.contains(controller.current.catalog)) {
      return snapshotFallback(
        controller.current.snapshot,
        controller.current.intent,
      );
    }
    final capture = controller.captureRender();
    final plan = capture.plan.plan,
        nodes = {for (final n in plan.nodes) n.id: n};
    final detail = nodes[controller.session.detailNode];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller.portError != null) Text(controller.portError!),
        if (detail == null)
          render(nodes[plan.root]!, nodes, capture)
        else
          PageScaffold(
            title: '${detail.properties['label']} detail',
            actions: [
              TextButton(
                key: const ValueKey('detail-back'),
                onPressed: detail.events.containsKey('back')
                    ? () => controller.dispatchCaptured(capture, detail, 'back')
                    : null,
                child: const Text('Back to comparison'),
              ),
            ],
            child: Text('Snapshot value: ${resolve(detail, 'value')}'),
          ),
      ],
    );
  }
}
