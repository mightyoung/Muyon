import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/app_shell.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/module_catalog.dart';
import 'package:muyon/platform/object_pages.dart';
import 'package:muyon/screens/platform_shell.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'support/fake_v2_module.dart';

class _PagesRuntime extends FakeRuntime implements ObjectPages {
  _PagesRuntime(super.resources);
  int released = 0;
  bool hasPage = true;
  @override
  Future<ObjectPageLease?> open(BuildContext context, ObjectRef ref) async =>
      hasPage
      ? ObjectPageLease(
          title: '记事 ${ref.objectId}',
          page: const Text('NOTE PAGE'),
          dispose: () async => released++,
        )
      : null;
}

/// REG-2b: home cards, the module menu and object pages follow declarations.
/// The three v1 modules must look exactly as they did when hard-coded.
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('declared-ui-'));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<MuyonHost> open(
    WidgetTester tester, [
    List<BusinessModule>? extra,
  ]) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final host = (await tester.runAsync(
      () => MuyonHost.open(
        root.path,
        modules: extra == null ? null : [...extra, ...moduleCatalog()],
      ),
    ))!;
    addTearDown(() => tester.runAsync(host.close));
    return host;
  }

  Widget shell(MuyonHost host) => MaterialApp(
    home: PlatformShell(
      host: host,
      themeMode: ThemeMode.light,
      onTheme: (_) {},
      onRestore: (_) async {},
    ),
  );

  testWidgets(
    'the home page lists the three v1 modules as before, nothing activated',
    (tester) async {
      final host = await open(tester);
      await tester.pumpWidget(shell(host));
      await tester.pumpAndSettle();
      final tiles = tester.widgetList<ListTile>(
        find.byWidgetPredicate(
          (w) =>
              w is ListTile &&
              w.title is Text &&
              const [
                'Folio · 询价台账',
                '科研工作台',
                '原型页面',
              ].contains((w.title as Text).data),
        ),
      );
      expect(
        [
          for (final t in tiles)
            ((t.title as Text).data, (t.subtitle as Text).data),
        ],
        [
          ('Folio · 询价台账', '完整供应商、询价报价和成本业务'),
          ('科研工作台', '原文阅读、批注、研究过程和成果'),
          ('原型页面', '导入单页原型，评审版本并记录反馈（不是完整业务系统）'),
        ],
      );
      expect(
        [for (final t in tiles) (t.leading as Icon).icon],
        [
          Icons.receipt_long_outlined,
          Icons.menu_book_outlined,
          Icons.web_outlined,
        ],
      );
      expect(host.research, isNull);
      expect(host.prototype, isNull);
      expect(host.inquiry, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a v2 module appears on the home page and opens its own section',
    (tester) async {
      final host = await open(tester, [
        FakeV2Module(
          'notes',
          displayName: '记事本',
          tagline: '随手记一笔',
          sections: [
            fakeSection(
              'notes',
              body: const Scaffold(body: Text('NOTES BODY')),
            ),
          ],
        ),
      ]);
      await tester.pumpWidget(shell(host));
      await tester.pumpAndSettle();
      expect(find.text('随手记一笔'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('记事本'));
        // Native SQLite activation must finish outside the widget fake clock.
        // The separate lifecycle regression verifies the tap admits activation.
        await host.modules.activate('notes');
      });
      await tester.pumpAndSettle();
      expect(find.text('NOTES BODY'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'the module menu is built from sections; prototype stays out of it',
    (tester) async {
      final notes = FakeV2Module(
        'notes',
        displayName: '记事本',
        sections: [
          fakeSection(
            'notes',
            label: '记事本',
            body: const Center(child: Text('NOTES BODY')),
          ),
        ],
      );
      final host = await open(tester, [notes]);
      // Real file I/O cannot run inside the widget test's fake clock.
      await tester.runAsync(() => host.modules.activate('notes'));
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspacePage(
            host: host,
            themeMode: ThemeMode.light,
            onTheme: (_) {},
            initialModule: 'notes',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('NOTES BODY'), findsOneWidget);
      expect(find.text('Muyon · 记事本'), findsOneWidget);
      expect(notes.activations, 1);
      await tester.tap(find.byTooltip('业务插件'));
      await tester.pump(const Duration(milliseconds: 400));
      final labels = tester
          .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
          .map((item) => (item.child! as Text).data)
          .toList();
      expect(labels, ['记事本', 'Folio · 询价与成本', '科研工作台']);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a declared module that cannot activate says so in its section', (
    tester,
  ) async {
    final host = await open(tester, [
      // Tool registration fails, so the module is blocked without any I/O.
      FakeV2Module(
        'broken',
        onRegisterTools: (_) => throw StateError('boom from broken'),
        sections: [fakeSection('broken', label: '坏模块')],
      ),
    ]);
    await tester.runAsync(() => host.modules.activate('broken'));
    await tester.pumpWidget(
      MaterialApp(
        home: WorkspacePage(
          host: host,
          themeMode: ThemeMode.light,
          onTheme: (_) {},
          initialModule: 'broken',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('坏模块 不可用'), findsOneWidget);
    expect(find.textContaining('boom from broken'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'object pages: a v2 module opens its own page with no workspace binding',
    (tester) async {
      final module = FakeV2Module(
        'notes',
        features: {ModuleFeature.objectPages},
        runtimeFactory: _PagesRuntime.new,
      );
      final host = await open(tester, [module]);
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      const ref = ObjectRef(
        moduleId: 'notes',
        objectType: 'note',
        objectId: 'n1',
        nativeProjectId: 'p-unbound',
      );
      final opened = (await tester.runAsync(
        () => openModuleObjectPage(context, host, ref),
      ))!;
      expect(opened.title, '记事 n1');
      expect(host.workspaces.all(), isEmpty, reason: 'no binding was created');
      final runtime = module.runtime! as _PagesRuntime;
      expect(runtime.released, 0);
      await tester.runAsync(opened.dispose);
      await tester.runAsync(opened.dispose);
      expect(runtime.released, 1);

      runtime.hasPage = false;
      expect(
        await tester.runAsync(() => openModuleObjectPage(context, host, ref)),
        isNull,
      );
    },
  );

  testWidgets(
    'object pages: a module that did not declare the feature is not asked',
    (tester) async {
      final module = FakeV2Module('plain', runtimeFactory: _PagesRuntime.new);
      final host = await open(tester, [module]);
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      const ref = ObjectRef(
        moduleId: 'plain',
        objectType: 'note',
        objectId: 'n1',
      );
      expect(
        await tester.runAsync(() => openModuleObjectPage(context, host, ref)),
        isNull,
      );
      expect(module.activations, 0);
    },
  );
}
