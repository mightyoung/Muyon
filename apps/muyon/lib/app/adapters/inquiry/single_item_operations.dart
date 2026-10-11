/// Host-side module declaration, never part of the model action catalogue.
/// Single-row support must cover preparation, commit AND the real receipt.
class IndependentItemOperation {
  const IndependentItemOperation({
    required this.moduleId,
    required this.objectType,
    required this.operation,
    this.independentPrepare = true,
    this.independentCommit = true,
    this.independentReceipt = true,
    this.atomic = false,
  });
  final String moduleId, objectType, operation;
  final bool independentPrepare, independentCommit, independentReceipt, atomic;
}

/// The existing quantity handler checks one pinned project_item and returns
/// that row's receipt. This declaration registers no tool or UI action.
const inquiryIndependentItemOperations = [
  IndependentItemOperation(
    moduleId: 'inquiry',
    objectType: 'project_item',
    operation: 'set_item_qty',
  ),
];
