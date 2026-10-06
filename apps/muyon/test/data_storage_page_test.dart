import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/screens/data_storage_page.dart';
import 'package:muyon/screens/storage_status.dart';
import 'package:muyon_ui/muyon_ui.dart';

const _root = '/data/muyon';

StorageStatus _status({
  Map<String, String> unavailable = const {},
  List<CatalogRow>? catalog,
  Map<String, String> projection = const {},
}) => StorageStatus(
  rootPath: _root,
  unavailableModules: unavailable,
  catalog:
      catalog ??
      const [
        CatalogRow(
          moduleId: 'muyon',
          targetVersion: 6,
          observedVersion: 6,
          status: 'ready',
          lastError: null,
        ),
      ],
  projectionErrors: projection,
);

class _Calls {
  final created = <String>[];
  final restored = <String>[];
  final verified = <String>[];
}

Widget _page(
  _Calls calls, {
  StorageStatus? status,
  List<String> problems = const [],
  String? picked = '/picked',
  Future<Map<String, Object?>> Function(String)? create,
  double scale = 1,
}) => MaterialApp(
  theme: muyonTheme(Brightness.light),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: DataStoragePage(
      readStatus: () => status ?? _status(),
      pickDirectory: (_) async => picked,
      verify: (dir) async {
        calls.verified.add(dir);
        return problems;
      },
      clock: () => DateTime.utc(2026, 10, 4, 12, 30, 45),
      createBackup:
          create ??
          (target) async {
            calls.created.add(target);
            return {
              'entries': [1, 2, 3],
            };
          },
      restore: (dir) async => calls.restored.add(dir),
    ),
  ),
);

void _size(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _tapButton(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 390.0, 430.0, 1280.0]) {
    testWidgets('healthy state renders at $width and 200% text', (
      tester,
    ) async {
      _size(tester, width);
      await tester.pumpWidget(_page(_Calls(), scale: 2));
      expect(find.text('所有已登记模块可用。'), findsOneWidget);
      expect(find.text('就绪', skipOffstage: false), findsOneWidget);
      expect(
        find.textContaining('未发现投影错误', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text(_root), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('failure states render at $width and 200% text', (
      tester,
    ) async {
      _size(tester, width);
      await tester.pumpWidget(
        _page(
          _Calls(),
          scale: 2,
          status: _status(
            unavailable: {'inquiry': 'Missing required module research'},
            projection: {'research': 'disk full'},
            catalog: const [
              CatalogRow(
                moduleId: 'research',
                targetVersion: 8,
                observedVersion: 9,
                status: 'blocked',
                lastError: 'Database is newer than this app',
              ),
            ],
          ),
        ),
      );
      expect(find.text('不可用', skipOffstage: false), findsOneWidget);
      expect(
        find.text('Missing required module research', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('已阻止', skipOffstage: false), findsOneWidget);
      expect(
        find.textContaining('Database is newer', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('滞后', skipOffstage: false), findsOneWidget);
      expect(
        find.textContaining('disk full', skipOffstage: false),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('create backup writes a new directory under the picked one', (
    tester,
  ) async {
    _size(tester, 1280);
    final calls = _Calls();
    await tester.pumpWidget(_page(calls));
    await _tapButton(tester, '创建备份');
    expect(calls.created, ['/picked/muyon-backup-20261004123045000']);
    expect(find.text('备份已创建'), findsOneWidget);
    expect(find.textContaining('共 3 个文件'), findsOneWidget);
  });

  testWidgets('create backup failure is shown, never as success', (
    tester,
  ) async {
    _size(tester, 390);
    await tester.pumpWidget(
      _page(
        _Calls(),
        create: (_) async => throw StateError('Backup target already exists'),
      ),
    );
    await _tapButton(tester, '创建备份');
    expect(find.text('备份已创建'), findsNothing);
    expect(find.text('操作失败'), findsOneWidget);
    expect(find.textContaining('already exists'), findsOneWidget);
  });

  testWidgets('verify failure lists every problem and shows no success', (
    tester,
  ) async {
    _size(tester, 390);
    await tester.pumpWidget(
      _page(_Calls(), problems: ['Altered: muyon.sqlite', 'Missing: a/b.pdf']),
    );
    await _tapButton(tester, '校验备份');
    expect(find.text('校验通过'), findsNothing);
    expect(find.textContaining('发现 2 个问题'), findsOneWidget);
    expect(find.text('Altered: muyon.sqlite'), findsOneWidget);
    expect(find.text('Missing: a/b.pdf'), findsOneWidget);
  });

  testWidgets('verify success says what was checked', (tester) async {
    _size(tester, 390);
    await tester.pumpWidget(_page(_Calls()));
    await _tapButton(tester, '校验备份');
    expect(find.text('校验通过'), findsOneWidget);
  });

  testWidgets('cancelled picker does nothing', (tester) async {
    _size(tester, 390);
    final calls = _Calls();
    await tester.pumpWidget(_page(calls, picked: null));
    await _tapButton(tester, '创建备份');
    await _tapButton(tester, '校验备份');
    await _tapButton(tester, '从备份恢复');
    expect(calls.created, isEmpty);
    expect(calls.verified, isEmpty);
    expect(calls.restored, isEmpty);
  });

  testWidgets('restore of a failing backup never reaches the host', (
    tester,
  ) async {
    _size(tester, 390);
    final calls = _Calls();
    await tester.pumpWidget(_page(calls, problems: ['Corrupt database: x']));
    await _tapButton(tester, '从备份恢复');
    expect(find.text('关闭并恢复'), findsNothing);
    expect(find.textContaining('未做任何恢复'), findsOneWidget);
    expect(find.text('Corrupt database: x'), findsOneWidget);
    expect(calls.restored, isEmpty);
  });

  testWidgets('restore explains the restart and keeps old data wording', (
    tester,
  ) async {
    _size(tester, 390);
    final calls = _Calls();
    await tester.pumpWidget(_page(calls));
    await _tapButton(tester, '从备份恢复');
    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.textContaining('关闭并重启')),
      findsOneWidget,
    );
    expect(find.textContaining('$_root.before-restore-*'), findsOneWidget);
    expect(find.textContaining('不会被删除'), findsOneWidget);
    await _tapButton(tester, '取消');
    expect(calls.restored, isEmpty);
    await _tapButton(tester, '从备份恢复');
    await _tapButton(tester, '关闭并恢复');
    expect(calls.restored, ['/picked']);
  });
}
