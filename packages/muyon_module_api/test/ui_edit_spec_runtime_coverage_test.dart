import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';

// Decode host metadata at runtime so const canonicalization cannot replace the
// constructor path. Assert the resulting rules, not construction alone.
void main() {
  for (final metadata in [
    '{"nullable":false,"view":true}',
    '{"nullable":true,"view":false}',
  ]) {
    test('runtime boolean metadata $metadata keeps strict payload rules', () {
      final config = jsonDecode(metadata) as Map<String, dynamic>;
      final nullable = config['nullable'] as bool;
      final spec = UiBoolEdit(
        nullable: nullable,
        view: config['view'] as bool,
      );

      expect(spec.validateSpec(), isNull);
      expect(spec.payloadType, UiValueType.boolean);
      expect(spec.view, config['view']);
      expect(spec.rejectPayload(true), isNull);
      expect(spec.rejectPayload(false), isNull);
      expect(spec.rejectPayload('true'), 'type');
      expect(spec.rejectPayload(1), 'type');
      expect(spec.rejectPayload(null), nullable ? null : 'null_not_allowed');
    });
  }

  test('runtime date bounds accept leap day and reject invalid payloads', () {
    final config = jsonDecode(
      '{"first":"2024-02-28","last":"2024-03-01","nullable":false}',
    ) as Map<String, dynamic>;
    final spec = UiDateEdit(
      first: config['first'] as String,
      last: config['last'] as String,
      nullable: config['nullable'] as bool,
    );

    expect(spec.validateSpec(), isNull);
    expect(spec.payloadType, UiValueType.string);
    expect(spec.rejectPayload('2024-02-28'), isNull);
    expect(spec.rejectPayload('2024-02-29'), isNull);
    expect(spec.rejectPayload('2024-03-01'), isNull);
    expect(spec.rejectPayload('2024-02-27'), 'range');
    expect(spec.rejectPayload('2024-03-02'), 'range');
    expect(spec.rejectPayload('2024-02-30'), 'date_format');
    expect(spec.rejectPayload('2024-2-29'), 'date_format');
    expect(spec.rejectPayload(DateTime.utc(2024, 2, 29)), 'type');
    expect(spec.rejectPayload(null), 'null_not_allowed');
  });

  test('runtime reversed date bounds are rejected without reordering', () {
    final config = jsonDecode(
      '{"first":"2024-03-01","last":"2024-02-28"}',
    ) as Map<String, dynamic>;
    final spec = UiDateEdit(
      first: config['first'] as String,
      last: config['last'] as String,
    );

    expect(spec.validateSpec(), 'range_invalid');
    expect(spec.rejectPayload('2024-02-29'), 'range');
  });
}
