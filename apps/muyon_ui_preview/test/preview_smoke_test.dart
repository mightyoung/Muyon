import 'package:flutter/material.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui_preview/preview_app.dart';
import 'package:muyon_ui_preview/fixture_ports.dart';

void main() {
  testWidgets('source_tap_cannot_route_to_detail_without_value', (
    tester,
  ) async {
    final f = comparisonFixture();
    final bad = f.plan.plan!.copyWith(
      nodes: [
        for (final node in f.plan.plan!.nodes)
          if (node.id == 'source-a')
            node.copyWith(events: {'tap': ActionBinding(actionRef: 'detail')})
          else
            node,
      ],
    );
    final checked = validateUiPlan(bad, f.snapshot, f.intent, minimalUiCatalog);
    expect(checked.isValid, isFalse);
    expect(checked.validatedPlan, isNull);
    await tester.pumpWidget(
      PreviewApp(
        fixture: PreviewFixture(
          snapshot: f.snapshot,
          intent: f.intent,
          answer: f.answer,
          plan: UiPlanningResult(
            decision: UiDisplayDecision.supplement,
            reasonCode: 'bad-source-route',
            plan: bad,
          ),
        ),
      ),
    );
    expect(find.text(f.answer), findsOneWidget);
    expect(find.byKey(const ValueKey('source-a-expand')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('field_change_cannot_route_to_back_and_leave_draft_unchanged', (
    tester,
  ) async {
    final f = comparisonFixture();
    final bad = f.plan.plan!.copyWith(
      nodes: [
        for (final node in f.plan.plan!.nodes)
          if (node.id == 'quantity')
            node.copyWith(events: {'change': ActionBinding(actionRef: 'back')})
          else
            node,
      ],
    );
    final checked = validateUiPlan(bad, f.snapshot, f.intent, minimalUiCatalog);
    expect(checked.isValid, isFalse);
    expect(checked.validatedPlan, isNull);
    await tester.pumpWidget(
      PreviewApp(
        fixture: PreviewFixture(
          snapshot: f.snapshot,
          intent: f.intent,
          answer: f.answer,
          plan: UiPlanningResult(
            decision: UiDisplayDecision.supplement,
            reasonCode: 'bad-edit-route',
            plan: bad,
          ),
        ),
      ),
    );
    expect(find.text(f.answer), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // Losing session state on detail navigation or ignoring a plan binding fails.
  for (final size in [const Size(390, 844), const Size(1440, 900)]) {
    testWidgets('preview_click_edit_and_back $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(PreviewApp(fixture: comparisonFixture()));
      expect(
        find.text('Public comparison: 10 pieces at 12 per piece.'),
        findsOneWidget,
      );
      expect(find.text('Fixture total: 120'), findsOneWidget);
      expect(
        find.text('Public source A: 10 pieces; unit price 12.'),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('source-a-expand')));
      await tester.pump();
      expect(
        find.text('Public source A: 10 pieces; unit price 12.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('quantity-field')),
        '12',
      );
      await tester.pump();
      expect(find.text('Fact quantity: 10'), findsOneWidget);
      expect(find.text('Fixture total: 120'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('quote-a-detail')));
      await tester.tap(find.byKey(const ValueKey('quote-a-detail')));
      await tester.pumpAndSettle();
      expect(find.text('Quote A detail'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('detail-back')));
      await tester.pumpAndSettle();
      final field = tester.widget<TextFormField>(
        find.byKey(const ValueKey('quantity-field')),
      );
      expect(field.controller!.text, '12');
      expect(
        find.text('Public source A: 10 pieces; unit price 12.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('invalid_plan_keeps_complete_text_without_controls', (
    tester,
  ) async {
    final fixture = comparisonFixture(invalid: true);
    await tester.pumpWidget(PreviewApp(fixture: fixture));
    expect(
      find.text('Public comparison: 10 pieces at 12 per piece.'),
      findsOneWidget,
    );
    expect(
      find.text('Interactive view unavailable. Original answer retained.'),
      findsOneWidget,
    );
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('second_public_fixture_renders_conflict_and_original_source', (
    tester,
  ) async {
    final fixture = comparisonFixture(alternative: true);
    expect(fixture.snapshot.facts['qty']!.state, FactState.verified);
    expect(fixture.snapshot.facts['delivery']!.state, FactState.conflict);
    expect(fixture.snapshot.facts['delivery']!.field, 'delivery');
    await tester.pumpWidget(PreviewApp(fixture: fixture));
    expect(find.text('Quote B'), findsOneWidget);
    expect(find.text('conflict'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('source-a-expand')));
    await tester.pump();
    expect(
      find.text(
        'Public source B: 10 pieces; unit price 12. Conflicting delivery estimates 3 and 5 days.',
      ),
      findsOneWidget,
    );
  });
  testWidgets('unbound_controls_do_not_advertise_edit_or_click', (
    tester,
  ) async {
    final f = comparisonFixture();
    final plan = f.plan.plan!;
    final inactive = PreviewFixture(
      snapshot: f.snapshot,
      intent: f.intent,
      answer: f.answer,
      plan: UiPlanningResult(
        decision: UiDisplayDecision.supplement,
        reasonCode: 'read-only',
        plan: plan.copyWith(
          nodes: [for (final node in plan.nodes) node.copyWith(events: {})],
        ),
      ),
    );
    await tester.pumpWidget(PreviewApp(fixture: inactive));
    final field = tester.widget<TextFormField>(
      find.byKey(const ValueKey('quantity-field')),
    );
    final input = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('quantity-field')),
        matching: find.byType(TextField),
      ),
    );
    expect(input.readOnly, isTrue);
    expect(field.controller!.text, '10');
    final expand = tester.widget<TextButton>(
      find.byKey(const ValueKey('source-a-expand')),
    );
    expect(expand.onPressed, isNull);
  });
}
