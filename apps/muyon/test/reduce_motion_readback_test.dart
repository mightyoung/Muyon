import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/app_shell.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/screens/assistant_page.dart';

void main() {
  testWidgets('reduce_motion_unset_keeps_animations', (tester) async {
    final root = Directory.systemTemp.createTempSync('reduce-motion-readback');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final host = (await tester.runAsync(() => MuyonHost.open(root.path)))!;
    try {
      await tester.pumpWidget(MuyonApp(host: host));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(AssistantPage));
      expect(MediaQuery.of(context).disableAnimations, isFalse);
      await tester.pumpWidget(const SizedBox());
    } finally {
      await tester.runAsync(() => host.close());
      root.deleteSync(recursive: true);
    }
  });

  testWidgets('reduce_motion_stored_true_disables_animations_on_open', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('reduce-motion-readback');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final host = (await tester.runAsync(() => MuyonHost.open(root.path)))!;
    try {
      await tester.runAsync(
        () => host.workspaces.setSetting('reduceMotion', true),
      );
      await tester.pumpWidget(MuyonApp(host: host));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(AssistantPage));
      expect(MediaQuery.of(context).disableAnimations, isTrue);
      await tester.pumpWidget(const SizedBox());
    } finally {
      await tester.runAsync(() => host.close());
      root.deleteSync(recursive: true);
    }
  });
}
