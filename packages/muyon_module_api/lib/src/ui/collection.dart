import '../references.dart';
import 'snapshot.dart';

/// NOT READY (F5b slice 1b scaffold): immutable declarations only. No
/// collection validator, resolver or renderer consumes these yet.
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

class UiCollectionLimits {
  const UiCollectionLimits._();
  static const rows = 200, columns = 32;
}
