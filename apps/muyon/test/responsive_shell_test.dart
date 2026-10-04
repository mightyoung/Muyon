import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/screens/platform_shell.dart';
import 'package:muyon/screens/assistant_page.dart';

void main() {
  for (final width in [320.0, 390.0, 430.0, 1280.0]) {
    testWidgets('platform four sections at $width and 200% text', (
      tester,
    ) async {
      final root = Directory.systemTemp.createTempSync('platform-responsive');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final host = (await tester.runAsync(() => MuyonHost.open(root.path)))!;
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: PlatformShell(
              host: host,
              themeMode: ThemeMode.light,
              onTheme: (_) {},
              onRestore: (_) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final navigation = width >= 900
            ? find.byType(NavigationRail)
            : find.byType(NavigationBar);
        expect(navigation, findsOneWidget);
        expect(
          find.byType(AssistantPage),
          width >= 1250 ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
        for (final label in ['助手', '资料', '工具', '工作台']) {
          await tester.tap(
            find.descendant(of: navigation, matching: find.text(label)),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$label at width $width',
          );
          if (label == '助手') expect(find.byType(AssistantPage), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
      } finally {
        await tester.runAsync(() => host.close());
        root.deleteSync(recursive: true);
      }
    });
  }
}
