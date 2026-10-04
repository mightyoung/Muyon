import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muspace/app/app_shell.dart';
import 'package:muspace/app/bootstrap.dart';

void main() {
  for (final width in [320.0, 390.0, 430.0, 1280.0]) {
    testWidgets('host at $width and 200% text', (tester) async {
      final root = Directory.systemTemp.createTempSync('muspace-ui-');
      final host = await MuSpaceHost.open(root.path);
      try {
        await host.activateResearch();
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: WorkspacePage(
              host: host,
              themeMode: ThemeMode.light,
              onTheme: (_) {},
              initialModule: 'research',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('创建工作区，开始研究'), findsOneWidget);
        expect(find.text('新建工作区'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally {
        await host.close();
        root.deleteSync(recursive: true);
      }
    });
  }
}
