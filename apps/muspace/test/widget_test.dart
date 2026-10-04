import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muspace/app/app_shell.dart';
import 'package:muspace/app/bootstrap.dart';
import 'package:muspace/screens/assistant_page.dart';

void main() {
  testWidgets('default host opens platform and all four navigation sections', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('platform-navigation');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final host = (await tester.runAsync(() => MuSpaceHost.open(root.path)))!;
    try {
      await tester.pumpWidget(MuSpaceApp(host: host));
      await tester.pumpAndSettle();
      expect(find.text('工作台'), findsOneWidget);
      expect(find.text('Folio · 询价台账'), findsOneWidget);
      expect(find.text('科研工作台'), findsOneWidget);
      expect(host.inquiry, isNull);
      expect(host.research, isNull);
      for (final item in [
        ('助手', find.byType(AssistantPage)),
        ('资料', find.text('数据与知识')),
        ('工具', find.text('页面与助手调用同一注册表；参数与权限由宿主校验。')),
      ]) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(item.$1),
          ),
        );
        await tester.pumpAndSettle();
        expect(item.$2, findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('工作台'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('个人助手'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    } finally {
      await tester.runAsync(() => host.close());
      root.deleteSync(recursive: true);
    }
  });
}
