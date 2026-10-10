import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:muyon_ui/muyon_ui.dart';

import 'dynamic_fixtures.dart';

class CountingController extends UiSurfaceController {
  CountingController(super.plan, {super.onEvent});
  int bottomDispatches = 0;
  @override
  Future<UiDispatchOutcome> dispatch(UiEvent event) {
    bottomDispatches++;
    return super.dispatch(event);
  }
}

void main() {
  test('capture rejects foreign controller, copied node, unknown event and disposal', () async {
    final plan = actionPlan();
    final first = CountingController(plan);
    final other = CountingController(plan);
    final capture = first.captureRender();
    final node = plan.plan.nodes.firstWhere((n) => n.id == 'quantity');
    expect(
      await other.dispatchCaptured(capture, node, 'change', '99'),
      UiDispatchOutcome.stale,
    );
    expect(
      await first.dispatchCaptured(capture, node.copyWith(), 'change', '99'),
      UiDispatchOutcome.stale,
    );
    expect(
      await first.dispatchCaptured(capture, node, 'unknown'),
      UiDispatchOutcome.stale,
    );
    expect(first.bottomDispatches, 0);
    expect(other.bottomDispatches, 0);
    first.dispose();
    expect(
      await first.dispatchCaptured(capture, node, 'change', '99'),
      UiDispatchOutcome.stale,
    );
    expect(first.bottomDispatches, 0);
    other.dispose();
  });

  for (final business in [false, true]) {
    testWidgets(
      'old ${business ? 'business' : 'edit'} callback before rebuild dispatches nothing',
      (tester) async {
        var sinkCalls = 0;
        final initial = actionPlan();
        final controller = CountingController(
          initial,
          onEvent: (_) async {
            sinkCalls++;
          },
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: muyonTheme(Brightness.light),
            home: Scaffold(
              body: SingleChildScrollView(
                child: DynamicUiSurface(plan: initial, controller: controller),
              ),
            ),
          ),
        );
        final edit = tester
            .widget<TextFormField>(find.byKey(const ValueKey('quantity-field')))
            .onChanged!;
        final confirm = tester
            .widget<ConfirmCard>(find.byType(ConfirmCard))
            .onDecision!;
        final next = validateUiPlan(
          initial.plan.copyWith(revision: initial.plan.revision + 1),
          initial.snapshot,
          initial.intent,
          initial.catalog,
        ).validatedPlan!;
        expect(controller.acceptPlan(next), isTrue);
        // No pump: invoke an actual closure retained by the old rendered widget.
        if (business) {
          confirm(ConfirmationChoice.once);
        } else {
          edit('99');
        }
        await Future<void>.value();
        expect(controller.bottomDispatches, 0);
        expect(sinkCalls, 0);
        expect(controller.session.userOverrides, isEmpty);
        expect(controller.session.draftRevision, 0);
        await tester.pump();
        if (business) {
          tester.widget<ConfirmCard>(find.byType(ConfirmCard)).onDecision!(
            ConfirmationChoice.once,
          );
        } else {
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('quantity-field')),
              )
              .onChanged!('99');
        }
        await tester.pump();
        expect(controller.bottomDispatches, 1);
        expect(sinkCalls, business ? 1 : 0);
      },
    );
  }
}
