import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui_preview/workspace_preview.dart';
import 'package:muyon_ui_preview/workspace_store.dart';

void main() {
  testWidgets(
    'public storage close recreate retains manually edited quantity',
    (tester) async {
      final disk = <String, String>{};
      FixtureWorkspaceStore store() => FixtureWorkspaceStore(
        read: (key) => disk[key],
        write: (key, value) {
          disk[key] = value;
        },
      );
      await tester.pumpWidget(
        MaterialApp(home: WorkspacePreview(store: store())),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '14');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save checkpoint'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(home: WorkspacePreview(store: store())),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '14',
      );
      expect(find.textContaining('Public fixture storage'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
