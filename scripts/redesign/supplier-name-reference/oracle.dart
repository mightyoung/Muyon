// Calls the unchanged product implementation, never a replacement normalizer.
import 'dart:convert';
import 'dart:io';

import '../../../packages/supplier_core/lib/src/values.dart' as product;
import '../../../packages/supplier_core/lib/src/entities.dart' as product;

Object? decodeInput(Object? raw) {
  final spec = raw as Map<String, dynamic>;
  if (spec.containsKey('literal')) return spec['literal'];
  if (spec.containsKey('repeat')) {
    final repeated = spec['repeat'] as Map<String, dynamic>;
    final count = repeated['count'] as int;
    if (count < 0 || count > 10000)
      throw FormatException('fixture repeat bound');
    return (repeated['literal'] as String) * count;
  }
  if (spec.containsKey('concat')) {
    return (spec['concat'] as List).map(decodeInput).cast<String>().join();
  }
  if (spec.containsKey('utf16_code_units')) {
    return String.fromCharCodes((spec['utf16_code_units'] as List).cast<int>());
  }
  throw FormatException('unsupported fixture input expression');
}

void main(List<String> arguments) {
  if (arguments.length != 1) throw ArgumentError('expected invocation JSON');
  final invocations =
      jsonDecode(File(arguments.single).readAsStringSync()) as List;
  final results = <Map<String, Object?>>[];
  for (final raw in invocations) {
    final item = raw as Map<String, dynamic>;
    final id = item['invocation_id'] as String;
    final entry = item['entry_point'] as String;
    final result = <String, Object?>{'invocation_id': id, 'entry_point': entry};
    try {
      final input = decodeInput(item['input']);
      result['input_utf16_units'] = input is String ? input.length : null;
      String? normalized;
      switch (entry) {
        case 'normalizeText':
          normalized = product.normalizeText(
            input,
            'name',
            200,
            required: true,
          );
        case 'Supplier.fromJson':
          final payload = item['complete_supplier_from_name'] == true
              ? <String, Object?>{
                  'name': input,
                  'aliases': <String>[],
                  'address': null,
                  'categories': <String>[],
                  'notes': null,
                  'merged_into': null,
                }
              : Map<String, Object?>.from(input as Map);
          normalized =
              product.Supplier.fromJson(payload).toJson()['name'] as String;
        default:
          throw StateError('entry point not supported');
      }
      result['outcome'] = 'accepted';
      // Classified/canary inputs never produce output plaintext.
      if (item['safe_output'] == true) result['normalized'] = normalized;
      result['normalized_codepoints'] = normalized?.runes.length;
      result['normalized_utf16_units'] = normalized?.length;
    } on FormatException catch (error) {
      result['outcome'] = 'rejected';
      result['reason'] = error.message;
    }
    results.add(result);
  }
  stdout.writeln(jsonEncode(results));
}
