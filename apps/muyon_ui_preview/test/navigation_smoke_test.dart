import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:muyon_ui_preview/workspace_preview.dart';
import 'package:muyon_ui_preview/workspace_store.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1440, 1100)]) {
    testWidgets('public navigation keeps edited workspace at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final disk = <String, String>{};
      final store = FixtureWorkspaceStore(
        read: (key) => disk[key],
        write: (key, value) => disk[key] = value,
      );
      await tester.pumpWidget(
        MaterialApp(home: WorkspacePreview(store: store)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '12');
      await tester.pumpAndSettle();
      for (final label in ['Open public object', 'Open public source']) {
        expect(find.text(label), findsOneWidget);
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.textContaining('Simulated navigation'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          '12',
        );
      }
      final c = tester
          .widget<UiWorkspaceView>(find.byType(UiWorkspaceView))
          .controller;
      expect(c.returnAnchor, contains('public-ui3b'));
      await c.flush();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(home: WorkspacePreview(store: store)),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '12',
      );
      expect(
        tester
            .widget<UiWorkspaceView>(find.byType(UiWorkspaceView))
            .controller
            .returnAnchor,
        c.returnAnchor,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
