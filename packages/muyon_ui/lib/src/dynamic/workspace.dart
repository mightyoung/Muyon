import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:muyon_module_api/ui_contract.dart';

import 'surface.dart';

enum UiOperationRecovery { succeeded, failed, unknown }

/// Coordinates one task-scoped projection. Port calls wait for durable state;
/// restoration only reads receipts, and can never invoke a business port.
class UiWorkspaceController extends ChangeNotifier {
  UiWorkspaceController._(
    this.store,
    this.taskId,
    this.scopeKey,
    this.schemaVersion,
  );
  final UiWorkspaceStore store;
  final String taskId, scopeKey;
  final int schemaVersion;
  late final UiSurfaceController surface;
  StoredUiWorkspace? _stored;
  int _revision = 0;
  bool _disposed = false;
  bool readOnly = false;
  String? saveError;
  String step = 'review';
  List<String> selectedRecords = [];
  String? returnAnchor;
  double scrollOffset = 0;
  Map<String, Object?>? get readableDraft => _stored?.displayValues;
  final _recovered = <String, UiOperationRecovery>{};
  Map<String, UiOperationRecovery> get recoveredOperations =>
      Map.unmodifiable(_recovered);
  Future<void> _tail = Future.value();

  static Future<UiWorkspaceController> open({
    required UiWorkspaceStore store,
    required String taskId,
    required String scopeKey,
    required ValidatedUiPlan plan,
    int schemaVersion = 1,
    UiEventSink? onEvent,
    Future<UiOperationRecovery> Function(String)? receiptLookup,
  }) async {
    final c = UiWorkspaceController._(store, taskId, scopeKey, schemaVersion);
    final old = await store.load(plan.plan.surfaceId);
    var current = plan;
    if (old != null) {
      if (old.taskId != taskId ||
          old.scopeKey != scopeKey ||
          old.surfaceId != plan.plan.surfaceId) {
        throw StateError('Workspace identity changed');
      }
      c._stored = old;
      c._revision = old.revision;
      c.step = old.step;
      c.selectedRecords = List.of(old.selectedRecords);
      c.returnAnchor = old.returnAnchor;
      c.scrollOffset = old.scrollOffset;
      final ids = plan.plan.nodes.map((n) => n.id).toSet();
      c.readOnly =
          old.schemaVersion != schemaVersion ||
          old.catalogVersion != plan.catalog.version ||
          old.intentRef != plan.intent.id ||
          old.snapshotRef.id != plan.snapshot.ref.id ||
          old.snapshotRef.revision > plan.snapshot.ref.revision ||
          !setEquals(ids, old.nodeIds.toSet()) ||
          old.userOverrides.keys.any(
            (key) => !plan.snapshot.initialUiState.containsKey(key),
          );
      if (!c.readOnly && old.presentation != null) {
        final prior = {
          for (final node in old.presentation!.nodes) node.id: node,
        };
        c.readOnly = plan.plan.nodes.any((node) {
          final before = prior[node.id];
          return before == null ||
              before.component != node.component ||
              !mapEquals(before.bindings, node.bindings);
        });
      }
      if (!c.readOnly &&
          old.snapshotRef == plan.snapshot.ref &&
          old.presentation != null) {
        final restored = old.presentation!;
        if (restored.surfaceId != old.surfaceId ||
            restored.revision != old.planRevision ||
            restored.snapshotRef != old.snapshotRef ||
            restored.catalogVersion != old.catalogVersion ||
            restored.intentRef != old.intentRef)
          c.readOnly = true;
        else if (restored.revision >= plan.plan.revision) {
          var result = validateUiPlan(
            restored,
            plan.snapshot,
            plan.intent,
            plan.catalog,
          );
          if (!result.isValid)
            c.readOnly = true;
          else {
            for (final entry in old.patchHistory.entries) {
              result = result.recordPatch(entry.key, entry.value);
            }
            current = result.validatedPlan!;
          }
        }
      }
      // Query each real host reference before allowing the restored surface.
      for (final ref in old.operationRefs) {
        try {
          c._recovered[ref] =
              await receiptLookup?.call(ref) ?? UiOperationRecovery.unknown;
        } catch (_) {
          c._recovered[ref] = UiOperationRecovery.unknown;
        }
      }
    }
    c.surface = UiSurfaceController(
      current,
      onEvent: c.readOnly || onEvent == null
          ? null
          : (event) async {
              await c.flush(); // includes the pending/locked operation before the port
              if (c.readOnly || c._disposed)
                throw StateError('Workspace not durable');
              await onEvent(event);
            },
    );
    if (old != null) {
      c.surface.session.restoreWorkspace(old);
      c.surface.lockRecoveredOperations(old.operationRefs);
      // MUTATION ONLY: replay a pending port during restore (never merge).
      if (old.operationRefs.isNotEmpty && onEvent != null) {
        final node = c.surface.current.plan.nodes.firstWhere(
          (n) => n.events.containsKey('confirm'),
        );
        await onEvent(c.surface.eventFor(node, 'confirm'));
      }
    }
    c.surface.addListener(c._changed);
    return c;
  }

  void _changed() {
    if (_disposed) return;
    if (!readOnly) {
      // flush owns failures. UI listener remains synchronous and never leaks an
      // unhandled future or pretends a failed save was durable.
      unawaited(flush().catchError((Object _) {}));
    }
    notifyListeners();
  }

  StoredUiWorkspace _capture(int revision) {
    final p = surface.current, session = surface.session;
    return StoredUiWorkspace(
      taskId: taskId,
      surfaceId: p.plan.surfaceId,
      scopeKey: scopeKey,
      revision: revision,
      schemaVersion: schemaVersion,
      catalogVersion: p.catalog.version,
      snapshotRef: p.snapshot.ref,
      intentRef: p.intent.id,
      planRevision: p.plan.revision,
      draftRevision: session.draftRevision,
      extracted: p.snapshot.initialUiState,
      userOverrides: session.userOverrides,
      viewValues: session.viewValues,
      nodeIds: p.plan.nodes.map((n) => n.id).toList(),
      step: step,
      selectedRecords: selectedRecords,
      returnAnchor: returnAnchor,
      scrollOffset: scrollOffset,
      expandedSources: session.expandedSources.toList(),
      detailNode: session.detailNode,
      cancelledNodes: session.cancelledNodes.toList(),
      operationRefs: surface.operationRefs.toList(),
      presentation: p.plan,
      patchHistory: p.appliedPatches,
    );
  }

  Future<void> flush() {
    if (readOnly)
      return saveError == null
          ? Future.value()
          : Future.error(StateError(saveError!));
    // Capture now, serialize later: rapid edits each get one coherent version.
    final projection = _capture(1);
    final result = _tail
        .then((_) async {
          if (readOnly) throw StateError(saveError ?? 'Workspace read-only');
          final next = projection.copyWith(revision: _revision + 1);
          if (!await store.save(next, expectedRevision: _revision))
            throw StateError('Workspace revision or scope changed');
          _revision = next.revision;
          _stored = next;
          saveError = null;
        })
        .catchError((Object error) {
          saveError = '$error';
          readOnly = true;
          if (!_disposed) notifyListeners();
          throw error;
        });
    _tail = result.catchError((Object _) {});
    return result;
  }

  Future<void> adoptExtracted(String key) async {
    if (readOnly) return;
    surface.adoptExtracted(key);
    await flush();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    surface.removeListener(_changed);
    surface.dispose();
    super.dispose();
  }
}
