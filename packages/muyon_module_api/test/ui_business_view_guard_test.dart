import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';

void main() {
  test('business-only events reject a view key in the draft at every validator entry', () {
    for (final view in [false, true]) {
      final snapshot = DataSnapshot(
        ref: const SnapshotRef('s', 1),
        facts: {},
        initialUiState: const {'selection': 'a'},
        editSpecs: {'selection': UiStringEdit(view: view)},
        actionContext: UiActionContext(
          draftRevision: 1,
          draft: const {'selection': 'a'},
          operations: {
            'op': HostOperationRef(draftRevision: 1, inputRefs: {'selection'}),
          },
        ),
      );
      final catalog = UiCatalog(
        version: 'library-2',
        components: {
          'Page': UiComponentSchema(allowsChildren: true),
          'Button': UiComponentSchema(
            events: {'tap': null},
            eventActions: {
              'tap': {'commit'},
            },
          ),
        },
        actions: {
          'commit': const UiActionDefinition(route: UiActionRoute.business),
        },
      );
      final intent = InteractionIntent(
        id: 'i',
        purpose: 'commit',
        snapshotRef: snapshot.ref,
        allowedActionRefs: {'commit'},
      );
      final button = UiNode(
        id: 'button',
        component: 'Button',
        events: {
          'tap': ActionBinding(
            actionRef: 'commit',
            inputRefs: ['selection'],
            operationKeyRef: 'op',
            expectedDraftRevision: 1,
          ),
        },
      );
      final plan = UIPlan(
        surfaceId: 's',
        revision: 1,
        catalogVersion: 'library-2',
        snapshotRef: snapshot.ref,
        intentRef: 'i',
        root: 'root',
        nodes: [
          UiNode(id: 'root', component: 'Page', children: ['button']),
          button,
        ],
      );
      final nodeErrors = validateUiNode(button, snapshot, intent, catalog);
      final result = validateUiPlan(plan, snapshot, intent, catalog);
      if (view) {
        expect(nodeErrors, contains('view_business_input'));
        expect(result.errors, contains('view_business_input'));
        expect(result.validatedPlan, isNull);
      } else {
        expect(nodeErrors, isEmpty);
        expect(result.isValid, isTrue, reason: result.errors.join(','));
      }
    }
  });

  test(
    'item IDs retain the frozen String.compareTo order across Unicode planes',
    () {
      const bmp = '\uE000';
      const supplementary = '\u{10000}';
      expect(supplementary.compareTo(bmp), lessThan(0));
      expect(UiItemIdsEdit.normalize([bmp, supplementary]), [
        supplementary,
        bmp,
      ]);
    },
  );
}
