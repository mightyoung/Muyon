import 'context.dart';

/// Stable identifier: lower snake case, as ontology field and type ids.
final _identifier = RegExp(r'^[a-z][a-z0-9_]*$');

/// Stable field path: `name`, `item_ids[2]`, `price_tiers[0].min_qty`.
final _fieldPath = RegExp(
  r'^[a-z][a-z0-9_]*(\[[0-9]+\])?(\.[a-z][a-z0-9_]*(\[[0-9]+\])?)*$',
);

bool isStableIdentifier(String value) => _identifier.hasMatch(value);

bool isStableFieldPath(String value) => _fieldPath.hasMatch(value);

void _requireIdentifier(String value, String what) {
  if (!isStableIdentifier(value)) {
    throw ArgumentError.value(value, what, 'expected a lower snake case id');
  }
}

void _requireUnique(List<String> values, String message) {
  if (values.toSet().length != values.length) throw ArgumentError(message);
}

void _requireFieldPath(String value) {
  if (!isStableFieldPath(value)) {
    throw ArgumentError.value(value, 'fieldPath', 'expected a stable path');
  }
}

/// Write-card operation. Matches the tool suffixes of the generic write tools.
enum WriteFormOp { create, update, delete, restore }

/// Writable face of one field. Declared by the module; the ontology says what
/// a field is, not whether a card may write it.
class WriteFieldPolicy {
  WriteFieldPolicy({
    required this.field,
    this.create = true,
    this.update = true,
    this.requiredOnCreate = false,
    this.clearable = true,
  }) {
    _requireIdentifier(field, 'field');
    if (!create && !update) {
      throw ArgumentError.value(field, 'field', 'needs create or update');
    }
    if (requiredOnCreate && !create) {
      throw ArgumentError.value(
        field,
        'field',
        'required on create, not creatable',
      );
    }
  }

  final String field;
  final bool create, update, requiredOnCreate, clearable;

  @override
  bool operator ==(Object other) =>
      other is WriteFieldPolicy &&
      other.field == field &&
      other.create == create &&
      other.update == update &&
      other.requiredOnCreate == requiredOnCreate &&
      other.clearable == clearable;

  @override
  int get hashCode =>
      Object.hash(field, create, update, requiredOnCreate, clearable);
}

/// Relation rules for writes that touch a `RelationSpec` by name.
class RelationWriteConstraint {
  RelationWriteConstraint({
    required this.relation,
    this.allowUpdate = true,
    this.requireTargetInScope = true,
    this.submitFullListForRefList = true,
  }) {
    _requireIdentifier(relation, 'relation');
  }

  final String relation;
  final bool allowUpdate, requireTargetInScope, submitFullListForRefList;
}

/// The writable declaration for one object type, across operations.
class ObjectWriteForm {
  ObjectWriteForm({
    required this.objectType,
    required List<WriteFieldPolicy> fields,
    this.creates = true,
    this.updates = true,
    this.deletes = true,
    this.restores = true,
    this.humanOnlyReason,
    List<RelationWriteConstraint> relations = const [],
  }) : fields = List.unmodifiable(fields),
       relations = List.unmodifiable(relations) {
    _requireIdentifier(objectType, 'objectType');
    _requireUnique([
      for (final f in this.fields) f.field,
    ], 'duplicate field in $objectType');
    _requireUnique([
      for (final r in this.relations) r.relation,
    ], 'duplicate relation in $objectType');
    if (humanOnlyReason != null) {
      if (humanOnlyReason!.trim().isEmpty) {
        throw ArgumentError.value(humanOnlyReason, 'humanOnlyReason', 'empty');
      }
      if (creates || updates || deletes || restores) {
        throw ArgumentError(
          'human-only $objectType must disable every operation',
        );
      }
    }
  }

  final String objectType;
  final List<WriteFieldPolicy> fields;
  final bool creates, updates, deletes, restores;

  /// Non-null: this type never produces an assistant-submittable card.
  final String? humanOnlyReason;
  final List<RelationWriteConstraint> relations;

  bool allows(WriteFormOp op) {
    if (humanOnlyReason != null) return false;
    return switch (op) {
      WriteFormOp.create => creates,
      WriteFormOp.update => updates,
      WriteFormOp.delete => deletes,
      WriteFormOp.restore => restores,
    };
  }

  WriteFieldPolicy? fieldPolicy(String field) {
    for (final policy in fields) {
      if (policy.field == field) return policy;
    }
    return null;
  }
}

