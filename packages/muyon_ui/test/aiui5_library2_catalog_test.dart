import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

UiValidationResult check(
  String component, {
  Map<String, Object?> props = const {},
  Map<String, BindingRef> bindings = const {},
  Map<String, ActionBinding> events = const {},
  UiEditSpec? spec,
  Object? initial = 'a',
  List<UiNode> children = const [],
}) {
  final snapshot = DataSnapshot(
    ref: const SnapshotRef('s', 1),
    facts: {
      'label': SnapshotFact(
        object: const ObjectRef(moduleId: 'm', objectType: 't', objectId: 'a'),
        field: 'label',
        value: 'A',
        state: FactState.verified,
      ),
      'value': SnapshotFact(
        object: const ObjectRef(moduleId: 'm', objectType: 't', objectId: 'a'),
        field: 'value',
        value: 1.5,
        state: FactState.verified,
      ),
    },
    sources: {
      'source': const SourceSpanRef(
        artifact: ArtifactRef(
          moduleId: 'm',
          artifactId: 'a',
          contentDigest: 'v1',
        ),
        originalText: 'source',
        start: 0,
        end: 6,
      ),
    },
    sourceDigests: {'a': 'v1'},
    initialUiState: spec is UiItemIdsEdit ? {} : {'k': initial},
    editSpecs: spec == null ? {} : {'k': spec},
    collections: {
      for (final id in ['options', 'items'])
        id: UiCollection(
          id: id,
          columns: const [UiColumn('label', 'Label')],
          rows: [
            UiRow(
              itemId: 'a',
              cells: const {'label': BindingRef.fact('label')},
            ),
          ],
        ),
      'series': UiCollection(
        id: 'series',
        columns: const [UiColumn('label', 'Label'), UiColumn('value', 'Value')],
        rows: [
          UiRow(
            itemId: 'a',
            cells: const {
              'label': BindingRef.fact('label'),
              'value': BindingRef.fact('value'),
            },
          ),
        ],
      ),
      'table': UiCollection(
        id: 'table',
        columns: const [UiColumn('value', 'Value')],
        rows: [
          UiRow(itemId: 'a', cells: const {'value': BindingRef.fact('value')}),
        ],
      ),
      'timeline': UiCollection(
        id: 'timeline',
        columns: const [UiColumn('time', 'Time'), UiColumn('title', 'Title')],
        rows: [
          UiRow(
            itemId: 'a',
            cells: const {
              'time': BindingRef.fact('label'),
              'title': BindingRef.fact('label'),
            },
          ),
        ],
      ),
    },
  );
  final intent = InteractionIntent(
    id: 'i',
    purpose: 'test',
    snapshotRef: snapshot.ref,
    allowedActionRefs: library2UiCatalog.actions.keys.toSet(),
  );
  return validateUiPlan(
    UIPlan(
      surfaceId: 's',
      revision: 1,
      catalogVersion: 'library-2',
      snapshotRef: snapshot.ref,
      intentRef: 'i',
      root: 'root',
      nodes: [
        UiNode(
          id: 'root',
          component: 'PageScaffold',
          properties: {'title': 'test'},
          children: ['target'],
        ),
        UiNode(
          id: 'target',
          component: component,
          properties: props,
          bindings: bindings,
          events: events,
          children: children.map((n) => n.id).toList(),
        ),
        ...children,
      ],
    ),
    snapshot,
    intent,
    library2UiCatalog,
  );
}

void main() {
  test('real library2 admits host collections and typed widget inputs', () {
    final cases = [
      check(
        'Choice',
        props: {'label': 'choice'},
        bindings: {
          'options': const BindingRef.collection('options'),
          'selected': const BindingRef.uiState('k'),
        },
        spec: UiItemIdsEdit(collectionId: 'options'),
        events: {
          'change': ActionBinding(actionRef: 'edit', inputRefs: ['k']),
        },
      ),
      check(
        'CompareTable',
        props: {'label': 'table'},
        bindings: {'rows': const BindingRef.collection('table')},
      ),
      check(
        'Chart',
        props: {'kind': 'bar'},
        bindings: {'data': const BindingRef.collection('series')},
      ),
      check(
        'Checklist',
        bindings: {'items': const BindingRef.collection('items')},
      ),
      check(
        'Timeline',
        bindings: {'events': const BindingRef.collection('timeline')},
      ),
      for (final component in ['NumberStepper', 'Slider'])
        check(
          component,
          props: {'label': 'number'},
          bindings: {'value': const BindingRef.uiState('k')},
          initial: 1.5,
          spec: const UiNumberEdit(min: 0, max: 3, step: .5),
          events: {
            'change': ActionBinding(actionRef: 'edit', inputRefs: ['k']),
          },
        ),
      check(
        'Tabs',
        bindings: {'selected': const BindingRef.uiState('k')},
        initial: 'section',
        spec: const UiStringEdit(view: true),
        events: {
          'change': ActionBinding(actionRef: 'edit', inputRefs: ['k']),
        },
        children: [
          UiNode(
            id: 'section',
            component: 'Section',
            properties: {'title': 'A'},
          ),
        ],
      ),
      check(
        'Disclosure',
        props: {'title': 'detail'},
        bindings: {'expanded': const BindingRef.uiState('k')},
        initial: true,
        spec: const UiBoolEdit(view: true),
        events: {
          'change': ActionBinding(actionRef: 'edit', inputRefs: ['k']),
        },
      ),
    ];
    for (final result in cases) {
      expect(result.isValid, isTrue, reason: result.errors.join(','));
    }
  });

  test('component spec requirements apply even without an edit event', () {
    for (final component in [
      'NumberStepper',
      'Slider',
      'DateField',
      'Toggle',
    ]) {
      final result = check(
        component,
        props: {'label': 'test'},
        bindings: {'value': const BindingRef.uiState('k')},
        spec: const UiStringEdit(),
      );
      expect(result.isValid, isFalse, reason: component);
    }
  });

  test('library2 rejects wrong collection membership, view spec, slider grid, props and children', () {
    final cases = [
      check(
        'Choice',
        props: {'label': 'choice'},
        bindings: {
          'options': const BindingRef.collection('options'),
          'selected': const BindingRef.uiState('k'),
        },
        spec: UiItemIdsEdit(collectionId: 'items'),
      ),
      check(
        'Slider',
        props: {'label': 'number'},
        bindings: {'value': const BindingRef.uiState('k')},
        initial: 0,
        spec: const UiNumberEdit(min: 0, max: 1, step: .3),
      ),
      check(
        'Tabs',
        bindings: {'selected': const BindingRef.uiState('k')},
        spec: const UiStringEdit(),
      ),
      check(
        'Tabs',
        children: [
          UiNode(id: 'text', component: 'Prose', properties: {'text': 'bad'}),
        ],
      ),
      check('Heading', props: {'text': 'title', 'level': 4}),
      check(
        'Chart',
        props: {'kind': 'scatter'},
        bindings: {'data': const BindingRef.collection('series')},
      ),
      check(
        'Choice',
        props: {'label': 'choice', 'allowCustom': true},
        bindings: {
          'options': const BindingRef.collection('options'),
          'selected': const BindingRef.uiState('k'),
        },
        spec: UiItemIdsEdit(collectionId: 'options'),
      ),
    ];
    for (final result in cases) {
      expect(result.isValid, isFalse);
    }
  });
}
