import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui_preview/preview_app.dart';
import 'package:muyon_ui_preview/fixture_ports.dart';

void main() {
  testWidgets(
    'public_preview_confirm_patch_cancel_and_semantic_are_marked_simulated',
    (tester) async {
      await tester.pumpWidget(PreviewApp(fixture: runtimeFixture()));
      expect(find.textContaining('Simulated business port'), findsOneWidget);
      await tester.ensureVisible(find.text('仅这一次'));
      await tester.tap(find.text('仅这一次'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Simulated receipt'), findsOneWidget);
      expect(find.textContaining('Public memory quantity: 12'), findsOneWidget);
      await tester.ensureVisible(find.text('Apply complete patch'));
      await tester.tap(find.text('Apply complete patch'));
      await tester.pump();
      expect(find.text('Current surface revision: 2'), findsOneWidget);
      await tester.ensureVisible(find.text('Explain'));
      await tester.tap(find.text('Explain'));
      await tester.pump();
      expect(
        find.text('Simulated semantic explanation requested. No model called.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('UI-4a fixture'));
      await tester.tap(find.text('UI-4a fixture'));
      await tester.pump();
      await tester.ensureVisible(find.text('拒绝'));
      await tester.tap(find.text('拒绝'));
      await tester.pump();
      expect(
        find.text('Confirmation cancelled. No request sent.'),
        findsOneWidget,
      );
      expect(find.textContaining('Simulated receipt'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
