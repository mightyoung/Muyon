import '../references.dart';
import 'snapshot.dart';

/// NOT READY (F5b slice 1b scaffold): immutable declarations only. No
/// collection-binding validator, resolver or renderer consumes these yet.
/// Typed itemIds membership may inspect these host row identities.
class UiColumn {
  const UiColumn(this.id, this.label);
  final String id, label;
}

class UiRow {
  UiRow({
    required this.itemId,
    required Map<String, BindingRef> cells,
    this.object,
  }) : cells = Map.unmodifiable(cells);
  final String itemId;
  final Map<String, BindingRef> cells;
  final ObjectRef? object;
}

class UiCollection {
  UiCollection({
    required this.id,
    required List<UiColumn> columns,
    required List<UiRow> rows,
  }) : columns = List.unmodifiable(columns),
       rows = List.unmodifiable(rows);
  final String id;
  final List<UiColumn> columns;
  final List<UiRow> rows;
}

/// NOT READY (slice 1c scaffold): metadata only; `accepts` is not implemented
/// and answers false for every collection until GREEN.
enum UiCollectionShape {
  table,
  series,
  timeline,
  options,
  items;

  bool accepts(UiCollection collection) => false;
}

class UiCollectionLimits {
  const UiCollectionLimits._();
  static const rows = 200, columns = 32;
}
