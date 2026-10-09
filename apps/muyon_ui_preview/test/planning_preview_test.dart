import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_ui_preview/preview_app.dart';
import 'package:muyon_ui_preview/fixture_ports.dart';
import 'package:muyon_ui_preview/planning_preview.dart';
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:muyon_module_api/ui_contract.dart';

void main() {
  test('both_modes_share_validator_renderer_and_features', () async {
    for (final mode in UiPlanningMode.values) {
      final request = publicPlanningRequest(mode);
      final watch = Stopwatch()..start();
      final result = await publicPlanningProvider.plan(request);
      watch.stop();
      final validated = validateUiPlan(
        result.plan!,
        request.snapshot,
        request.intent,
        request.catalog,
      ).validatedPlan!;
      final controller = UiSurfaceController(validated);
      addTearDown(controller.dispose);
      UiNode node(String id) =>
          validated.plan.nodes.firstWhere((n) => n.id == id);
      expect(
        await controller.dispatch(
          controller.eventFor(node('quantity'), 'change', '14'),
        ),
        UiDispatchOutcome.applied,
      );
      expect(
        controller.session.resolve(const BindingRef.uiState('quantity')),
        '14',
      );
      expect(
        await controller.dispatch(
          controller.eventFor(node('sort'), 'change', 'value'),
        ),
        UiDispatchOutcome.applied,
      );
      expect(
        controller.session.resolve(const BindingRef.uiState('sort')),
        'value',
      );
      expect(
        controller.session.resolve(const BindingRef.computed('total')),
        120,
      );
      expect(
        await controller.dispatch(controller.eventFor(node('source-a'), 'tap')),
        UiDispatchOutcome.applied,
      );
      expect(controller.session.isExpanded('source-a'), isTrue);
      expect(
        controller.session.resolve(const BindingRef.sourceSpan('original')),
        contains('Public source B'),
      );
      await controller.dispatch(controller.eventFor(node('quote-a'), 'tap'));
      expect(controller.session.detailNode, 'quote-a');
      await controller.dispatch(controller.eventFor(node('quote-a'), 'back'));
      expect(controller.session.detailNode, isNull);
      // Fixture-only measurement, deliberately distinct from real model effects.
      // ignore: avoid_print
      print(
        '${mode.name}: fixture latency ${watch.elapsedMicroseconds}us; network=false; cost=0; edit/compare/navigation/source passed; real model effect untested',
      );
    }
  });
  testWidgets('both modes use shared public planning preview and renderer', (
    tester,
  ) async {
    await tester.pumpWidget(PreviewApp(fixture: runtimeFixture()));
    expect(find.text('UI-4b planning'), findsOneWidget);
    await tester.tap(find.text('UI-4b planning'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Both modes use fixture Provider'),
      findsOneWidget,
    );
    expect(find.text('Intelligent fixture'), findsOneWidget);
    expect(find.text('Motivation fixture'), findsOneWidget);
    await tester.tap(find.text('Motivation fixture'));
    await tester.pumpAndSettle();
    expect(find.textContaining('mode: motivation'), findsOneWidget);
    expect(find.textContaining('No network · cost 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
