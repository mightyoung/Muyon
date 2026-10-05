import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/mcp_adapter.dart';
import 'package:muyon/screens/mcp_servers_page.dart';
import 'package:muyon_ui/muyon_ui.dart';

/// E2 page acceptance: add/edit/remove and connect flows driven through an
/// injected [McpServerStore] double, so UI states need no database. The real
/// host store is covered in `mcp_servers_store_test.dart`.
void main() {
  late _FakeStore store;

  setUp(() => store = _FakeStore());

  McpServerRecord record({String? credentialRef}) => McpServerRecord(
    id: 'catalog',
    endpoint: Uri.parse('http://127.0.0.1:41414/mcp'),
    credentialRef: credentialRef,
  );

  Widget page() => MaterialApp(
    theme: muyonTheme(Brightness.light),
    home: Scaffold(body: McpServersPage(store: store)),
  );

  Future<void> fill(
    WidgetTester tester, {
    String id = 'catalog',
    String? endpoint,
    String? token,
  }) async {
    await tester.enterText(find.byKey(const ValueKey('mcp-id-field')), id);
    await tester.enterText(
      find.byKey(const ValueKey('mcp-endpoint-field')),
      endpoint ?? 'http://127.0.0.1:41414/mcp',
    );
    if (token != null) {
      await tester.enterText(
        find.byKey(const ValueKey('mcp-token-field')),
        token,
      );
    }
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
  }

  testWidgets('adds a server and shows the saved token', (tester) async {
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('尚未配置 MCP 服务器。'), findsOneWidget);

    await tester.tap(find.text('添加服务器'));
    await tester.pumpAndSettle();
    await fill(tester, token: 'secret-token');

    expect(find.text('catalog'), findsOneWidget);
    expect(find.textContaining('已保存令牌'), findsOneWidget);
    expect(store.servers.single.id, 'catalog');
    expect(store.servers.single.credentialRef, 'mcp-catalog');
    expect(store.tokens['mcp-catalog'], 'secret-token');
    expect(tester.takeException(), isNull);
  });

  testWidgets('validation errors are shown inline and nothing is saved', (
    tester,
  ) async {
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加服务器'));
    await tester.pumpAndSettle();
    await fill(tester, id: 'Bad ID!', endpoint: 'http://example.com/mcp');
    expect(find.textContaining('小写字母'), findsOneWidget);
    expect(find.textContaining('https'), findsWidgets);
    expect(store.servers, isEmpty);

    await fill(tester, endpoint: 'http://127.0.0.1:41414/mcp');
    expect(store.servers.single.id, 'catalog');

    await tester.tap(find.text('添加服务器'));
    await tester.pumpAndSettle();
    await fill(tester);
    expect(find.textContaining('已存在'), findsOneWidget);
    expect(store.servers.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('connects only when asked and lists registered and skipped', (
    tester,
  ) async {
    store.servers.add(record());
    store.connection = (server) => McpConnection(
      McpServerConfig(
        id: server.id,
        endpoint: server.endpoint,
        credentialRef: server.credentialRef,
      ),
      const ['mcp.catalog.search'],
      const {'fancy': 'invalid_schema: Unsupported schema keyword'},
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(store.connects, isEmpty);

    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();
    expect(store.connects, ['catalog']);
    expect(find.textContaining('已注册 1 个工具'), findsOneWidget);
    expect(find.text('mcp.catalog.search'), findsOneWidget);
    expect(find.textContaining('跳过 1 个工具'), findsOneWidget);
    expect(find.textContaining('fancy'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removal needs confirmation and clears the list', (tester) async {
    store.servers.add(record(credentialRef: 'mcp-catalog'));
    store.tokens['mcp-catalog'] = 'secret-token';
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    await tester.tap(find.text('移除'));
    await tester.pumpAndSettle();
    expect(find.textContaining('服务器已移除'), findsOneWidget);
    await tester.tap(find.text('确认移除'));
    await tester.pumpAndSettle();

    expect(store.servers, isEmpty);
    expect(store.tokens, isEmpty);
    expect(find.text('尚未配置 MCP 服务器。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing keeps the token when the field stays empty', (
    tester,
  ) async {
    store.servers.add(record(credentialRef: 'mcp-catalog'));
    store.tokens['mcp-catalog'] = 'secret-token';
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.textContaining('留空保持不变'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('mcp-endpoint-field')),
      'http://127.0.0.1:41414/mcp?v=2',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(
      store.servers.single.endpoint.toString(),
      'http://127.0.0.1:41414/mcp?v=2',
    );
    expect(store.servers.single.credentialRef, 'mcp-catalog');
    expect(store.tokens['mcp-catalog'], 'secret-token');
    expect(tester.takeException(), isNull);
  });
}

class _FakeStore implements McpServerStore {
  final servers = <McpServerRecord>[];
  final tokens = <String, String>{};
  final connects = <String>[];
  McpConnection Function(McpServerRecord)? connection;

  @override
  List<McpServerRecord> load() => List.of(servers);

  @override
  Future<void> save(McpServerRecord record, String token) async {
    servers
      ..removeWhere((server) => server.id == record.id)
      ..add(record);
    if (token.isNotEmpty) tokens[record.tokenRef] = token;
  }

  @override
  Future<void> remove(McpServerRecord record) async {
    servers.removeWhere((server) => server.id == record.id);
    tokens.remove(record.tokenRef);
  }

  @override
  Future<McpConnection> connect(McpServerRecord record) async {
    connects.add(record.id);
    return connection!(record);
  }
}
