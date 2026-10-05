import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/screens/mcp_servers_page.dart';
import 'package:path/path.dart' as p;

/// E2 host-level acceptance for [HostMcpServerStore]: configuration is stored
/// without the token, tokens only in the injected secret store, connection
/// happens on demand against a local fake MCP server, and removal disables the
/// tools the server registered instead of deleting registry entries.
///
/// Kept in its own file: real HTTP must not share a suite that initialises
/// `TestWidgetsFlutterBinding`, which turns every request into a 400.
void main() {
  late Directory tmp;
  late _FakeMcp mcp;
  late _MemorySecrets secrets;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('mcp-store-');
    mcp = _FakeMcp();
    await mcp.start();
    secrets = _MemorySecrets();
  });
  tearDown(() async {
    await mcp.server.close(force: true);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  McpServerRecord record({String? credentialRef}) => McpServerRecord(
    id: 'catalog',
    endpoint: mcp.endpoint,
    credentialRef: credentialRef,
  );

  test('saves config without the token and reloads it', () async {
    final host = await MuyonHost.open(p.join(tmp.path, 'data'));
    try {
      final store = HostMcpServerStore(host, secrets);
      await store.save(record(credentialRef: 'mcp-catalog'), 'secret-token');

      final json = jsonEncode(host.workspaces.setting('mcpServers'));
      expect(json.contains('secret-token'), isFalse);
      expect(secrets.values['mcp-catalog'], 'secret-token');

      final reloaded = HostMcpServerStore(host, secrets).load().single;
      expect(reloaded.id, 'catalog');
      expect(reloaded.endpoint, mcp.endpoint);
      expect(reloaded.credentialRef, 'mcp-catalog');
    } finally {
      await host.close();
    }
  });

  test('connects only when asked and removal disables its tools', () async {
    final host = await MuyonHost.open(p.join(tmp.path, 'data'));
    try {
      final store = HostMcpServerStore(host, secrets);
      await store.save(record(), '');
      expect(mcp.requests, 0);

      final connection = await store.connect(record());
      expect(connection.registered, ['mcp.catalog.search']);
      expect(connection.skipped.keys, ['fancy']);
      expect(host.tools.inspect('mcp.catalog.search')!.available, isTrue);
      expect(mcp.requests, greaterThan(0));

      await store.remove(record());
      expect(store.load(), isEmpty);
      expect(secrets.values, isEmpty);
      final info = host.tools.inspect('mcp.catalog.search')!;
      expect(info.available, isFalse);
      expect(info.unavailableReason, '服务器已移除');
    } finally {
      await host.close();
    }
  });
}

class _MemorySecrets implements McpSecrets {
  final values = <String, String>{};
  @override
  Future<String?> read(String reference) async => values[reference];
  @override
  Future<void> write(String reference, String value) async {
    values[reference] = value;
  }

  @override
  Future<void> remove(String reference) async {
    values.remove(reference);
  }
}

/// Minimal Streamable-HTTP MCP server: JSON for most replies.
class _FakeMcp {
  late HttpServer server;
  var requests = 0;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests++;
      final body = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, Object?>;
      final id = body['id'];
      final method = body['method'];
      final response = request.response;
      if (id == null) {
        response.statusCode = 202;
        await response.close();
        return;
      }
      Object? result;
      if (method == 'initialize') {
        response.headers.set('mcp-session-id', 'sess-1');
        result = {
          'protocolVersion': '2025-06-18',
          'capabilities': {'tools': {}},
          'serverInfo': {'name': 'fake', 'version': '1'},
        };
      } else if (method == 'tools/list') {
        result = {
          'tools': [
            {
              'name': 'search',
              'description': 'Search remote catalog',
              'inputSchema': {
                'type': 'object',
                'properties': {
                  'q': {'type': 'string', 'maxLength': 50},
                },
                'required': ['q'],
              },
            },
            {
              'name': 'fancy',
              'inputSchema': {
                'type': 'object',
                'oneOf': [
                  {'required': ['a']},
                ],
              },
            },
          ],
        };
      } else {
        result = const {};
      }
      response.headers.contentType = ContentType.json;
      response.write(
        jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}),
      );
      await response.close();
    });
  }

  Uri get endpoint => Uri.parse('http://127.0.0.1:${server.port}/mcp');
}
