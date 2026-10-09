import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:muyon_module_api/ui_contract.dart';

import 'dynamic_fixtures.dart';

class DelayedStore implements UiWorkspaceStore {
  final gate = Completer<void>();
  StoredUiWorkspace? value;
  @override
  Future<StoredUiWorkspace?> load(String _) async => value;
  @override
  Future<bool> save(
    StoredUiWorkspace next, {
    required int expectedRevision,
  }) async {
    await gate.future;
    if ((value?.revision ?? 0) != expectedRevision) return false;
    value = next;
    return true;
  }
}

void main() {
  testWidgets('rapid back while saving returns once to the immediate parent', (
    tester,
  ) async {
    final store = DelayedStore();
    final c = await UiWorkspaceController.open(
      store: store,
      taskId: 't',
      scopeKey: 's',
      plan: actionPlan(),
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => UiWorkspaceView(
                          controller: c,
                          originalAnswer: 'answer',
                        ),
                      ),
                    ),
                    child: const Text('Open workspace'),
                  ),
                ),
              ),
            ),
            child: const Text('Home'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open workspace'));
    await tester.pumpAndSettle();
    final button = tester.widget<IconButton>(
      find.byWidgetPredicate((w) => w is IconButton && w.tooltip == '返回'),
    );
    button.onPressed!();
    button.onPressed!();
    store.gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Open workspace'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });
  testWidgets('scrolling is present in explicit checkpoint before returning', (
    tester,
  ) async {
    final store = DelayedStore();
    store.gate.complete();
    final c = await UiWorkspaceController.open(
      store: store,
      taskId: 't',
      scopeKey: 's',
      plan: actionPlan(),
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: UiWorkspaceView(
          controller: c,
          originalAnswer: List.filled(100, 'long public answer').join('\n'),
        ),
      ),
    );
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();
    await c.flush();
    expect(store.value!.scrollOffset, greaterThan(0));
    final savedOffset = store.value!.scrollOffset;
    await tester.pumpWidget(const SizedBox());
    final restored = await UiWorkspaceController.open(
      store: store,
      taskId: 't',
      scopeKey: 's',
      plan: actionPlan(),
    );
    addTearDown(restored.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: UiWorkspaceView(
          controller: restored,
          originalAnswer: List.filled(100, 'long public answer').join('\n'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!
          .offset,
      closeTo(savedOffset, 1),
    );
  });
}
