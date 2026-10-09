import 'dart:convert';
import 'dart:io';

import 'package:supplier_core/supplier_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  late Store store;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('agent-tool-arguments-');
    store = device('A');
  });
  tearDown(() {
    store.close();
    tmp.deleteSync(recursive: true);
  });
  test(
    'explicit malformed inputs are typed and legacy JSON keeps its error',
    () {
      for (final (name, arguments) in [
        ('query', '{'),
        ('query', '[]'),
        (
          'query',
          '{"type":"product","where":[{"field":"unknown","op":"eq","value":"x"}]}',
        ),
        ('search', '{"type":"product","keywords":[]}'),
        (
          'query',
          '{"type":"product","where":[{"field":"name","op":"invented"}]}',
        ),
        ('query', '{"type":"product","where":[{"field":"name"}]}'),
        ('quote_options', '{"project_id":"p","product_id":"q","qty":"bad"}'),
      ]) {
        final result = store.runToolResult(name, arguments);
        expect(
          result.status,
          AgentToolStatus.invalidArguments,
          reason: arguments,
        );
        expect(jsonDecode(store.runTool(name, arguments)), {
          'error': result.error,
        });
      }
    },
  );
  test('snapshot data changes stay failed', () {
    final first = store.runToolResult('query', '{"type":"product"}');
    final snapshot = (first.data as Map)['snapshot'];
    store.save('product', product('changed'));
    final stale = store.runToolResult(
      'query',
      jsonEncode({'type': 'product', 'snapshot': snapshot}),
    );
    expect(stale.status, AgentToolStatus.failed);
    expect(stale.error, contains('snapshot'));
  });
  test('storage query exceptions stay failed', () {
    store.db.execute('DROP TABLE product');
    final result = store.runToolResult('query', '{"type":"product"}');
    expect(result.status, AgentToolStatus.failed);
    expect(result.error, contains('SqliteException'));
  });
  test('unknown tool and nonexistent business record stay failed', () {
    expect(
      store.runToolResult('not_registered', '{}').status,
      AgentToolStatus.failed,
    );
    expect(
      store.runToolResult('match_item', '{"item_id":"missing"}').status,
      AgentToolStatus.failed,
    );
  });
  test(
    'successful raw data is unchanged through the compatibility interface',
    () {
      final id = store.save('product', product('pump'));
      final arguments = jsonEncode({'type': 'product', 'id': id});
      final result = store.runToolResult('get', arguments);
      expect(result.status, AgentToolStatus.succeeded);
      expect(jsonDecode(store.runTool('get', arguments)), result.data);
    },
  );
}
