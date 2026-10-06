import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/mcp_adapter.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/screens/mcp_servers_page.dart';
import 'package:muyon/services/models/credential_redaction.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_ui/muyon_ui.dart';
import 'package:sqlite3/sqlite3.dart';

/// P0-S2: an MCP token never reaches the page, storage or receipts.
const _marker = 'SECRET';
const _good = 'tok-$_marker-ok';

class _Secrets implements SecretStore {
  _Secrets(this.value);
  final String value;
  @override
  Future<String?> read(String reference) async => value;
}

/// Loopback MCP server. [echo] decides what to put back: in a JSON-RPC
/// error for tools/list, or in a tool result.
class _Server {
  _Server({this.errorEcho = false, this.resultEcho = false});
  final bool errorEcho, resultEcho;
  late HttpServer server;
  var requests = 0;
  var connections = 0;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests++;
      final body = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, Object?>;
      final id = body['id'];
      final response = request.response;
      if (id == null) {
        response.statusCode = 202;
        await response.close();
        return;
      }
      final auth = request.headers.value('authorization') ?? '';
      final method = body['method'];
      Object reply;
      if (method == 'tools/list' && errorEcho) {
        reply = {
          'jsonrpc': '2.0',
          'id': id,
          'error': {'code': -32001, 'message': 'rejected $auth'},
        };
      } else if (method == 'tools/list') {
        reply = {
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'tools': [
              {
                'name': 'echo',
                'inputSchema': {'type': 'object', 'properties': {}},
              },
            ],
          },
        };
      } else if (method == 'tools/call') {
        reply = {
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'content': [
              {'type': 'text', 'text': resultEcho ? 'you sent $auth' : 'ok'},
            ],
          },
        };
      } else {
        reply = {'jsonrpc': '2.0', 'id': id, 'result': <String, Object?>{}};
      }
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode(reply));
      await response.close();
    });
  }

  Uri get endpoint => Uri.parse('http://127.0.0.1:${server.port}/mcp');
}

ToolRegistry _registry() {
  final db = ManagedConnection(sqlite3.openInMemory());
  installToolRegistrySchema(db.raw);
  return ToolRegistry(
    database: db,
    resolveScope: (scope) async =>
        ResolvedAssistantScope(requested: scope, objects: const []),
  );
}

Future<McpConnection> _connect(_Server server, String token) =>
    McpAdapter.connect(
      _registry(),
      McpServerConfig(
        id: 'catalog',
        endpoint: server.endpoint,
        credentialRef: 'mcp-catalog',
      ),
      secrets: _Secrets(token),
    );

/// Page store whose connect runs [onConnect].
class _Store implements McpServerStore {
  _Store(this.onConnect, {List<McpServerRecord>? servers})
    : servers = servers ?? [];
  final Future<McpConnection> Function(McpServerRecord) onConnect;
  final List<McpServerRecord> servers;
  final tokens = <String, String>{};
  @override
  List<McpServerRecord> load() => List.of(servers);
  @override
  Future<void> save(McpServerRecord record, String token) async {
    servers
      ..removeWhere((s) => s.id == record.id)
      ..add(record);
    if (token.isNotEmpty) tokens[record.tokenRef] = token;
  }

  @override
  Future<void> remove(McpServerRecord record) async =>
      servers.removeWhere((s) => s.id == record.id);
  @override
  Future<McpConnection> connect(McpServerRecord record) => onConnect(record);
}

