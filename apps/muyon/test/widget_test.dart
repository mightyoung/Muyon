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
      expect(find.byType(AssistantPage), findsOneWidget);
      expect(host.inquiry, isNull);
      expect(host.research, isNull);
      for (final item in [
        ('助手', find.byType(AssistantPage)),
        ('任务', find.text('执行面板')),
        ('资料', find.text('资料检索')),
        ('设置', find.text('接口与工具')),
      ]) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(item.$1),
          ),
        );
        await tester.pumpAndSettle();
        expect(item.$2, findsOneWidget);
        if (item.$1 == '资料') {
          expect(find.text('Folio · 询价台账'), findsOneWidget);
          expect(find.text('科研工作台'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('助手'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('个人助手'), findsOneWidget);
      // Phone hub: each entry is its own page with a back button. A tall
      // surface keeps tiles clear of the bottom navigation bar.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('设置'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('外观'), findsOneWidget);
      for (final entry in const [
        ('接口与工具', '页面与助手调用同一注册表；参数与权限由宿主校验。'),
        ('数据与存储', '备份与恢复'),
        ('设备聊天', '只在本人已配对、同时在线的设备之间发送文字，没有中继。聊天内容不会授予任何操作权限，也不会自动进入助手上下文。'),
        ('记忆与整理', '整理'),
      ]) {
        final scroll = find.descendant(of: find.byType(ListView), matching: find.byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down,
        ));
        expect(scroll, findsOneWidget);
        // A previous child may have been opened lower in the lazy settings
        // list. Return toward the top with a gesture before finding the next
        // entry, including entries that have not been built yet.
        await tester.drag(scroll, const Offset(0, 1600));
        await tester.pumpAndSettle();
        final tile = find.widgetWithText(ListTile, entry.$1);
        await tester.scrollUntilVisible(tile, 100, scrollable: scroll, maxScrolls: 60);
        await tester.pumpAndSettle();
        expect(tile.hitTestable(), findsOneWidget);
        await tester.tap(tile.hitTestable());
        await tester.pumpAndSettle();
        expect(
          find.text(entry.$2, skipOffstage: false),
          findsWidgets,
          reason: entry.$1,
        );
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
        expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
            3, reason: 'back to selected settings hub');
        expect(find.byTooltip('返回'), findsNothing, reason: 'child page closed');
      }
      await tester.pumpWidget(const SizedBox());
    } finally {
      await tester.runAsync(() => host.close());
      root.deleteSync(recursive: true);
    }
  });
}
