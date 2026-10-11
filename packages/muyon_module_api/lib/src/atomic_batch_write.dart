import 'module_v2.dart';
import 'write_forms.dart';

/// CR-2 D6 recommendation: the first batch limit before plugin, display and
/// content budgets are checked.
const defaultAtomicBatchMaxRows = 50;

/// One explicitly listed batch capability: an object type and an operation
/// that may be submitted as a single all-or-nothing batch.
class AtomicBatchForm {
  AtomicBatchForm({
    required this.objectType,
    required this.op,
    this.maxRows = defaultAtomicBatchMaxRows,
  }) {
    if (!isStableIdentifier(objectType)) {
      throw ArgumentError.value(
        objectType,
        'objectType',
        'expected a stable id',
      );
    }
    if (maxRows < 1) {
      throw ArgumentError.value(maxRows, 'maxRows', 'must be at least 1');
    }
  }

  final String objectType;
  final WriteFormOp op;
  final int maxRows;

  @override
  bool operator ==(Object other) =>
      other is AtomicBatchForm &&
      other.objectType == objectType &&
      other.op == op &&
      other.maxRows == maxRows;

  @override
  int get hashCode => Object.hash(objectType, op, maxRows);
}

/// Declared by `ModuleFeature.atomicBatchWrite`. Atomic batch is its own
/// capability: a module that can write one row through [WriteFormCapable] has
/// not thereby declared that many rows can commit together.
abstract interface class AtomicBatchWriteCapable {
  List<AtomicBatchForm> get atomicBatchForms;
}

/// Whether [op] on [objectType] may be submitted as an atomic batch. True only
/// when the feature is declared, the module implements both interfaces, and
/// the batch is explicitly listed and backed by a single-row form that allows
/// the same operation.
bool atomicBatchAllowed({
  required Set<ModuleFeature> features,
  required Object module,
  required String objectType,
  required WriteFormOp op,
}) {
  if (!features.contains(ModuleFeature.atomicBatchWrite)) return false;
  if (!features.contains(ModuleFeature.writeForms)) return false;
  final batchable = module is AtomicBatchWriteCapable ? module : null;
  final single = module is WriteFormCapable ? module : null;
  if (batchable == null || single == null) return false;
  final form = single.writeFormFor(objectType);
  if (form == null || !form.allows(op)) return false;
  return batchable.atomicBatchForms.any(
    (batch) => batch.objectType == objectType && batch.op == op,
  );
}
