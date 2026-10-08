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
      properties: {'label': UiValueType.string},
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
