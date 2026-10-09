import 'package:muyon_module_api/ui_contract.dart';

import '../dynamic_ui/catalog.dart';

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