/// Module-side write card contract (ADR-0004 §4.5 amendment, W1). Read-only:
/// `validateDraft` never writes and never issues an approval.
abstract interface class WriteFormCapable {
  /// Writable faces of this module's object types. Unknown types are not
  /// writable.
  List<ObjectWriteForm> get writeForms;

  /// Full pre-confirmation check of a draft (GB-5 gap 2).
  Future<WriteValidationResult> validateDraft(WriteDraft draft);
}

/// Lookup on the interface. An extension, not a member: `implements` does not
/// inherit default bodies, so every module would otherwise have to repeat it.
extension WriteFormLookup on WriteFormCapable {
  ObjectWriteForm? writeFormFor(String objectType) {
    for (final form in writeForms) {
      if (form.objectType == objectType) return form;
    }
    return null;
  }
}

/// Host-built write draft. `values` holds only changed fields for updates.
class WriteDraft {
  WriteDraft({
    required this.objectType,
    required this.op,
    this.id,
    this.expectedVersion,
    this.expectedContentDigest,
    Map<String, Object?> baseline = const {},
    Map<String, Object?> values = const {},
    this.draftRevision,
    required this.scopeProof,
  }) : baseline = freezeJsonMap(baseline),
       values = freezeJsonMap(values) {
    _requireIdentifier(objectType, 'objectType');
    for (final key in [...this.baseline.keys, ...this.values.keys]) {
      _requireIdentifier(key, 'field');
    }
    if (op == WriteFormOp.create) {
      if (id != null ||
          expectedVersion != null ||
          expectedContentDigest != null) {
        throw ArgumentError('a create draft carries no existing identity');
      }
    } else if (id == null || id!.isEmpty) {
      throw ArgumentError('${op.name} draft needs an id');
    }
    if (draftRevision != null && draftRevision! < 0) {
      throw ArgumentError.value(draftRevision, 'draftRevision', 'negative');
    }
  }

  final String objectType;
  final WriteFormOp op;
  final String? id;
  final int? expectedVersion;
  final String? expectedContentDigest;
  final Map<String, Object?> baseline, values;
  final int? draftRevision;

  /// Opaque host-pinned scope proof; the module compares it, never reads it.
  final Object scopeProof;
}

/// One field-level problem. `code` is for branching; `message` is for people.
class FieldIssue {
  FieldIssue({
    required this.code,
    required this.fieldPath,
    required this.message,
  }) {
    _requireIdentifier(code, 'code');
    _requireFieldPath(fieldPath);
  }

  final String code, fieldPath, message;

  @override
  bool operator ==(Object other) =>
      other is FieldIssue &&
      other.code == code &&
      other.fieldPath == fieldPath &&
      other.message == message;

  @override
  int get hashCode => Object.hash(code, fieldPath, message);
}

/// A problem with the draft as a whole, not one field.
class FormIssue {
  FormIssue({required this.code, required this.message}) {
    _requireIdentifier(code, 'code');
  }

  final String code, message;

  @override
  bool operator ==(Object other) =>
      other is FormIssue && other.code == code && other.message == message;

  @override
  int get hashCode => Object.hash(code, message);
}

class WriteValidationResult {
  WriteValidationResult.ok({
    required Map<String, Object?> normalized,
    this.draftRevision,
    this.dependencyProof,
  }) : normalized = freezeJsonMap(normalized),
       issues = const [],
       formIssues = const [],
       formBlocked = false;

  WriteValidationResult.invalid({
    required List<FieldIssue> issues,
    List<FormIssue> formIssues = const [],
    this.formBlocked = true,
    Map<String, Object?>? normalized,
    this.draftRevision,
  }) : issues = List.unmodifiable(issues),
       formIssues = List.unmodifiable(formIssues),
       normalized = normalized == null ? null : freezeJsonMap(normalized),
       dependencyProof = null {
    if (issues.isEmpty && formIssues.isEmpty) {
      throw ArgumentError('an invalid result must say what is wrong');
    }
  }

  /// Present on success, and optionally on failure for display.
  final Map<String, Object?>? normalized;
  final List<FieldIssue> issues;
  final List<FormIssue> formIssues;
  final bool formBlocked;
  final int? draftRevision;

  /// Optional read-only proof, e.g. that a referenced record still exists.
  final Object? dependencyProof;

  bool get isValid => issues.isEmpty && formIssues.isEmpty && !formBlocked;
}
