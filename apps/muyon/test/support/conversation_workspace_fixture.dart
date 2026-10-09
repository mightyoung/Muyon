import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/screens/dynamic_workspace.dart';

/// Start an operation in the real zone while also advancing callbacks queued
/// earlier in the widget binding's fake zone. Direct runAsync-await would stop
/// those fake callbacks and can deadlock SQLite's serialized write tail.
Future<T> workspaceOperation<T>(
  WidgetTester tester,
  Future<T> Function() operation,
) async {
  var completed = false;
  late T result;
  Object? failure;
  StackTrace? failureStack;
  await tester.runAsync(() async {
    try {
      operation().then<void>((value) {
        result = value;
        completed = true;
      }, onError: (Object error, StackTrace stack) {
        failure = error;
        failureStack = stack;
        completed = true;
      });
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
      completed = true;
    }
  });
  for (var turn = 0; turn < 2000 && !completed; turn++) {
    await tester.runAsync(() => Future<void>(() {}));
    await tester.pump();
  }
  if (!completed) fail('Workspace operation did not finish after draining real and fake event turns');
  if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  return result;
}

/// Drain real SQLite/registered plugin futures until the expected visible state.
/// No elapsed-time sleeps are used to manufacture navigation/save ordering.
Future<void> workspaceReady(WidgetTester tester) async {
  final loaded = <DynamicWorkspaceSession>{};
  var stable = 0;
  for (var turn = 0; turn < 2000; turn++) {
    await tester.runAsync(() => Future<void>(() {}));
    await tester.pump(const Duration(milliseconds: 16));
    final finder = find.byType(DynamicWorkspace);
    if (finder.evaluate().isEmpty) { stable = 0; continue; }
    final session = tester.widget<DynamicWorkspace>(finder).session;
    if (session != null && loaded.add(session)) {
      await workspaceOperation(tester, session.ensureLoaded);
      stable = 0;
      continue;
    }
    stable = tester.binding.hasScheduledFrame ? 0 : stable + 1;
    if (stable >= 2) return;
  }
  fail('Workspace did not finish loading and responsive route animation');
}

Future<void> workspaceVisible(WidgetTester tester, Finder target) =>
    _workspaceSettled(tester, () => target.evaluate().isNotEmpty,
      'Navigation did not expose $target');

Future<void> workspaceGone(WidgetTester tester, Finder target) =>
    _workspaceSettled(tester, () => target.evaluate().isEmpty,
      'Navigation did not remove $target');

Future<void> _workspaceSettled(WidgetTester tester, bool Function() ready, String failure) async {
  var stable = 0;
  for (var turn = 0; turn < 2000; turn++) {
    // Yield to native SQLite between every animation frame. pumpAndSettle
    // alone starves real futures while an async progress indicator animates.
    await tester.runAsync(() => Future<void>(() {}));
    await tester.pump(const Duration(milliseconds: 16));
    stable = ready() && !tester.binding.hasScheduledFrame ? stable + 1 : 0;
    if (stable >= 2) return;
  }
  fail('$failure after draining pending event turns and animation frames');
}
