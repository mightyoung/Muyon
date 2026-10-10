import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/ui_planning_events.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/host_authorization_facts.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_module_api/muyon_module_api.dart' show AssistantScope;
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:muyon_ui/muyon_ui.dart';

import 'support/aiui6_snapshot_fixture.dart';
import 'support/ui_public_fixture.dart';

void main() {
  for (final scenario in ['late', 'unknown', 'refuse', 'once']) {
    test('actual host external-content $scenario keeps business authority', () async {
      final f = await InquirySnapshotFixture.open();
      UiSurfaceController? surface;
      UiPlanningEventRouter? router;
      try {
        final ref = f.refs['project_item']!;
        final conversation = await f.host.foundation.createConversation(scope: AssistantScope.selectedObjects([ref]));
        final parent = await f.host.personalAgent.start(conversationId: conversation.id, prompt: '没有模型');
        final fixture = runtimeFixture();
        final plan = validateUiPlan(fixture.plan.plan!, fixture.snapshot, fixture.intent, fixture.catalog!).validatedPlan!;
        late UiPlanningEventRouter activeRouter;
        final activeSurface = UiSurfaceController(plan, onEvent: (event) => activeRouter.dispatch(event));
        surface = activeSurface;
        activeRouter = UiPlanningEventRouter(agent: f.host.personalAgent, taskId: parent.id,
          surface: activeSurface, businessActions: {'confirm': UiBusinessAction('inquiry.set_item_qty',
            (pending) => {'item_id': ref.objectId, 'from_qty': '2', 'to_qty': pending.inputs['quantity']})});
        router = activeRouter;
        final confirm = plan.plan.nodes.firstWhere((node) => node.id == 'confirmation');
        final before = activeSurface.captureRender();
        final approvals = f.host.foundation.database.raw.select('SELECT * FROM tool_approvals').length;
        final grants = f.host.assistantGrants.list().length;
        final history = f.host.tools.history().length;
        if (scenario == 'late') {
          expect(before.externalContent, isFalse);
          final marking = f.host.foundation.authorizationFacts.markExternal(parent.id, HostSourceFact.object(ref));
          expect(activeSurface.hasExternalContent, isTrue, reason: 'Pending taint denies before SQL commit');
          expect(await activeSurface.dispatchCaptured(before, confirm, 'confirm'), UiDispatchOutcome.stale);
          await marking;
        } else if (scenario == 'unknown') {
          await f.host.foundation.database.write((db) => db.execute(
            'DELETE FROM settings WHERE key=?', ['auth1b:task:${parent.id}']));
          expect(f.host.foundation.authorizationFacts.readTask(parent.id).taintState, HostTaintState.unknown);
          await activeSurface.dispatch(activeSurface.eventFor(confirm, 'confirm'));
          expect(activeSurface.portError, isNotNull);
        } else {
          await f.host.foundation.authorizationFacts.markExternal(parent.id, HostSourceFact.object(ref));
          expect(activeSurface.hasExternalContent, isTrue);
          if (scenario == 'refuse') {
            await activeSurface.dispatch(activeSurface.eventFor(confirm, 'cancel'));
          } else {
            final event = activeSurface.eventFor(confirm, 'confirm');
            await activeSurface.dispatch(event);
            final child = f.host.foundation.task(activeRouter.tasks[event.eventId]!)!;
            expect(child.state, PersonalTaskState.waitingConfirmation);
            expect(f.host.foundation.authorizationFacts.readTask(child.id).requiresConfirmation, isTrue);
            expect(f.host.inquiry!.runtime.state.store.get('project_item', ref.objectId)!.data['qty'], '2');
            await f.host.personalAgent.confirm(child.id, requestDigest: child.payload['requestDigest'] as String);
            expect(f.host.inquiry!.runtime.state.store.get('project_item', ref.objectId)!.data['qty'], '12');
            expect(activeSurface.receiptFor(confirm)!.status, UiReceiptStatus.succeeded);
            expect(activeSurface.receiptFor(confirm)!.isSimulated, isFalse);
          }
        }
        expect(f.host.assistantGrants.list().length, grants);
        if (scenario != 'once') {
          expect(activeRouter.tasks, isEmpty);
          expect(f.host.inquiry!.runtime.state.store.get('project_item', ref.objectId)!.data['qty'], '2');
          expect(f.host.tools.history().length, history);
          expect(f.host.foundation.database.raw.select('SELECT * FROM tool_approvals').length, approvals);
        }
      } finally { router?.dispose(); surface?.dispose(); await f.close(); }
    });
  }
  testWidgets('unknown dynamic batch confirmation warns and removes allow-all but keeps refusal', (tester) async {
    final fixture = runtimeFixture();
    final original = fixture.plan.plan!;
    final plan = original.copyWith(nodes: [for (final node in original.nodes)
      node.id == 'confirmation' ? node.copyWith(component: 'BatchConfirmCard') : node]);
    final checked = validateUiPlan(plan, fixture.snapshot, fixture.intent, fixture.catalog!).validatedPlan!;
    final surface = UiSurfaceController(checked, onEvent: (_) async {});
    try {
      await tester.pumpWidget(MaterialApp(theme: muyonTheme(Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: DynamicUiSurface(plan: checked, controller: surface)))));
      expect(tester.widget<BatchConfirmCard>(find.byType(BatchConfirmCard)).externalContent, isTrue);
      expect(find.text('全部允许'), findsNothing);
      expect(find.text('逐项决定'), findsOneWidget);
      expect(find.text('拒绝'), findsOneWidget);
      final reject = find.widgetWithText(TextButton, '拒绝');
      await tester.ensureVisible(reject); await tester.tap(reject); await tester.pump();
      expect(surface.session.isCancelled('confirmation'), isTrue);
    } finally { await tester.pumpWidget(const SizedBox.shrink()); surface.dispose(); }
  });
}
