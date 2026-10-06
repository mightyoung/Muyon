import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_ui/muyon_ui.dart';
import 'package:path/path.dart' as p;
import 'package:prototype_module/prototype_module.dart';
import 'package:prototype_module/src/prototype_store.dart';
import 'package:sqlite3/sqlite3.dart';

class _Db implements ManagedDatabase {
  _Db() : raw = sqlite3.openInMemory() {
    createPrototypeTables(raw);
  }
  @override
  final Database raw;
  @override
  Future<T> write<T>(T Function(Database database) body) async {
    raw.execute('BEGIN');
    try {
      final r = body(raw);
      raw.execute('COMMIT');
      return r;
    } catch (_) {
      raw.execute('ROLLBACK');
      rethrow;
    }
  }
}

/// Real file IO needs the real event loop; interleave it with frame pumps.
Future<void> io(WidgetTester tester, {bool Function()? until}) async {
  for (var i = 0; i < 60 && !(until?.call() ?? i >= 5); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late Directory tmp;
  late PrototypeStore store;
  late Directory build;
  PrototypeWebConfig? lastConfig;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('proto-ui');
    store = PrototypeStore(database: _Db(), filesRoot: p.join(tmp.path, 'f'));
    build = Directory(p.join(tmp.path, 'dist'))..createSync();
    File(p.join(build.path, 'index.html')).writeAsStringSync('<p>x</p>');
    lastConfig = null;
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Widget app({String? picked}) => MaterialApp(
    theme: muyonTheme(Brightness.light),
    home: PrototypeHome(
      store: store,
      pickDirectory: () async => picked,
      webViewBuilder: (config) {
        lastConfig = config;
        return const Center(child: Text('fake web view'));
      },
    ),
  );

  void size(WidgetTester tester, double w) {
    tester.view.physicalSize = Size(w, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final w in [320.0, 390.0, 430.0, 1280.0]) {
    testWidgets('empty state and scope notice at $w', (tester) async {
      size(tester, w);
      await tester.pumpWidget(app());
      expect(find.textContaining('不代表完整业务系统'), findsOneWidget);
      expect(find.textContaining('还没有原型页面'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('import, open, feedback flow', (tester) async {
    size(tester, 390);
    await tester.pumpWidget(app(picked: build.path));
    await tester.tap(find.text('导入原型构建'));
    await tester.pump();
    await io(tester);
    await tester.enterText(find.byType(TextField), 'MES 原型');
    await tester.tap(find.text('导入'));
    await tester.pump();
    await io(tester, until: () => store.pages().isNotEmpty);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('MES 原型'), findsOneWidget);
    await tester.tap(find.text('MES 原型'));
    await tester.pumpAndSettle();
    expect(find.text('v1'), findsOneWidget);
    await tester.tap(find.text('打开 v1'));
    await tester.pumpAndSettle();
    expect(find.text('fake web view'), findsOneWidget);
    final config = lastConfig!;
    expect(config.guard.allowsNavigation('https://example.com'), isFalse);
    expect(config.spec.bridgeChannels, {feedbackChannel});
    config.onBlocked('javascript:alert(1)');
    await tester.pump();
    expect(find.textContaining('已拦截越界访问'), findsOneWidget);
    config.onBridge(feedbackChannel, ['页面里的反馈']);
    await tester.pumpAndSettle();
    expect(find.text('原型页面请求提交反馈'), findsOneWidget);
    await tester.tap(find.text('拒绝'));
    await tester.pumpAndSettle();
    expect(store.feedback(store.pages().single.id), isEmpty);
    config.onBridge(feedbackChannel, ['页面里的反馈']);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('保存反馈'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(store.feedback(store.pages().single.id).single.text, '页面里的反馈');
  });

  testWidgets('import failure is shown, never listed', (tester) async {
    size(tester, 390);
    File(p.join(build.path, 'index.html')).deleteSync();
    await tester.pumpWidget(app(picked: build.path));
    await tester.tap(find.text('导入原型构建'));
    await tester.pump();
    await io(tester);
    await tester.tap(find.text('导入'));
    await tester.pump();
    await io(tester);
    expect(find.textContaining('缺少 index.html'), findsOneWidget);
    expect(store.pages(), isEmpty);
  });

  test('module declares schema, route and session resolution', () async {
    final module = PrototypeModule();
    expect(module.manifest.id, 'prototype');
    expect(module.schema.version, 1);
    expect(module.routes.single.path, '/');
    final db = _Db();
    final runtime = PrototypeRuntime(
      ModuleResources(
        database: db,
        files: _Files(p.join(tmp.path, 'mod')),
        capabilities: CapabilityRegistry().forModule('prototype', allowed: {}),
      ),
    );
    final v = await runtime.store.importBuild(
      sourceDir: build.path,
      title: 'T',
    );
    final session = await runtime.openSession(
      const WorkspaceBinding(
        workspaceId: 'w',
        moduleId: 'prototype',
        nativeProjectId: 'n',
      ),
    );
    final view = await session.resolve(
      ObjectRef(moduleId: 'prototype', objectType: 'version', objectId: v.id),
    );
    expect(view!.title, 'T v1');
    expect(
      await session.resolve(
        const ObjectRef(
          moduleId: 'prototype',
          objectType: 'page',
          objectId: 'ghost',
        ),
      ),
      isNull,
    );
    expect(await runtime.receipt('x'), isNull);
  });
}

class _Files implements ModuleFiles {
  _Files(this.rootPath);
  @override
  final String rootPath;
  @override
  Future<SelectedInput> freeze(SelectedInput input) async => input;
}
