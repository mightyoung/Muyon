
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/dream/dream_service.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/screens/memory_page.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_ui/muyon_ui.dart';

/// In-memory database whose writes finish synchronously, so widget tests do
/// not depend on the real event loop.
class _MemoryDb implements ManagedDatabase {
  _MemoryDb() : raw = sqlite3.openInMemory() {
    for (final migration in WorkspaceRepository.schema.migrations) {
      migration.migrate(raw);
    }
  }
  @override
  final Database raw;
  @override
  Future<T> write<T>(T Function(Database database) body) async {
    raw.execute('BEGIN');
    try {
      final result = body(raw);
      raw.execute('COMMIT');
      return result;
    } catch (_) {
      raw.execute('ROLLBACK');
      rethrow;
    }
  }
}

void main() {
  late FoundationRepository repo;
  late DreamService dream;
  var networkCalls = 0;
  final remote = ModelProfile(
    id: 'remote-1',
    endpoint: Uri.parse('https://models.example.com/v1'),
    location: ModelLocation.remote,
    modelId: 'big-model',
    endpointIdentity: 'models.example.com',
    credentialRef: 'k1',
  );

  setUp(() {
    networkCalls = 0;
    repo = FoundationRepository(_MemoryDb());
    dream = DreamService(
      repo,
      gateway: OpenAiModelGateway(
        UnavailableSecretStore(),
        clientFactory: () {
          networkCalls++;
          throw StateError('network is off in this test');
        },
      ),
    );
  });
  Widget app({double scale = 1, List<ModelProfile> profiles = const []}) =>
      MaterialApp(
        theme: muyonTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: MemoryPage(repo: repo, dream: dream, profiles: () => profiles),
        ),
      );

  void size(WidgetTester tester, double w) {
    tester.view.physicalSize = Size(w, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> put(
    WidgetTester tester, {
    required String content,
    required String source,
    bool verified = true,
    bool disabled = false,
    String kind = 'fact',
    bool inference = false,
    DateTime? expiresAt,
  }) async {
    await repo.saveMemory(
      content: content,
      source: source,
      verified: verified,
      disabled: disabled,
      kind: kind,
      inference: inference,
      expiresAt: expiresAt,
    );
    await tester.pump();
  }

  Future<void> tapText(
    WidgetTester tester,
    String text, {
    int index = 0,
  }) async {
    final finder = find.text(text).at(index);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  for (final w in [320.0, 390.0, 430.0, 1280.0]) {
    testWidgets('empty and populated states fit at $w and 200% text', (
      tester,
    ) async {
      size(tester, w);
      await tester.pumpWidget(app(scale: 2));
      expect(find.text('还没有记忆。'), findsOneWidget);
      await put(tester, content: '喜欢先看摘要再看全文', source: '本人确认');
      await put(
        tester,
        content: '模型整理的一句话',
        source: 'dream',
        verified: false,
        kind: 'summary',
        inference: true,
      );
      await tester.pumpAndSettle();
      expect(find.text('喜欢先看摘要再看全文'), findsOneWidget);
      expect(find.text('待确认'), findsOneWidget);
      expect(find.text('整理生成'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'disable keeps the memory but removes it from assistant context',
    (tester) async {
      size(tester, 390);
      await put(tester, content: '偏好深色', source: '本人确认');
      await tester.pumpWidget(app());
      final finder = find.text('停用').at(0);
      await tester.ensureVisible(finder);
      await tester.tap(finder);
    await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      final memory = repo.memories(includeDisabled: true).single;
      expect(memory.disabled, isTrue);
      expect(repo.memoriesFor(const AssistantScope.global()), isEmpty);
      expect(find.text('已停用'), findsWidgets);
      await tapText(tester, '启用');
      expect(repo.memories().single.disabled, isFalse);
    },
  );

  testWidgets('editing a disabled, unverified memory keeps those states', (
    tester,
  ) async {
    size(tester, 390);
    await put(
      tester,
      content: '旧内容',
      source: 'dream',
      verified: false,
      disabled: true,
      kind: 'summary',
      inference: true,
    );
    await tester.pumpWidget(app());
    await tapText(tester, '编辑');
    await tester.enterText(find.widgetWithText(TextField, '内容'), '新内容');
    await tapText(tester, '保存');
    final memory = repo.memories(includeDisabled: true).single;
    expect(memory.content, '新内容');
    expect(memory.disabled, isTrue);
    expect(memory.verified, isFalse);
    expect(memory.kind, 'summary');
    expect(memory.inference, isTrue);
  });

  testWidgets('bad expiry is reported and nothing is saved', (tester) async {
    size(tester, 390);
    await tester.pumpWidget(app());
    await tapText(tester, '添加记忆');
    await tester.enterText(find.widgetWithText(TextField, '内容'), '某事');
    await tester.enterText(
      find.widgetWithText(TextField, '过期日期 YYYY-MM-DD（可留空）'),
      '明天',
    );
    await tapText(tester, '保存');
    expect(find.textContaining('格式应为'), findsOneWidget);
    expect(repo.memories(includeDisabled: true), isEmpty);
  });

  testWidgets('confirm turns a pending memory into a verified one', (
    tester,
  ) async {
    size(tester, 390);
    await put(tester, content: '待确认的事', source: 'dream', verified: false);
    await tester.pumpWidget(app());
    await tapText(tester, '确认');
    expect(repo.memories().single.verified, isTrue);
    expect(find.text('待确认'), findsNothing);
  });

  testWidgets(
    'delete asks first, cancel keeps it, confirm removes it for good',
    (tester) async {
      size(tester, 390);
      await put(tester, content: '要删除的记忆', source: '本人确认');
      await tester.pumpWidget(app());
      await tapText(tester, '删除');
      expect(find.textContaining('不能撤销'), findsOneWidget);
      await tapText(tester, '取消');
      expect(repo.memories(), hasLength(1));
      await tapText(tester, '删除');
      await tapText(tester, '永久删除');
      expect(
        repo.memories(includeDisabled: true, includeExpired: true),
        isEmpty,
      );
      expect(repo.deletedContent('要删除的记忆'), isTrue);
    },
  );

  testWidgets('filters separate active, disabled and expired memories', (
    tester,
  ) async {
    size(tester, 390);
    await put(tester, content: '有效一条', source: 's');
    await put(tester, content: '停用一条', source: 's', disabled: true);
    await put(
      tester,
      content: '过期一条',
      source: 's',
      expiresAt: DateTime.utc(2020),
    );
    await tester.pumpWidget(app());
    await tapText(tester, '已停用');
    expect(find.text('停用一条'), findsOneWidget);
    expect(find.text('有效一条'), findsNothing);
    await tapText(tester, '已过期');
    expect(find.text('过期一条'), findsOneWidget);
    expect(find.text('停用一条'), findsNothing);
    await tapText(tester, '有效');
    expect(find.text('有效一条'), findsOneWidget);
    expect(find.text('过期一条'), findsNothing);
  });

  group('Dream', () {
    Future<void> seedDuplicatesAndConflict(WidgetTester tester) async {
      await put(tester, content: '同一句话', source: 'user');
      await put(tester, content: '同一句话', source: 'user');
      await put(tester, content: '单价：1', source: '报价');
      await put(tester, content: '单价：2', source: '合同');
    }

    testWidgets('runs only on click, offline, and shows proposals', (
      tester,
    ) async {
      size(tester, 390);
      await seedDuplicatesAndConflict(tester);
      await tester.pumpWidget(app());
      expect(
        dream.runs(),
        isEmpty,
        reason: 'opening the page never runs Dream',
      );
      expect(find.text('没有待处理的建议。'), findsOneWidget);
      await tapText(tester, '整理记忆');
      expect(dream.runs(), hasLength(1));
      expect(networkCalls, 0);
      expect(find.text('重复'), findsOneWidget);
      expect(find.text('冲突'), findsOneWidget);
      expect(find.textContaining('不能自动消解'), findsOneWidget);
      // Only the duplicate can be accepted; the conflict is view-only.
      expect(find.text('接受'), findsOneWidget);
    });

    testWidgets('accept disables the extra copy, revert restores it', (
      tester,
    ) async {
      size(tester, 390);
      await seedDuplicatesAndConflict(tester);
      await tester.pumpWidget(app());
      await tapText(tester, '整理记忆');
      await tapText(tester, '接受');
      expect(
        repo.memories(includeDisabled: true).where((m) => m.disabled),
        hasLength(1),
      );
      expect(find.text('已接受'), findsOneWidget);
      await tapText(tester, '撤回最近一次整理');
      expect(find.textContaining('恢复到这次整理开始前'), findsOneWidget);
      await tapText(tester, '撤回');
      expect(repo.memories().where((m) => m.disabled), isEmpty);
      expect(dream.runs().single.status, 'reverted');
      expect(find.text('已撤回。'), findsOneWidget);
    });

    testWidgets('a second run with no changes says so', (tester) async {
      size(tester, 390);
      await seedDuplicatesAndConflict(tester);
      await tester.pumpWidget(app());
      await tapText(tester, '整理记忆');
      await tapText(tester, '整理记忆');
      expect(find.textContaining('没有新的变化'), findsOneWidget);
      expect(dream.runs(), hasLength(1));
    });

    testWidgets('a model needs explicit consent; cancel sends nothing', (
      tester,
    ) async {
      size(tester, 390);
      await seedDuplicatesAndConflict(tester);
      await tester.pumpWidget(app(profiles: [remote]));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('models.example.com').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('运行前会再次确认'), findsOneWidget);
      await tapText(tester, '整理记忆');
      expect(find.textContaining('将把本次新增或变化的记忆内容'), findsOneWidget);
      expect(find.textContaining('远程服务'), findsWidgets);
      await tapText(tester, '取消');
      expect(dream.runs(), isEmpty);
      expect(networkCalls, 0);
    });

    testWidgets('a failed model run is shown, not reported as done', (
      tester,
    ) async {
      size(tester, 390);
      await seedDuplicatesAndConflict(tester);
      await tester.pumpWidget(app(profiles: [remote]));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('models.example.com').last);
      await tester.pumpAndSettle();
      await tapText(tester, '整理记忆');
      await tapText(tester, '发送并整理');
      expect(find.text('整理完成，请在下面查看建议。'), findsNothing);
      expect(
        find.textContaining('network is off').evaluate().isNotEmpty ||
            find.textContaining('整理未完成').evaluate().isNotEmpty,
        isTrue,
      );
      expect(
        repo.memories(includeDisabled: true).where((m) => m.disabled),
        isEmpty,
      );
    });
  });
}
