import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/screens/platform_shell.dart';
import 'package:muyon/screens/assistant_page.dart';

void main() {
  testWidgets('assistant_is_default_and_four_destinations_are_exact', (tester) async {
    final root = Directory.systemTemp.createTempSync('platform-default');
    final host = (await tester.runAsync(() => MuyonHost.open(root.path)))!;
    try {
      await tester.pumpWidget(MaterialApp(home: PlatformShell(
        host: host, themeMode: ThemeMode.light,
        onTheme: (_) {}, onRestore: (_) async {},
      )));
      await tester.pumpAndSettle();
      final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(nav.selectedIndex, 0);
      expect(nav.destinations.cast<NavigationDestination>().map((d) => d.label),
          ['助手', '任务', '资料', '设置']);
      expect(find.byType(AssistantPage), findsOneWidget);
      expect(find.byType(AssistantPage, skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    } finally {
      await tester.runAsync(host.close);
      root.deleteSync(recursive: true);
    }
  });

  for (final width in [320.0, 390.0, 430.0, 900.0, 1250.0, 1280.0]) {
    testWidgets('four_destinations_320_390_430_900_1250_1280_at_200_percent ($width)', (tester) async {
      final root = Directory.systemTemp.createTempSync('platform-responsive');
      final host = (await tester.runAsync(() => MuyonHost.open(root.path)))!;
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: PlatformShell(host: host, themeMode: ThemeMode.light,
            onTheme: (_) {}, onRestore: (_) async {}),
        ));
        await tester.pumpAndSettle();
        final navigation = width >= 900 ? find.byType(NavigationRail) : find.byType(NavigationBar);
        expect(navigation, findsOneWidget);
        expect(find.byType(AssistantPage), findsOneWidget);
        final initialState = tester.state(find.byType(AssistantPage));
        for (final label in ['助手', '任务', '资料', '设置', '助手']) {
          await tester.tap(find.descendant(of: navigation, matching: find.text(label)));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$label at width $width');
          expect(find.byType(AssistantPage, skipOffstage: false), findsOneWidget);
          if (label == '助手') expect(tester.state(find.byType(AssistantPage)), same(initialState));
        }
        await tester.pumpWidget(const SizedBox());
      } finally {
        await tester.runAsync(host.close);
        root.deleteSync(recursive: true);
      }
    });
  }
}
