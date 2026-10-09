import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import 'dynamic_fixtures.dart';

class MemoryStore implements UiWorkspaceStore {
  StoredUiWorkspace? value;
  @override
  Future<StoredUiWorkspace?> load(String id) async => value;
  @override
  Future<bool> save(
    StoredUiWorkspace next, {
    required int expectedRevision,
  }) async {
    if ((value?.revision ?? 0) != expectedRevision) return false;
    value = next;
    return true;
  }
}

void main() {
  test(
    'edit patch close reopen retains manual value and actual patched current',
    () async {
      final store = MemoryStore();
      final f = actionPlan();
      final c = await UiWorkspaceController.open(
        store: store,
        taskId: 'task',
        scopeKey: 'w1',
        plan: f,
      );
      final field = f.plan.nodes.firstWhere((n) => n.component == 'Field');
      await c.surface.dispatch(c.surface.eventFor(field, 'change', '13'));
      c.surface.applyPatch(
        UiPatch(
          patchId: 'p1',
          surfaceId: f.plan.surfaceId,
          baseRevision: f.plan.revision,
          nextRevision: f.plan.revision + 1,
          snapshotRevision: f.snapshot.ref,
          ops: [
            UiPatchOperation.replace(
              f.plan.nodes.first.copyWith(properties: {'title': 'Updated'}),
            ),
          ],
        ),
      );
      await c.flush();
      c.dispose();
      final restored = await UiWorkspaceController.open(
        store: store,
        taskId: 'task',
        scopeKey: 'w1',
        plan: f,
      );
      expect(restored.surface.session.resolve(field.bindings['draft']!), '13');
      expect(restored.surface.current.plan.revision, f.plan.revision + 1);
      expect(restored.surface.current.appliedPatches, contains('p1'));
      restored.dispose();
    },
  );
  test(
    'stale schema keeps readable old override and disables action ports',
    () async {
      final store = MemoryStore();
      final f = actionPlan();
      final c = await UiWorkspaceController.open(
        store: store,
        taskId: 'task',
        scopeKey: 'w1',
        plan: f,
      );
      final field = f.plan.nodes.firstWhere((n) => n.component == 'Field');
      await c.surface.dispatch(c.surface.eventFor(field, 'change', '13'));
      await c.flush();
      c.dispose();
      final restored = await UiWorkspaceController.open(
        store: store,
        taskId: 'task',
        scopeKey: 'w1',
        plan: f,
        schemaVersion: 2,
      );
      expect(restored.readOnly, isTrue);
      expect(restored.readableDraft!['quantity'], '13');
      expect(restored.surface.onEvent, isNull);
      restored.dispose();
    },
  );
  test(
    'unknown operation is saved before port and never replayed on reopen',
    () async {
      final store = MemoryStore();
      final f = actionPlan();
      var calls = 0, lookups = 0;
      final c = await UiWorkspaceController.open(
        store: store,
        taskId: 'task',
        scopeKey: 'w1',
        plan: f,
        onEvent: (e) async {
          expect(store.value!.operationRefs, isNotEmpty);
          calls++;
          throw StateError('lost reply');
        },
      );
      final node = f.plan.nodes.firstWhere(
        (n) => n.events.containsKey('confirm'),
      );
      await c.surface.dispatch(c.surface.eventFor(node, 'confirm'));
      await c.flush();
      c.dispose();
      final r = await UiWorkspaceController.open(
        store: store,
        taskId: 'task',
        scopeKey: 'w1',
        plan: f,
        onEvent: (e) async {
          calls++;
        },
        receiptLookup: (ref) async {
          lookups++;
          return UiOperationRecovery.unknown;
        },
      );
      expect(lookups, 1);
      expect(calls, 1);
      expect(r.surface.canConfirm(node), isFalse);
      expect(r.recoveredOperations.values.single, UiOperationRecovery.unknown);
      r.dispose();
    },
  );
  test('extraction refresh suggests11 but override12 survives until explicit adoption', () async {
    final store = MemoryStore();
    final f = actionPlan();
    final c = await UiWorkspaceController.open(
      store: store,
      taskId: 'task',
      scopeKey: 'w1',
      plan: f,
    );
    final field = f.plan.nodes.firstWhere((n) => n.component == 'Field');
    await c.surface.dispatch(c.surface.eventFor(field, 'change', '12'));
    await c.flush();
    c.dispose();
    final s = DataSnapshot(
      ref: const SnapshotRef('public', 2),
      facts: f.snapshot.facts,
      initialUiState: {'quantity': '11', 'sort': 'original'},
      sources: f.snapshot.sources,
      sourceDigests: f.snapshot.sourceDigests,
    );
    final i = InteractionIntent(
      id: f.intent.id,
      purpose: f.intent.purpose,
      snapshotRef: s.ref,
      requiredBindings: f.intent.requiredBindings,
      mandatoryStates: f.intent.mandatoryStates,
      allowedActionRefs: f.intent.allowedActionRefs,
    );
    final p = f.plan.copyWith(
      snapshotRef: s.ref,
      revision: 5,
      nodes: [
        for (final n in f.plan.nodes)
          n.id == 'confirm'
              ? n.copyWith(
                  events: {'cancel': ActionBinding(actionRef: 'cancel')},
                )
              : n,
      ],
    );
    final next = validateUiPlan(p, s, i, f.catalog).validatedPlan!;
    final r = await UiWorkspaceController.open(
      store: store,
      taskId: 'task',
      scopeKey: 'w1',
      plan: next,
    );
    expect(
      r.surface.session.resolve(const BindingRef.uiState('quantity')),
      '12',
    );
    expect(r.surface.session.draftRevision, greaterThan(0));
    await r.flush();
    r.dispose();
    final reopened = await UiWorkspaceController.open(
      store: store,
      taskId: 'task',
      scopeKey: 'w1',
      plan: next,
    );
    expect(
      reopened.surface.session.resolve(const BindingRef.uiState('quantity')),
      '12',
    );
    await reopened.adoptExtracted('quantity');
    expect(
      reopened.surface.session.resolve(const BindingRef.uiState('quantity')),
      '11',
    );
    reopened.dispose();
  });
  test('same node id with changed binding keeps old draft read-only', () async {
    final store = MemoryStore();
    final f = actionPlan();
    final c = await UiWorkspaceController.open(
      store: store,
      taskId: 'task',
      scopeKey: 'w1',
      plan: f,
    );
    await c.flush();
    c.dispose();
    final updated = f.plan.copyWith(
      revision: 5,
      nodes: [
        for (final n in f.plan.nodes)
          n.id == 'quantity'
              ? n.copyWith(
                  bindings: {
                    'value': const BindingRef.fact('noise'),
                    'draft': const BindingRef.uiState('quantity'),
                  },
                )
              : n,
      ],
    );
    final next = validateUiPlan(
      updated,
      f.snapshot,
      f.intent,
      f.catalog,
    ).validatedPlan!;
    final r = await UiWorkspaceController.open(
      store: store,
      taskId: 'task',
      scopeKey: 'w1',
      plan: next,
    );
    expect(r.readOnly, isTrue);
    expect(r.readableDraft!['quantity'], '12');
    r.dispose();
  });
}
