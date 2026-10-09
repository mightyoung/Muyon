import 'package:muyon_module_api/ui_contract.dart';

/// Implemented subset only; deliberately distinct from the debug gallery.
/// PageScaffold and ObjectChip reuse existing widgets. Field/Table/SourceList
/// are minimal adapters, not a claim that the proposed 25-component set exists.
final minimalUiCatalog = UiCatalog(
  version: 'minimal-1',
  components: {
    'PageScaffold': UiComponentSchema(
      properties: {'title': UiValueType.string},
      requiredProperties: {'title'},
      allowsChildren: true,
    ),
    'Field': UiComponentSchema(
      properties: {
        'label': UiValueType.string,
        'inputType': UiValueType.string,
      },
      requiredProperties: {'label'},
      bindings: {
        'value': {BindingKind.fact},
        'draft': {BindingKind.uiState},
      },
      requiredBindings: {'value', 'draft'},
      events: {'change': UiValueType.string},
      eventActions: {
        'change': {'edit'},
      },
    ),
    'Table': UiComponentSchema(
      properties: {'label': UiValueType.string},
      requiredProperties: {'label'},
      bindings: {
        'value': {BindingKind.computed},
      },
      requiredBindings: {'value'},
    ),
    'SourceList': UiComponentSchema(
      bindings: {
        'source': {BindingKind.sourceSpan},
      },
      requiredBindings: {'source'},
      events: {'tap': null},
      eventActions: {
        'tap': {'source'},
      },
    ),
    'ObjectChip': UiComponentSchema(
      properties: {'label': UiValueType.string},
      requiredProperties: {'label'},
      bindings: {
        'value': {BindingKind.fact},
      },
      requiredBindings: {'value'},
      events: {'tap': null, 'back': null},
      eventActions: {
        'tap': {'detail'},
        'back': {'back'},
      },
    ),
  },
  actions: {
    'edit': const UiActionDefinition(
      route: UiActionRoute.local,
      localAction: UiLocalAction.editField,
    ),
    'source': const UiActionDefinition(
      route: UiActionRoute.local,
      localAction: UiLocalAction.expandSource,
    ),
    'detail': const UiActionDefinition(
      route: UiActionRoute.local,
      localAction: UiLocalAction.openDetail,
    ),
    'back': const UiActionDefinition(
      route: UiActionRoute.local,
      localAction: UiLocalAction.back,
    ),
  },
);

final dynamicUiCatalog = UiCatalog(
  version: 'dynamic-1',
  components: {
    ...minimalUiCatalog.components,
    'MasterDetail': UiComponentSchema(allowsChildren: true),
    'Table': UiComponentSchema(
      properties: {
        'label': UiValueType.string,
        'alternateLabel': UiValueType.string,
      },
      requiredProperties: {'label'},
      bindings: {
        'value': {BindingKind.fact, BindingKind.computed},
        'alternate': {BindingKind.fact, BindingKind.computed},
        'sort': {BindingKind.uiState},
      },
      requiredBindings: {'value'},
    ),
    'StatusBadge': UiComponentSchema(
      bindings: {
        'value': {BindingKind.fact},
      },
      requiredBindings: {'value'},
    ),
    'ScopeChip': UiComponentSchema(
      properties: {'label': UiValueType.string},
      requiredProperties: {'label'},
      bindings: {
        'value': {BindingKind.fact},
      },
      requiredBindings: {'value'},
    ),
    'WarnBanner': UiComponentSchema(
      bindings: {
        'value': {BindingKind.fact},
      },
      requiredBindings: {'value'},
      events: {'tap': null},
      eventActions: {
        'tap': {'explain'},
      },
    ),
    'SegmentedPill': UiComponentSchema(
      bindings: {
        'selected': {BindingKind.uiState},
      },
      requiredBindings: {'selected'},
      events: {'change': UiValueType.string},
      eventActions: {
        'change': {'sort'},
      },
    ),
    for (final component in ['ConfirmCard', 'BatchConfirmCard'])
      component: UiComponentSchema(
        properties: {'label': UiValueType.string},
        requiredProperties: {'label'},
        bindings: {
          'value': {BindingKind.fact},
        },
        requiredBindings: {'value'},
        events: {'confirm': null, 'cancel': null},
        eventActions: {
          'confirm': {'confirm'},
          'cancel': {'cancel'},
        },
      ),
  },
  actions: {
    ...minimalUiCatalog.actions,
    'sort': const UiActionDefinition(
      route: UiActionRoute.local,
      localAction: UiLocalAction.sortRows,
    ),
    'confirm': const UiActionDefinition(route: UiActionRoute.business),
    'cancel': const UiActionDefinition(
      route: UiActionRoute.local,
      localAction: UiLocalAction.cancelConfirmation,
    ),
    'explain': const UiActionDefinition(route: UiActionRoute.semantic),
  },
);

