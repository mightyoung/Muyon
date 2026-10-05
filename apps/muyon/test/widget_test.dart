import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/app_shell.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/screens/assistant_page.dart';

void main() {
  testWidgets('default host opens platform and all four navigation sections', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('platform-navigation');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final host = (await tester.runAsync(() => MuyonHost.open(root.path)))!;
    try {
      await tester.pumpWidget(MuyonApp(host: host));
      await tester.pumpAndSettle();
      expect(find.text('工作台'), findsOneWidget);
      expect(find.text('Folio · 询价台账'), findsOneWidget);
      expect(find.text('科研工作台'), findsOneWidget);
      expect(host.inquiry, isNull);
      expect(host.research, isNull);
      for (final item in [
        ('助手', find.byType(AssistantPage)),
        ('资料', find.text('数据与知识')),
        ('我的', find.text('接口与工具')),
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
      // Phone hub: each entry is its own page with a back button.
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('我的'),
        ),
      );
      await tester.pumpAndSettle();
      for (final entry in [
        ('接口与工具', find.text('页面与助手调用同一注册表；参数与权限由宿主校验。')),
        ('数据与存储', find.text('备份与恢复')),
        ('系统设置', find.text('外观')),
      ]) {
        await tester.tap(find.text(entry.$1).first);
        await tester.pumpAndSettle();
        expect(entry.$2, findsWidgets, reason: entry.$1);
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
        expect(find.text('个人中心'), findsOneWidget, reason: 'back to hub');
      }
      await tester.pumpWidget(const SizedBox());
    } finally {
      await tester.runAsync(() => host.close());
      root.deleteSync(recursive: true);
    }
  });
}
