import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cases = [
    (
      name: 'sum_decimal_exact_and_unit_checked',
      before: 'value = pricing.fromMicros(total); // exact_sum',
      after: "value = values.values.cast<String>().fold<double>(0, (sum, item) => sum + double.parse(item)).toStringAsFixed(6).replaceFirst(RegExp(r'0+\$'), '').replaceFirst(RegExp(r'\\.\$'), ''); // double_sum",
    ),
    (
      name: 'stale_input_version_not_published',
      before: 'if (invocation.inputVersion != snapshot.ref) {',
      after: 'if (false) { // stale guard bypassed',
    ),
    (
      name: 'unknown_formula_rejected',
      before: 'if (invocation.formulaId != definition.formulaId) {',
      after: 'if (false) { // formula guard bypassed',
    ),
    (
      name: 'unknown_ref_rejected',
      before: "invalid.add('unknown_ref:\$name');",
      after: "missing.add('missing_value:\$name'); // unknown ref treated as nullable",
    ),
  ];

  for (final mutant in cases) {
    test('source mutation is killed: ${mutant.name}', () async {
      final source = File('lib/platform/ui_formula_registry.dart').readAsStringSync();
      final fixture = File('test/ui_formula_registry_mutation_fixture.dart').readAsStringSync();
      final count = mutant.before.allMatches(source).length;
      expect(count, 1, reason: 'mutation must change exactly one real source anchor');
      final altered = source.replaceFirst(mutant.before, mutant.after);
      expect(sha256.convert(utf8.encode(altered)), isNot(sha256.convert(utf8.encode(source))));
      final parent = Directory('.dart_tool');
      parent.createSync(recursive: true);
      final directory = parent.createTempSync('formula-mutant-');
      try {
        File('${directory.path}/driver.dart').writeAsStringSync(fixture.replaceFirst("'package:muyon/platform/ui_formula_registry.dart'", "'registry.dart'"));
        Future<({int code, String output})> run(String library) async {
          File('${directory.path}/registry.dart').writeAsStringSync(library);
          // Plain Dart: no nested Flutter build, network, pub get or business IO.
          final config = File('../../.dart_tool/package_config.json').absolute.path;
          final process = await Process.start('dart', ['--packages=$config', '${directory.path}/driver.dart', mutant.name]);
          addTearDown(() async {
            process.kill(ProcessSignal.sigkill);
            await process.exitCode;
          });
          final output = process.stdout.transform(utf8.decoder).join();
          final errors = process.stderr.transform(utf8.decoder).join();
          int code;
          try {
            code = await process.exitCode.timeout(const Duration(seconds: 45));
          } catch (_) {
            process.kill(ProcessSignal.sigkill);
            await process.exitCode;
            rethrow;
          }
          return (code: code, output: '${await output}${await errors}');
        }
        final baseline = await run(source);
        expect(baseline.code, 0, reason: baseline.output);
        expect(baseline.output, contains('PASS:${mutant.name}'));
        final result = await run(altered);
        expect(result.code, 65, reason: 'compilation/startup errors do not count as mutation kills: ${result.output}');
        expect(result.output, contains('EXPECTED_ASSERTION_FAILURE:${mutant.name}'));
        expect(File('lib/platform/ui_formula_registry.dart').readAsStringSync(), source);
        // Concise evidence; the underlying command logs stay in Actions.
        // ignore: avoid_print
        print('MUTATION ${mutant.name}: baseline PASS; killed by expectation; source=${sha256.convert(utf8.encode(source))}; mutant=${sha256.convert(utf8.encode(altered))}');
      } finally {
        directory.deleteSync(recursive: true);
      }
    }, timeout: const Timeout(Duration(seconds: 120)));
  }
}
