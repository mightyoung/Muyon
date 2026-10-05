import 'dart:convert';
import 'dart:io';

import 'package:supplier_core/supplier_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// E9: the ontology link paths handed to models through `describe(type)`.
void main() {
  setUp(() => tmp = Directory.systemTemp.createTempSync('supplier_paths'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('ontologyPaths', () {
    test('every pair yields valid simple deterministic paths', () {
      for (final from in ontology.keys) {
        for (final to in ontology.keys) {
          if (from == to) continue;
          final first = ontologyPaths(from, to);
          final second = ontologyPaths(from, to);
          expect(
            jsonEncode([for (final path in first) path.toJson()]),
            jsonEncode([for (final path in second) path.toJson()]),
            reason: '$from -> $to 必须可复现',
          );
          for (final path in first) {
            expect(path.hops, lessThanOrEqualTo(3), reason: '$from -> $to');
            expect(path.steps, isNotEmpty);
            final visited = [path.steps.first.from];
            expect(visited.first, from);
            for (final step in path.steps) {
              final link = links.where((l) => l.name == step.link).firstOrNull;
              expect(link, isNotNull, reason: '${step.link} 不在 links 里');
              expect(step.from, visited.last, reason: '相邻步必须首尾相接');
              expect(visited, isNot(contains(step.to)), reason: '不得重复经过对象');
              if (step.direction == PathDirection.out) {
                expect(step.from, link!.from);
                expect(step.to, link.to);
                expect(step.via, 'get');
              } else {
                expect(step.from, link!.to);
                expect(step.to, link.from);
                expect(step.via, 'related');
              }
              expect(step.many, link.many);
              visited.add(step.to);
            }
            expect(visited.last, to);
          }
        }
      }
    });

    test('supplier to project has the two hand-checked two-hop paths', () {
      final paths = ontologyPaths('supplier', 'project');
      expect(paths, hasLength(2));
      expect(paths[0].linkNames, [
        'inquiry.supplier_ids',
        'inquiry.project_id',
      ]);
      expect(paths[0].steps[0].direction, PathDirection.incoming);
      expect(paths[0].steps[0].from, 'supplier');
      expect(paths[0].steps[0].to, 'inquiry');
      expect(paths[0].steps[0].via, 'related');
      expect(paths[0].steps[0].many, isTrue);
      expect(paths[0].steps[1].direction, PathDirection.out);
      expect(paths[0].steps[1].from, 'inquiry');
      expect(paths[0].steps[1].to, 'project');
      expect(paths[0].steps[1].via, 'get');
      expect(paths[0].steps[1].many, isFalse);
      expect(paths[1].linkNames, [
        'quotation.supplier_id',
        'quotation.project_id',
      ]);
      expect(paths[1].steps[0].direction, PathDirection.incoming);
      expect(paths[1].steps[0].from, 'supplier');
      expect(paths[1].steps[0].to, 'quotation');
      expect(paths[1].steps[1].direction, PathDirection.out);
      expect(paths[1].steps[1].to, 'project');
    });

    test('same type, unknown types and bounds return as documented', () {
      expect(ontologyPaths('supplier', 'supplier'), isEmpty);
      expect(ontologyPaths('supplier', 'nope'), isEmpty);
      expect(ontologyPaths('nope', 'supplier'), isEmpty);
      expect(ontologyPaths('supplier', 'project', maxHops: 1), isEmpty);
      final limited = ontologyPaths('supplier', 'project', limit: 1);
      expect(limited, hasLength(1));
      expect(limited.single.linkNames, [
        'inquiry.supplier_ids',
        'inquiry.project_id',
      ]);
    });
  });

  group('describe paths_to', () {
    late Store store;
    setUp(() => store = device('A'));
    Object? run(String name, Map<String, Object?> args) =>
        jsonDecode(store.runTool(name, jsonEncode(args)));

    test('describe(type) adds paths_to; describe() stays unchanged', () {
      final typed =
          run('describe', {'type': 'supplier'})! as Map<String, Object?>;
      final paths = typed['paths_to']! as Map<String, Object?>;
      expect(paths, isNotEmpty);
      expect(paths.keys, isNot(contains('supplier')));
      expect(
        paths['project'],
        'related inquiry.supplier_ids → get inquiry.project_id',
      );
      expect(typed['paths_to_format'], isA<String>());

      final plain = run('describe', {})! as Map<String, Object?>;
      expect(plain.containsKey('paths_to'), isFalse);
      expect(plain.keys.toSet(), {'types', 'links', 'rules', 'actions_in_app'});
    });
  });
}