/// Component library v1 (AIUI-2, design §5.2): the component schemas of every
/// library component, on top of [dynamicUiCatalog]. Registered here so the
/// planner contract and the widgets are reviewed together; the planner keeps
/// using [dynamicUiCatalog] until AIUI-1/AIUI-5 wire streaming and rendering.
///
/// Rules: every number comes from a binding (no data properties, Chart
/// included); inputs only edit UI state through `edit`; opening a source or a
/// file are local actions; a form submit is a business action, so it still
/// goes through confirmation.
final libraryUiCatalog = UiCatalog(
  version: 'library-1',
  components: {
    ...dynamicUiCatalog.components,
    // Layout.
    'Heading': UiComponentSchema(
      properties: {'text': UiValueType.string, 'level': UiValueType.integer},
      requiredProperties: {'text'},
    ),
    'Prose': UiComponentSchema(
      properties: {'text': UiValueType.string},
      requiredProperties: {'text'},
    ),
    'Section': UiComponentSchema(
      properties: {'title': UiValueType.string},
      requiredProperties: {'title'},
      allowsChildren: true,
    ),
    'Columns': UiComponentSchema(allowsChildren: true),
    'Tabs': UiComponentSchema(allowsChildren: true),
    'Disclosure': UiComponentSchema(
      properties: {
        'title': UiValueType.string,
        'initiallyExpanded': UiValueType.boolean,
      },
      requiredProperties: {'title'},
      allowsChildren: true,
    ),
    // Data.
    'KeyValue': UiComponentSchema(
      bindings: {
        'value': {BindingKind.fact, BindingKind.computed},
      },
      requiredBindings: {'value'},
    ),
    'Metric': UiComponentSchema(
      properties: {'label': UiValueType.string, 'unit': UiValueType.string},
      requiredProperties: {'label'},
      bindings: {
        'value': {BindingKind.fact, BindingKind.computed},
        'delta': {BindingKind.computed},
      },
      requiredBindings: {'value'},
    ),
    'CompareTable': UiComponentSchema(
      properties: {'label': UiValueType.string},
      requiredProperties: {'label'},
      bindings: {
        'rows': {BindingKind.computed},
        'sort': {BindingKind.uiState},
      },
      requiredBindings: {'rows'},
      events: {'tap': null},
      eventActions: {
        'tap': {'detail'},
      },
    ),
    'Chart': UiComponentSchema(
      properties: {
        'kind': UiValueType.string,
        'title': UiValueType.string,
        'unit': UiValueType.string,
      },
      requiredProperties: {'kind'},
      bindings: {
        'data': {BindingKind.fact, BindingKind.computed},
      },
      requiredBindings: {'data'},
    ),
    // Inputs.
    'Choice': UiComponentSchema(
      properties: {
        'label': UiValueType.string,
        'multiple': UiValueType.boolean,
        'allowCustom': UiValueType.boolean,
      },
      requiredProperties: {'label'},
      bindings: {
        'options': {BindingKind.fact, BindingKind.computed},
        'selected': {BindingKind.uiState},
      },
      requiredBindings: {'options', 'selected'},
      events: {'change': UiValueType.string},
      eventActions: {
        'change': {'edit'},
      },
    ),
    'Form': UiComponentSchema(
      properties: {
        'title': UiValueType.string,
        'submitLabel': UiValueType.string,
      },
      requiredProperties: {'title'},
      allowsChildren: true,
      events: {'submit': null},
      eventActions: {
        'submit': {'submit'},
      },
    ),
    for (final component in ['NumberStepper', 'Slider'])
      component: UiComponentSchema(
        properties: {
          'label': UiValueType.string,
          'unit': UiValueType.string,
          'min': UiValueType.integer,
          'max': UiValueType.integer,
          'step': UiValueType.integer,
        },
        requiredProperties: {'label'},
        bindings: {
          'value': {BindingKind.uiState},
        },
        requiredBindings: {'value'},
        events: {'change': UiValueType.string},
        eventActions: {
          'change': {'edit'},
        },
      ),
    'Toggle': UiComponentSchema(
      properties: {'label': UiValueType.string},
      requiredProperties: {'label'},
      bindings: {
        'value': {BindingKind.uiState},
      },
      requiredBindings: {'value'},
      events: {'change': UiValueType.boolean},
      eventActions: {
        'change': {'edit'},
      },
    ),
    'DateField': UiComponentSchema(
      properties: {'label': UiValueType.string},
      requiredProperties: {'label'},
      bindings: {
        'value': {BindingKind.uiState},
      },
      requiredBindings: {'value'},
      events: {'change': UiValueType.string},
      eventActions: {
        'change': {'edit'},
      },
    ),
    // Business.
    'SourceCard': UiComponentSchema(
      properties: {'title': UiValueType.string},
      requiredProperties: {'title'},
      bindings: {
        'source': {BindingKind.sourceSpan},
      },
      requiredBindings: {'source'},
      events: {'tap': null},
      eventActions: {
        'tap': {'source'},
      },
    ),
    'FileCard': UiComponentSchema(
      bindings: {
        'value': {BindingKind.fact},
      },
      requiredBindings: {'value'},
      events: {'tap': null},
      eventActions: {
        'tap': {'detail'},
      },
    ),
    'ProgressCard': UiComponentSchema(
      properties: {'title': UiValueType.string},
      requiredProperties: {'title'},
      bindings: {
        'value': {BindingKind.fact, BindingKind.computed},
      },
      requiredBindings: {'value'},
    ),
    'Checklist': UiComponentSchema(
      bindings: {
        'items': {BindingKind.fact, BindingKind.uiState},
      },
      requiredBindings: {'items'},
      events: {'change': UiValueType.string},
      eventActions: {
        'change': {'edit'},
      },
    ),
    'Timeline': UiComponentSchema(
      bindings: {
        'events': {BindingKind.fact, BindingKind.computed},
      },
      requiredBindings: {'events'},
    ),
  },
  actions: {
    ...dynamicUiCatalog.actions,
    'submit': const UiActionDefinition(route: UiActionRoute.business),
  },
);

/// The 21 components AIUI-2 adds (design §5.2), in catalog order.
const libraryComponentNames = [
  'Heading',
  'Prose',
  'Section',
  'Columns',
  'Tabs',
  'Disclosure',
  'KeyValue',
  'Metric',
  'CompareTable',
  'Chart',
  'Choice',
  'Form',
  'NumberStepper',
  'Slider',
  'Toggle',
  'DateField',
  'SourceCard',
  'FileCard',
  'ProgressCard',
  'Checklist',
  'Timeline',
];
