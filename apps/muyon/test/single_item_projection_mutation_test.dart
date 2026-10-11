import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cases = [
    (
      name: 'item_id_uses_array_index',
      before: "final itemId = 'item-\${_digest(identity)}'; // stable_item_identity",
      after: "final itemId = 'item-\${items.length}'; // positional_identity",
    ),
    (
      name: 'items_share_operation_key',
      before: "[\n          namespace,\n          identity,\n          target.toJson(),\n          draftRevision,\n          operation.oldValues,\n          operation.newValues,\n        ]",
      after: "[namespace]",
    ),
  ];

  for (final mutant in cases) {
    test('source mutation is killed: ${mutant.name}', () async {
      final source = File('lib/assistant/single_item_projection.dart')
          .readAsStringSync();
      final fixture = File('test/single_item_projection_mutation_fixture.dart')
          .readAsStringSync();
      final count = mutant.before.allMatches(source).length;
      expect(
        count,
        1,
        reason: 'mutation must change exactly one real source anchor',
      );
      final altered = source.replaceFirst(mutant.before, mutant.after);
      expect(
        sha256.convert(utf8.encode(altered)),
        isNot(sha256.convert(utf8.encode(source))),
      );
      final parent = Directory('.dart_tool');
      parent.createSync(recursive: true);
      final directory = parent.createTempSync('projection-mutant-');
      try {
        File('${directory.path}/driver.dart').writeAsStringSync(
          fixture.replaceFirst(
            "'package:muyon/assistant/single_item_projection.dart'",
            "'registry.dart'",
          ),
        );
        Future<({int code, String output})> run(String library) async {
          File('${directory.path}/registry.dart').writeAsStringSync(library);
          // Plain Dart: no nested Flutter build, network, pub get or business IO.
          final config = File('../../.dart_tool/package_config.json')
              .absolute
              .path;
          final process = await Process.start('dart', [
            '--packages=$config',
            '${directory.path}/driver.dart',
            mutant.name,
          ]);
          addTearDown(() async {
            process.kill(ProcessSignal.sigkill);
            await process.exitCode;
          });
          final output = process.stdout.transform(utf8.decoder).join();
          final errors = process.stderr.transform(utf8.decoder).join();
          int code;
          try {
            code = await process.exitCode.timeout(const Duration(seconds: 150));
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
        expect(
          result.code,
          65,
          reason:
              'compilation/startup errors do not count as mutation kills: ${result.output}',
        );
        expect(
          result.output,
          contains('EXPECTED_ASSERTION_FAILURE:${mutant.name}'),
        );
        expect(
          File('lib/assistant/single_item_projection.dart').readAsStringSync(),
          source,
        );
        // Concise evidence; the underlying command logs stay in Actions.
        // ignore: avoid_print
        print(
          'MUTATION ${mutant.name}: baseline PASS; killed by expectation; source=${sha256.convert(utf8.encode(source))}; mutant=${sha256.convert(utf8.encode(altered))}',
        );
      } finally {
        directory.deleteSync(recursive: true);
      }
    }, timeout: const Timeout(Duration(seconds: 360)));
  }
}
