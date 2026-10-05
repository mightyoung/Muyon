import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/screens/data_flow_page.dart';
import 'package:muyon/screens/data_storage_page.dart';
import 'package:muyon/screens/storage_status.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_ui/muyon_ui.dart';
import 'package:path/path.dart' as p;

/// E1 acceptance: the page shows what actually left the device using the real
/// host tables, with text (not colour alone), filters, empty and failure
/// states. The ledger stores digests and sizes, so payload content must never
/// appear.
void main() {
  late Directory tmp;
  late MuyonHost host;
  var counter = 0;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('data-flow-');
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> open(WidgetTester tester) async {
    host = (await tester.runAsync(
      () => MuyonHost.open(p.join(tmp.path, 'data')),
    ))!;
    addTearDown(() async {
      await tester.runAsync(() => host.close());
    });
  }

  final local = ModelProfile(
    id: 'local-1',
    endpoint: Uri.parse('http://127.0.0.1:11434/v1/chat/completions'),
    location: ModelLocation.local,
    modelId: 'qwen2.5',
    endpointIdentity: '本机 Ollama',
  );
  final remote = ModelProfile(
    id: 'remote-1',
    endpoint: Uri.parse('https://api.example.com/v1/chat/completions'),
    location: ModelLocation.remote,
    modelId: 'cloud-1',
    endpointIdentity: '远程服务',
    credentialRef: 'model-remote',
    cloudProxy: true,
  );

  Future<void> request(
    WidgetTester tester, {
    required String caller,
    required String status,
    ModelProfile? profile,
    String payload = '{"q":"hello"}',
    int itemCount = 1,
  }) => tester.runAsync(() async {
    final id = await host.outbound.begin(
      caller: caller,
      profile: profile ?? local,
      payload: payload,
      itemCount: itemCount,
    );
    if (status != 'sending') {
      await host.outbound.finish(
        id,
        status,
        httpStatus: status == 'succeeded' ? 200 : null,
        error: status == 'failed' ? 'connection refused' : null,
      );
    }
  });

  Future<void> toolCall(
    WidgetTester tester, {
    required String toolId,
    required ToolCallStatus status,
    required String summary,
  }) => tester.runAsync(() {
    final n = counter++;
    final result = ToolCallResult(
      status: status,
      summary: summary,
      executionId: 'exec-$n',
    );
    return host.workspaces.database.write(
      (db) => db.execute(
        'INSERT INTO tool_invocation_receipts VALUES(?,?,?,?,?,?)',
        ['rk-$n', 'inv-$n', 'digest', toolId, status.name, jsonEncode(result.toJson())],
      ),
    );
  });

  Future<void> approval(
    WidgetTester tester, {
    required String toolId,
    String? destination,
    required String state,
  }) => tester.runAsync(() {
    final n = counter++;
    return host.workspaces.database.write(
      (db) => db.execute(
        'INSERT INTO tool_approvals VALUES(?,?,?,?,?,?,?,?,?,?,?)',
        [
          'ap-$n',
          'session',
          toolId,
          'identity',
          'scope',
          'input',
          destination,
          '2026-10-04T10:00:00.000Z',
          '2026-10-04T10:02:00.000Z',
          state,
          state == 'consumed' ? '2026-10-04T10:01:00.000Z' : null,
        ],
      ),
    );
  });

  Widget page({
    DataFlowSnapshot Function()? read,
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) => MaterialApp(
    theme: muyonTheme(brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(body: DataFlowPage(host: host, read: read)),
  );

  void resize(WidgetTester tester, double width) {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pickFilter(WidgetTester tester, Key key, String label) async {
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('lists every state, endpoint and size, but never payload text', (
    tester,
  ) async {
    resize(tester, 1280);
    await open(tester);
    await request(
      tester,
      caller: 'assistant',
      status: 'succeeded',
      itemCount: 3,
    );
    await request(
      tester,
      caller: 'dream',
      status: 'failed',
      profile: remote,
    );
    await request(tester, caller: 'embedding', status: 'sending');
    await request(tester, caller: 'research.qa', status: 'interrupted');
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    expect(find.textContaining('assistant · 成功'), findsOneWidget);
    expect(find.textContaining('dream · 失败'), findsOneWidget);
    expect(find.textContaining('embedding · 发送中'), findsOneWidget);
    expect(find.textContaining('research.qa · 中断（结果未知）'), findsOneWidget);
    expect(find.textContaining('结果未知，重试前请先核实'), findsOneWidget);
    expect(
      find.textContaining('http://127.0.0.1:11434/v1/chat/completions'),
      findsWidgets,
    );
    expect(find.textContaining('https://api.example.com'), findsOneWidget);
    expect(find.textContaining('经云代理'), findsOneWidget);
    expect(find.textContaining('本机'), findsWidgets);
    expect(find.textContaining('远程'), findsWidgets);
    expect(find.textContaining('载荷'), findsWidgets);
    expect(find.textContaining('connection refused'), findsOneWidget);

    // The ledger only has digests and sizes; no payload content is shown.
    expect(find.textContaining('hello'), findsNothing);
    expect(find.textContaining('{"q"'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filters by caller and status', (tester) async {
    resize(tester, 1280);
    await open(tester);
    await request(tester, caller: 'assistant', status: 'succeeded');
    await request(tester, caller: 'dream', status: 'failed');
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    await pickFilter(
      tester,
      const ValueKey('data-flow-caller-filter'),
      'dream',
    );
    expect(find.textContaining('assistant · '), findsNothing);
    expect(find.textContaining('dream · 失败'), findsOneWidget);

    await pickFilter(
      tester,
      const ValueKey('data-flow-status-filter'),
      '成功',
    );
    expect(find.textContaining('dream · 失败'), findsNothing);
    expect(find.text('没有符合筛选的记录。'), findsOneWidget);

    await pickFilter(
      tester,
      const ValueKey('data-flow-caller-filter'),
      '全部调用方',
    );
    expect(find.textContaining('assistant · 成功'), findsOneWidget);
    expect(find.textContaining('dream · '), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tool calls and approvals show status and destination', (
    tester,
  ) async {
    resize(tester, 1280);
    await open(tester);
    await toolCall(
      tester,
      toolId: 'inquiry.supplier.list',
      status: ToolCallStatus.succeeded,
      summary: '已列出 3 家供应商',
    );
    await toolCall(
      tester,
      toolId: 'mcp.catalog.search',
      status: ToolCallStatus.interrupted,
      summary: '请求已发出但未收到结果',
    );
    await approval(
      tester,
      toolId: 'mcp.catalog.search',
      destination: 'https://mcp.example.com/mcp',
      state: 'issued',
    );
    await approval(
      tester,
      toolId: 'inquiry.supplier.create',
      destination: null,
      state: 'consumed',
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    expect(find.textContaining('已列出 3 家供应商'), findsOneWidget);
    expect(find.textContaining('工具调用 · 成功'), findsOneWidget);
    expect(find.textContaining('工具调用 · 中断（结果未知）'), findsOneWidget);
    expect(
      find.textContaining('结果未知，重试前请先核实'),
      findsOneWidget,
    );
    expect(find.text('批准记录'), findsOneWidget);
    expect(
      find.textContaining('https://mcp.example.com/mcp'),
      findsOneWidget,
    );
    expect(find.textContaining('已发放'), findsOneWidget);
    expect(find.textContaining('已使用'), findsOneWidget);
    expect(find.textContaining('本地'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty host explains each section instead of showing nothing', (
    tester,
  ) async {
    resize(tester, 390);
    await open(tester);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    expect(find.text('暂无数据发送记录。'), findsOneWidget);
    expect(find.text('暂无工具调用记录。'), findsOneWidget);
    expect(find.text('暂无批准记录。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed read shows the reason and retry recovers', (
    tester,
  ) async {
    resize(tester, 390);
    await open(tester);
    await request(tester, caller: 'assistant', status: 'succeeded');
    var broken = true;
    await tester.pumpWidget(
      page(
        read: () {
          if (broken) throw StateError('数据库不可读');
          return DataFlowSnapshot.readFrom(host);
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('读取失败'), findsOneWidget);
    expect(find.textContaining('数据库不可读'), findsOneWidget);
    expect(find.textContaining('assistant · '), findsNothing);

    broken = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('读取失败'), findsNothing);
    expect(find.textContaining('assistant · 成功'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the data & storage page exposes the data-flow entry', (
    tester,
  ) async {
    resize(tester, 390);
    await tester.pumpWidget(
      MaterialApp(
        theme: muyonTheme(Brightness.light),
        home: Scaffold(
          body: DataStoragePage(
            readStatus: () => const StorageStatus(
              rootPath: '/data',
              unavailableModules: {},
              catalog: [],
              projectionErrors: {},
            ),
            createBackup: (_) async => const {},
            restore: (_) async {},
            pickDirectory: (_) async => null,
            dataFlow: const Scaffold(body: Text('去向内容')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('数据去向'));
    await tester.tap(find.text('数据去向'));
    await tester.pumpAndSettle();
    expect(find.text('去向内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1280.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('renders at $width and ${scale * 100}% text', (tester) async {
        resize(tester, width);
        await open(tester);
        await request(
          tester,
          caller: 'assistant',
          status: 'succeeded',
          profile: remote,
          itemCount: 128,
        );
        await request(
          tester,
          caller: 'dream',
          status: 'interrupted',
          payload: 'x' * 40,
        );
        await toolCall(
          tester,
          toolId: 'mcp.catalog.search',
          status: ToolCallStatus.failed,
          summary: '远程服务器错误：schema 不受支持，已跳过注册',
        );
        await approval(
          tester,
          toolId: 'mcp.catalog.search',
          destination: 'https://mcp.example.com/a/very/long/path/mcp',
          state: 'issued',
        );
        await tester.pumpWidget(page(scale: scale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