void main() {
  group('adapter', () {
    // testWidgets below installs a binding whose HttpClient answers 400.
    setUp(() => HttpOverrides.global = null);
    test('a malformed token fails with mcp_token_invalid before any '
        'request', () async {
      for (final bad in ['tok-$_marker\r', 'tok-$_marker　x', 'tok $_marker']) {
        final server = _Server();
        await server.start();
        Object? thrown;
        try {
          await _connect(server, bad);
        } catch (error) {
          thrown = error;
        }
        await server.server.close(force: true);
        expect(
          thrown,
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'mcp_token_invalid',
          ),
        );
        expect('$thrown', isNot(contains(_marker)));
        expect(server.requests, 0, reason: jsonEncode(bad));
      }
    });

    test('a server error that echoes the token is redacted', () async {
      final server = _Server(errorEcho: true);
      await server.start();
      addTearDown(() => server.server.close(force: true));
      Object? thrown;
      try {
        await _connect(server, _good);
      } catch (error) {
        thrown = error;
      }
      expect(thrown, isNotNull);
      expect(server.requests, greaterThan(0), reason: 'the server answered');
      expect('$thrown', isNot(contains(_marker)));
      expect('$thrown', contains('details withheld'));
    });

    test(
      'a tool result that echoes the token is masked before the receipt',
      () async {
        final server = _Server(resultEcho: true);
        await server.start();
        addTearDown(() => server.server.close(force: true));
        final registry = _registry();
        await McpAdapter.connect(
          registry,
          McpServerConfig(
            id: 'catalog',
            endpoint: server.endpoint,
            credentialRef: 'mcp-catalog',
          ),
          secrets: _Secrets(_good),
        );
        final request = ToolCallRequest(
          invocationId: 'c1',
          toolId: 'mcp.catalog.echo',
          scope: const AssistantScope.global(),
          parameters: const {},
          destination: server.endpoint.origin,
        );
        final result = await registry.invoke(
          request.withApproval(
            await registry.approve(await registry.prepare(request)),
          ),
        );
        expect(result.status, ToolCallStatus.succeeded);
        expect(result.summary, contains('<redacted>'));
        expect(jsonEncode(result.toJson()), isNot(contains(_marker)));
      },
    );
  });

  group('page', () {
    final record = McpServerRecord(
      id: 'catalog',
      endpoint: Uri.parse('http://127.0.0.1:41414/mcp'),
      credentialRef: 'mcp-catalog',
    );

    Widget page(McpServerStore store) => MaterialApp(
      theme: muyonTheme(Brightness.light),
      home: Scaffold(body: McpServersPage(store: store)),
    );

    bool shows(String text) => find
        .byWidgetPredicate(
          (w) =>
              (w is Text && (w.data ?? '').contains(text)) ||
              (w is SelectableText && (w.data ?? '').contains(text)),
        )
        .evaluate()
        .isNotEmpty;

    testWidgets('a malformed token is refused by the adapter and the page '
        'never shows it', (tester) async {
      late _Server server;
      await tester.runAsync(() async {
        server = _Server();
        await server.start();
      });
      final store = _Store(
        (r) => McpAdapter.connect(
          _registry(),
          McpServerConfig(
            id: r.id,
            endpoint: server.endpoint,
            credentialRef: r.credentialRef,
          ),
          secrets: _Secrets('tok-$_marker\r'),
        ),
        servers: [record],
      );
      await tester.pumpWidget(page(store));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('连接'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(shows('mcp_token_invalid'), isTrue);
      expect(shows(_marker), isFalse);
      expect(server.requests, 0);
      await tester.runAsync(() => server.server.close(force: true));
    });

    testWidgets('an error that quotes the token past the check is not shown '
        'on the page', (tester) async {
      final store = _Store(
        (_) async => throw const FormatException(
          'Invalid HTTP header field value: "Bearer tok-$_marker\r"',
        ),
        servers: [record],
      );
      await tester.pumpWidget(page(store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('连接'));
      await tester.pumpAndSettle();
      expect(shows('details withheld'), isTrue);
      expect(shows(_marker), isFalse);
    });

    testWidgets('saving a malformed token is refused and nothing is stored', (
      tester,
    ) async {
      final store = _Store((_) async => throw UnimplementedError());
      await tester.pumpWidget(page(store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加服务器'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('mcp-id-field')),
        'catalog',
      );
      await tester.enterText(
        find.byKey(const ValueKey('mcp-endpoint-field')),
        'http://127.0.0.1:41414/mcp',
      );
      await tester.enterText(
        find.byKey(const ValueKey('mcp-token-field')),
        'tok-$_marker\r',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.text(invalidCredentialMessage), findsOneWidget);
      expect(store.servers, isEmpty);
      expect(store.tokens, isEmpty);
      expect(shows(_marker), isFalse);
    });
  });
}
