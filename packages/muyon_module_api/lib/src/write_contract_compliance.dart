import 'atomic_batch_write.dart';
import 'business_receipts.dart';
import 'module_v2.dart';
import 'write_forms.dart';

/// Cross-checks the optional write-card interfaces against the features a
/// module declares (ADR-0004 §8, amended for writes). Returns one message per
/// violation; empty means compliant. Pure: the host decides what to do.
///
/// A declared `writeForms` without `validateDraft` is caught here: the only
/// way to have `validateDraft` is to implement [WriteFormCapable].
List<String> writeContractViolations({
  required Set<ModuleFeature> features,
  required Object module,
}) {
  final problems = <String>[
    ..._writeFormProblems(features, module),
    ..._receiptProblems(features, module),
    ..._batchProblems(features, module),
  ];
  return List.unmodifiable(problems);
}

List<String> _writeFormProblems(Set<ModuleFeature> features, Object module) {
  final declares = features.contains(ModuleFeature.writeForms);
  if (module is! WriteFormCapable) {
    return declares
        ? const [
            'writeForms declared without WriteFormCapable (validateDraft missing)',
          ]
        : const [];
  }
  final problems = <String>[];
  if (!declares) {
    problems.add('WriteFormCapable implemented without writeForms feature');
  }
  final seen = <String>{};
  for (final form in module.writeForms) {
    if (!seen.add(form.objectType)) {
      problems.add('duplicate writeForms objectType ${form.objectType}');
    }
  }
  return problems;
}

List<String> _receiptProblems(Set<ModuleFeature> features, Object module) {
  final declares = features.contains(ModuleFeature.businessReceipts);
  if (module is BusinessReceiptLookup) {
    return declares
        ? const []
        : const [
            'BusinessReceiptLookup implemented without businessReceipts feature',
          ];
  }
  return declares
      ? const ['businessReceipts declared without BusinessReceiptLookup']
      : const [];
}

List<String> _batchProblems(Set<ModuleFeature> features, Object module) {
  final declares = features.contains(ModuleFeature.atomicBatchWrite);
  final batchModule = module is AtomicBatchWriteCapable ? module : null;
  final single = module is WriteFormCapable ? module : null;
  if (batchModule == null) {
    return declares
        ? const ['atomicBatchWrite declared without AtomicBatchWriteCapable']
        : const [];
  }
  final problems = <String>[];
  if (!declares) {
    problems.add(
      'AtomicBatchWriteCapable implemented without atomicBatchWrite feature',
    );
  }
  final seen = <(String, WriteFormOp)>{};
  for (final batch in batchModule.atomicBatchForms) {
    final label = '${batch.objectType} ${batch.op.name}';
    if (!seen.add((batch.objectType, batch.op))) {
      problems.add('duplicate atomic batch $label');
    }
    // Batch is explicit, but it still needs the single-row face it batches.
    if (single == null) {
      problems.add('atomic batch $label requires WriteFormCapable');
      continue;
    }
    final form = single.writeFormFor(batch.objectType);
    if (form == null || !form.allows(batch.op)) {
      problems.add(
        'atomic batch $label has no single-row form allowing ${batch.op.name}',
      );
    }
  }
  return problems;
}
