import '../references.dart';
import 'snapshot.dart';

/// Immutable host-owned collection metadata. Cells retain binding references,
/// so values and provenance continue to come from the snapshot.
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

/// Required column identities. Registry order remains presentation order.
enum UiCollectionShape {
  table,
  series,
  timeline,
  options,
  items;

  bool accepts(UiCollection collection) {
    final ids = collection.columns.map((column) => column.id).toSet();
    if (ids.length != collection.columns.length) return false;
    return switch (this) {
      table => ids.isNotEmpty,
      series => ids.length == 2 && ids.containsAll({'label', 'value'}),
      timeline =>
        ids.containsAll({'time', 'title'}) &&
            ids.every({'time', 'title', 'detail'}.contains),
      options || items => ids.length == 1 && ids.contains('label'),
    };
  }
}

class UiCollectionLimits {
  const UiCollectionLimits._();
  static const rows = 200, columns = 32;
  static const idBytes = 128, labelBytes = 256, metadataBytes = 65536;
}
