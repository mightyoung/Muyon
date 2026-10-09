import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/screens/dynamic_workspace.dart';

/// Drain real SQLite/registered plugin futures until the expected visible state.
/// No elapsed-time sleeps are used to manufacture navigation/save ordering.
Future<void> workspaceReady(WidgetTester tester) async {
  await tester.pump();
  final finder = find.byType(DynamicWorkspace);
  if (finder.evaluate().isNotEmpty) {
    final session = tester.widget<DynamicWorkspace>(finder.first).session;
    if (session != null) await tester.runAsync(session.ensureLoaded);
  }
  await tester.pumpAndSettle();
}

Future<void> workspaceVisible(WidgetTester tester, Finder target) async {
  for (var turn = 0; turn < 1000; turn++) {
    await tester.runAsync(() => Future<void>(() {}));
    await tester.pumpAndSettle();
    if (target.evaluate().isNotEmpty) return;
  }
  fail('Navigation did not expose $target after draining pending event turns');
}
