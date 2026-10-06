import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/mcp_adapter.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

class _Secrets implements SecretStore {
  @override
  Future<String?> read(String reference) async =>
      reference == 'mcp-key' ? 'secret-token' : null;
}

/// Minimal Streamable-HTTP MCP server: JSON for most replies, SSE for calls.
class _FakeMcp {
  late HttpServer server;
  final calls = <Map<String, Object?>>[];
  final sessions = <String?>[];
  final auth = <String?>[];

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, Object?>;
      sessions.add(request.headers.value('mcp-session-id'));
      auth.add(request.headers.value('authorization'));
      final id = body['id'];
      final method = body['method'];
      final response = request.response;
      if (id == null) {
        response.statusCode = 202; // notification
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
                  {
                    'required': ['a'],
                  },
                ],
              },
            },
          ],
        };
      } else if (method == 'tools/call') {
        final params = body['params'] as Map;
        calls.add(Map<String, Object?>.from(params));
        final q = (params['arguments'] as Map)['q'];
        final payload = jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'content': [
              {'type': 'text', 'text': 'found $q'},
            ],
            'isError': q == 'bad',
          },
        });
        response.headers.contentType = ContentType('text', 'event-stream');
        response.write('event: message\ndata: $payload\n\n');
        await response.close();
        return;
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

void main() {
  late _FakeMcp mcp;
  late ManagedConnection db;
  late ToolRegistry registry;

  setUp(() async {
    mcp = _FakeMcp();
    await mcp.start();
    db = ManagedConnection(sqlite3.openInMemory());
    installToolRegistrySchema(db.raw);
    registry = ToolRegistry(
      database: db,
      resolveScope: (scope) async =>
          ResolvedAssistantScope(requested: scope, objects: const []),
    );
  });
  tearDown(() async {
    await mcp.server.close(force: true);
    await db.close();
  });

  Future<McpConnection> connect() => McpAdapter.connect(
    registry,
    McpServerConfig(
      id: 'catalog',
      endpoint: mcp.endpoint,
      credentialRef: 'mcp-key',
    ),
    secrets: _Secrets(),
  );

  ToolCallRequest call(String q, {String? destination, String id = 'c1'}) =>
      ToolCallRequest(
        invocationId: id,
        toolId: 'mcp.catalog.search',
        scope: const AssistantScope.global(),
        parameters: {'q': q},
        destination: destination ?? mcp.endpoint.origin,
      );

  test(
    'registers supported tools as external, skips unsupported with reason',
    () async {
      final connection = await connect();
      final info = registry.inspect('mcp.catalog.search')!;
      expect(info.accessLevel, ToolAccessLevel.external);
      expect(info.providerId, 'mcp:catalog');
      expect(registry.inspect('mcp.catalog.fancy'), isNull);
      expect(connection.skipped.keys, ['fancy']);
      expect(mcp.sessions.skip(1), everyElement('sess-1'));
      expect(mcp.auth, everyElement('Bearer secret-token'));
    },
  );

  test('calls need host approval and reach the server once', () async {
    await connect();
    await expectLater(
      registry.invoke(call('x')),
      throwsA(
        isA<ToolPlatformException>().having(
          (e) => e.code,
          'code',
          'approval_required',
        ),
      ),
    );
    expect(mcp.calls, isEmpty);

    final approved = call('chips').withApproval(
      await registry.approve(await registry.prepare(call('chips'))),
    );
    final result = await registry.invoke(approved);
    expect(result.status, ToolCallStatus.succeeded);
    expect(result.summary, 'found chips');
    expect(mcp.calls.single['name'], 'search');
    expect(mcp.calls.single['arguments'], {'q': 'chips'});
  });

  test('destination must be the configured server', () async {
    await connect();
    final wrong = call('x', destination: 'https://elsewhere.example');
    final approved = wrong.withApproval(
      await registry.approve(await registry.prepare(wrong)),
    );
    final result = await registry.invoke(approved);
    expect(result.status, ToolCallStatus.failed);
    expect(result.summary, contains('destination'));
    expect(mcp.calls, isEmpty);
  });

  test('tool-reported errors are failures, not successes', () async {
    await connect();
    final approved = call(
      'bad',
    ).withApproval(await registry.approve(await registry.prepare(call('bad'))));
    final result = await registry.invoke(approved);
    expect(result.status, ToolCallStatus.failed);
    expect(result.summary, contains('found bad'));
  });

  test(
    'parameters are validated by the host before anything is sent',
    () async {
      await connect();
      final tooLong = call('x' * 51);
      await expectLater(registry.prepare(tooLong), throwsA(anything));
      expect(mcp.calls, isEmpty);
    },
  );

  test('remote endpoints must use https', () {
    expect(
      () => McpServerConfig(
        id: 'remote',
        endpoint: Uri.parse('http://example.com/mcp'),
      ),
      throwsArgumentError,
    );
  });
}
