import 'dart:convert';

import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_module_api/ui_contract.dart';

/// A display projection, never a write payload or authorization. Sensitive raw
/// values are removed before the projection reaches a widget or semantics.
final class OntologyCardField {
  const OntologyCardField({
    required this.name,
    required this.label,
    required this.value,
    this.suggestion,
    required this.kind,
    required this.required,
    required this.masked,
  });
  final String name, label, value;
  final String? suggestion;
  final FieldKind kind;
  final bool required, masked;
}

final class OntologyCardSnapshot {
  OntologyCardSnapshot._({
    required this.object,
    required this.snapshotRef,
    required this.typeLabel,
    required List<OntologyCardField> fields,
    required this.fallback,
    required this.hasRegisteredUpdateTool,
    required this.hasOriginalPage,
  }) : fields = List.unmodifiable(fields);

  final ObjectRef object;
  final SnapshotRef snapshotRef;
  final String typeLabel;
  final List<OntologyCardField> fields;
  final bool fallback, hasRegisteredUpdateTool, hasOriginalPage;

  /// Called only with a registered host declaration and a host-read snapshot.
  /// Suggestions are untrusted display hints; they cannot replace saved facts.
  factory OntologyCardSnapshot.fromHostSnapshot({
    required ModuleOntology ontology,
    required int moduleApiVersion,
    required ObjectRef object,
    required ResolvedAssistantScope scope,
    required DataSnapshot snapshot,
    required bool hasRegisteredUpdateTool,
    Map<String, Object?> suggestions = const {},
  }) {
    if (!scope.contains(object) ||
        object.revisionRef == null ||
        object.contentDigest == null ||
        object.revisionRef!.isEmpty ||
        object.contentDigest!.isEmpty) {
      throw StateError('Card requires a current pinned object in host scope');
    }
    final type = ontology.type(object.objectType);
    final fallback = moduleApiVersion != 2 || type == null;
    if ((type?.fields.length ?? 0) > UiStreamLimits.v1.nodes ||
        suggestions.length > UiStreamLimits.v1.nodes) {
      throw StateError('Ontology card exceeds host field budget');
    }
    final facts = <String, SnapshotFact>{};
    for (final fact in snapshot.facts.values) {
      if (fact.object != object || facts.containsKey(fact.field)) {
        throw StateError('Card snapshot contains mixed or duplicate facts');
      }
      facts[fact.field] = fact;
    }
    final card = OntologyCardSnapshot._(
      object: object,
      snapshotRef: snapshot.ref,
      typeLabel: type?.label ?? '未知对象类型',
      fallback: fallback,
      hasRegisteredUpdateTool: !fallback && hasRegisteredUpdateTool,
      hasOriginalPage: !fallback && type.page.hasPage,
      fields: [
        if (type != null)
          for (final field in type.fields)
            if (field.sensitivity != Sensitivity.credential)
              _projectField(field, facts[field.name], suggestions),
      ],
    );
    final text = [card.typeLabel,
      for (final field in card.fields) ...[
        field.label, field.value, if (field.suggestion != null) field.suggestion!,
      ],
    ];
    if (text.any((value) => !_withinFieldBudget(value)) ||
        text.fold<int>(0, (total, value) => total + utf8.encode(value).length) >
            UiStreamLimits.v1.textBytes) {
      throw StateError('Ontology card exceeds host text budget');
    }
    return card;
  }
}

bool _withinFieldBudget(String value) =>
    value.length <= uiStringEditMaxBytes &&
    utf8.encode(value).length <= uiStringEditMaxBytes;

bool _stringList(Object value) => value is List &&
    value.length <= UiStreamLimits.v1.nodes &&
    value.every((v) => v is String && _withinFieldBudget(v)) &&
    value.fold<int>(0, (total, v) => total + utf8.encode(v as String).length + 3) <=
        uiStringEditMaxBytes;

OntologyCardField _projectField(
  OntologyFieldSpec field,
  SnapshotFact? fact,
  Map<String, Object?> suggestions,
) {
  final masked = field.sensitivity != Sensitivity.none;
  final current = masked
      ? '已遮盖'
      : fact == null
      ? '未提供'
      : fact.state != FactState.verified
      ? '未核验，请在原页面查看'
      : _displayValue(field, fact.value);
  return OntologyCardField(
    name: field.name,
    label: field.label,
    value: current,
    suggestion: suggestions.containsKey(field.name)
        ? masked
              ? '已遮盖'
              : _displayValue(field, suggestions[field.name])
        : null,
    kind: field.kind,
    required: field.required,
    masked: masked,
  );
}

String _displayValue(OntologyFieldSpec field, Object? value) {
  if (value == null) return '未提供';
  const invalid = '无法读取，请在原页面查看';
  if (value is String && !_withinFieldBudget(value)) return invalid;
  // This is display-shape validation, not the plugin's business validator.
  // No submit path exists in this slice.
  return switch (field.kind) {
    FieldKind.text => value is String ? value : invalid,
    FieldKind.textList => _stringList(value)
        ? (value as List).join('、')
        : invalid,
    FieldKind.decimal => value is String && num.tryParse(value)?.isFinite == true
        ? value
        : invalid,
    FieldKind.integer => value is int ? '$value' : invalid,
    FieldKind.boolean => value is bool ? (value ? '是' : '否') : invalid,
    FieldKind.date || FieldKind.instant => value is String &&
            DateTime.tryParse(value) != null
        ? value
        : invalid,
    FieldKind.enumeration => value is String &&
            (field.values?.containsKey(value) ?? false)
        ? field.values![value]!
        : invalid,
    FieldKind.ref => value is String
        ? '关联对象（未活化）：$value'
        : invalid,
    FieldKind.refList => _stringList(value)
        ? '关联对象（未活化）：${(value as List).join('、')}'
        : invalid,
    FieldKind.object => '结构化值，请在原页面查看',
  };
}
