import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui/muyon_ui.dart';

import 'support/widget_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadUiTestFont);
  for (final config in [
    for (final brightness in Brightness.values)
      for (final width in [320.0, 390.0, 1280.0])
        (brightness: brightness, width: width),
  ]) {
    final width = config.width;
    final brightness = config.brightness;
    testWidgets(
      'dialog content grows and remains actionable at $width/200% $brightness',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await tester.binding.setSurfaceSize(Size(width, 1000));
          var confirmed = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: muyonTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => MuyonDialog(
                        title: '确认删除所选项目与相关记录',
                        message: '删除后可以在回收站恢复，范围仅限当前明确选择的对象。请核对这个完整说明。',
                        confirmLabel: '确认删除',
                        onConfirm: () => confirmed++,
                      ),
                    ),
                    child: const Text('打开对话框'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('打开对话框'));
          await tester.pumpAndSettle();
          expect(find.bySemanticsLabel('对话框：确认删除所选项目与相关记录'), findsOneWidget);
          final action = find.bySemanticsLabel('确认删除');
          minimum(tester, action);
          await tester.ensureVisible(action);
          await tester.tap(action);
          await tester.pumpAndSettle();
          expect(confirmed, 1);
          expect(find.byType(MuyonDialog), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('打开对话框'));
          await tester.pumpAndSettle();
          minimum(tester, find.bySemanticsLabel('取消'));
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(confirmed, 1);
        } finally {
          semantics.dispose();
          await tester.binding.setSurfaceSize(null);
        }
      },
    );
    for (final status in [
      BusinessStatus.success,
      BusinessStatus.failed,
      BusinessStatus.warning,
    ]) {
      testWidgets(
        'toast $status wraps with semantic action at $width/200% $brightness',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            var action = 0;
            await mount(
              tester,
              MuyonToast(
                message: '完整结果说明：对象已处理，请核对结果和范围',
                status: status,
                actionLabel: '查看结果',
                onAction: () => action++,
              ),
              width: width,
              brightness: brightness,
            );
            expect(
              find.bySemanticsLabel('${status.label}：完整结果说明：对象已处理，请核对结果和范围'),
              findsOneWidget,
            );
            minimum(tester, find.bySemanticsLabel('查看结果'));
            await tester.tap(find.text('查看结果'));
            expect(action, 1);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
            await tester.binding.setSurfaceSize(null);
          }
        },
      );
    }
  }
}
