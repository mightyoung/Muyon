import 'package:muyon_module_api/ui_contract.dart';

import 'catalog.dart';

/// Explicit opt-in catalog. Library-1 retains its historical refusal behavior.
final library2UiCatalog = UiCatalog(
  version: 'library-2',
  components: {
    ...libraryUiCatalog.components,
    'Heading': UiComponentSchema(
      properties: {'text': UiValueType.string, 'level': UiValueType.integer},
      requiredProperties: {'text'},
      allowedValues: {
        'level': {1, 2, 3},
      },
    ),
    'Tabs': UiComponentSchema(
      allowsChildren: true,
      childComponents: {'Section'},
      bindings: {
        'selected': {BindingKind.uiState},
      },
      events: {'change': UiValueType.string},
      eventActions: {
        'change': {'edit'},
      },
    ),
    'Disclosure': UiComponentSchema(
      properties: {
        'title': UiValueType.string,
        'initiallyExpanded': UiValueType.boolean,
      },
      requiredProperties: {'title'},
      allowsChildren: true,
      bindings: {
        'expanded': {BindingKind.uiState},
      },
      events: {'change': UiValueType.boolean},
      eventActions: {
        'change': {'edit'},
      },
    ),
    'CompareTable': UiComponentSchema(
      properties: {'label': UiValueType.string},
      requiredProperties: {'label'},
      bindings: {
        'rows': {BindingKind.collection},
        'sort': {BindingKind.uiState},
      },
      requiredBindings: {'rows'},
      collections: {'rows': UiCollectionShape.table},
      events: {'tap': UiValueType.string},
      eventActions: {
        'tap': {'openRow'},
      },
    ),
    'Chart': UiComponentSchema(
      properties: {
        'kind': UiValueType.string,
        'title': UiValueType.string,
        'unit': UiValueType.string,
      },
      requiredProperties: {'kind'},
      allowedValues: {
        'kind': {'bar', 'line', 'pie'},
      },
      bindings: {
        'data': {BindingKind.collection},
      },
      requiredBindings: {'data'},
      collections: {'data': UiCollectionShape.series},
    ),
    'Choice': UiComponentSchema(
      properties: {
        'label': UiValueType.string,
        'multiple': UiValueType.boolean,
      },
      requiredProperties: {'label'},
      bindings: {
        'options': {BindingKind.collection},
        'selected': {BindingKind.uiState},
      },
      requiredBindings: {'options', 'selected'},
      collections: {'options': UiCollectionShape.options},
      events: {'change': UiValueType.stringList},
      eventActions: {
        'change': {'edit'},
      },
    ),
    for (final component in ['NumberStepper', 'Slider'])
      component: UiComponentSchema(
        properties: {'label': UiValueType.string, 'unit': UiValueType.string},
        requiredProperties: {'label'},
        bindings: {
          'value': {BindingKind.uiState},
        },
        requiredBindings: {'value'},
        events: {'change': UiValueType.number},
        eventActions: {
          'change': {'edit'},
        },
      ),
    'Checklist': UiComponentSchema(
      bindings: {
        'items': {BindingKind.collection},
        'checked': {BindingKind.uiState},
      },
      requiredBindings: {'items'},
      collections: {'items': UiCollectionShape.items},
      events: {'change': UiValueType.stringList},
      eventActions: {
        'change': {'edit'},
      },
    ),
    'Timeline': UiComponentSchema(
      bindings: {
        'events': {BindingKind.collection},
      },
      requiredBindings: {'events'},
      collections: {'events': UiCollectionShape.timeline},
    ),
  },
  actions: {
    ...libraryUiCatalog.actions,
    'openRow': const UiActionDefinition(
      route: UiActionRoute.local,
      localAction: UiLocalAction.openRow,
    ),
  },
);

final supportedUiCatalogs = Set<UiCatalog>.unmodifiable({
  minimalUiCatalog,
  dynamicUiCatalog,
  library2UiCatalog,
});
