import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import 'aiui5_revision2_review_test.dart' show reviewPlan;
import 'workspace_controller_test.dart' show MemoryStore;

class CountingStore extends MemoryStore {
  int saves = 0;
  @override
  Future<bool> save(StoredUiWorkspace next, {required int expectedRevision}) {
    saves++;
    return super.save(next, expectedRevision: expectedRevision);
  }
}

void main() {
  for (final direct in [false, true]) {
    test(
      'revoked ${direct ? 'surface' : 'workspace'} adoption preserves draft and storage',
      () async {
        final store = CountingStore();
        var revoked = false;
        final c = await UiWorkspaceController.open(
          store: store,
          taskId: 'task',
          scopeKey: 'scope',
          plan: reviewPlan('NumberStepper'),
          readOnlyProbe: () => revoked,
        );
        addTearDown(c.dispose);
        c.surface.session.edit('k', 9.0);
        await c.flush();
        final before = jsonEncode(store.value!.toJson());
        final revision = c.surface.session.draftRevision;
        final saves = store.saves;
        final adopt = direct
            ? () async => c.surface.adoptExtracted('k')
            : () => c.adoptExtracted('k');
        revoked = true;
        await adopt();
        expect(c.surface.session.resolve(const BindingRef.uiState('k')), 9.0);
        expect(c.surface.session.draftRevision, revision);
        expect(store.saves, saves);
        expect(jsonEncode(store.value!.toJson()), before);
      },
    );
  }
  for (final discard in [false, true]) {
    for (final revoked in [false, true]) {
      test(
        '${revoked ? 'revoked' : 'legal'} recovery discard=$discard separates host from internal read-only',
        () async {
          final store = CountingStore();
          final seed = await UiWorkspaceController.open(
            store: store,
            taskId: 'task',
            scopeKey: 'scope',
            plan: reviewPlan('NumberStepper'),
          );
          seed.surface.session.edit('k', 9.0);
          await seed.flush();
          seed.dispose();
          final raw = store.value!.toJson();
          raw['userOverrides'] = <String, Object?>{};
          raw['readableDraft'] = {'k': 9.0};
          store.value = StoredUiWorkspace.fromJson(raw);
          var hostRevoked = false;
          final c = await UiWorkspaceController.open(
            store: store,
            taskId: 'task',
            scopeKey: 'scope',
            plan: reviewPlan('NumberStepper'),
            readOnlyProbe: () => hostRevoked,
          );
          addTearDown(c.dispose);
          expect(c.readOnly, isTrue);
          final before = jsonEncode(store.value!.toJson());
          final revision = c.surface.session.draftRevision;
          final saves = store.saves;
          hostRevoked = revoked;
          if (revoked) {
            await expectLater(
              c.resolveDraft('k', discard: discard),
              throwsStateError,
            );
            expect(c.surface.session.draftRevision, revision);
            expect(c.quarantinedDraft, {'k': 9.0});
            expect(store.saves, saves);
            expect(jsonEncode(store.value!.toJson()), before);
          } else {
            await c.resolveDraft('k', discard: discard);
            expect(c.readOnly, isFalse);
            expect(c.quarantinedDraft, isEmpty);
            expect(
              c.surface.session.resolve(const BindingRef.uiState('k')),
              discard ? 2.0 : 9.0,
            );
            expect(store.saves, saves + 1);
          }
        },
      );
    }
  }
}
