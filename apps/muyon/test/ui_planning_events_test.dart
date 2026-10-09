import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/business_tools.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/assistant/ui_planning_events.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import 'support/ui_public_fixture.dart';

void main() {
  test(
    'three_event_routes_preserve_authority with actual host Store and receipts',
    () async {
      final root = Directory.systemTemp.createTempSync('ui4b-events-');
      var host = await MuyonHost.open(root.path);
      addTearDown(() async {
        await host.close();
        root.deleteSync(recursive: true);
      });
      await host.activateInquiry();
      final store = host.inquiry!.runtime.state.store;
      final project = store.save('project', {
        'code': 'UI4B',
        'name': 'Planning test',
        'status': 'active',
        'type': 'market',
        'level': 'A',
        'customer': null,
        'contract_no': null,
        'contract_amount': null,
        'department': null,
        'leader': null,
        'start_date': null,
        'end_date': null,
        'notes': null,
        'currency': 'CNY',
        'tax_mode': 'included',
        'markup_rate': '0',
      });
      final item = store.save('project_item', {
        'project_id': project,
        'category': 'material',
        'name': 'fixture item',
        'qty': '10',
        'unit': 'pieces',
        'unit_cost': '0',
        'product_id': null,
        'quotation_id': null,
        'unit_price': null,
        'notes': null,
      });
      final all = await resolveAssistantScope(
        host,
        const AssistantScope.global(),
      );
      final refs = all.objects
          .where((r) => r.objectId == item || r.objectId == project)
          .toList();
      final conversation = await host.foundation.createConversation(
        scope: AssistantScope.selectedObjects(refs),
      );
      final task = await host.personalAgent.start(
        conversationId: conversation.id,
        prompt: 'Show fixture quote',
      );
      final fixture = runtimeFixture();
      final checked = validateUiPlan(
        fixture.plan.plan!,
        fixture.snapshot,
        fixture.intent,
        fixture.catalog!,
      ).validatedPlan!;
      late UiPlanningEventRouter router;
      final surface = UiSurfaceController(
        checked,
        onEvent: (event) => router.dispatch(event),
      );
      addTearDown(surface.dispose);
      router = UiPlanningEventRouter(
        agent: host.personalAgent,
        taskId: task.id,
        surface: surface,
        businessActions: {
          'confirm': UiBusinessAction(
            'inquiry.set_item_qty',
            (pending) => {
              'item_id': item,
              'from_qty': '10',
              'to_qty': pending.inputs['quantity'],
            },
          ),
        },
      );
      addTearDown(router.dispose);
      final sort = checked.plan.nodes.firstWhere((n) => n.id == 'sort');
      await surface.dispatch(surface.eventFor(sort, 'change', 'value'));
      expect(router.tasks, isEmpty);
      expect(store.get('project_item', item)!.data['qty'], '10');
      final confirm = checked.plan.nodes.firstWhere(
        (n) => n.id == 'confirmation',
      );
      final event = surface.eventFor(confirm, 'confirm');
      await surface.dispatch(event);
      expect(
        router.tasks[event.eventId],
        isNotNull,
        reason: 'business event must prepare an actual host task',
      );
      expect(
        store.get('project_item', item)!.data['qty'],
        '10',
        reason: 'a component selection is not approval',
      );
      final child = host.foundation.task(router.tasks[event.eventId]!)!;
      expect(child.state, PersonalTaskState.waitingConfirmation);
      expect(child.stage, 'tool');
      await host.personalAgent.confirm(
        child.id,
        requestDigest: child.payload['requestDigest'] as String,
      );
      expect(store.get('project_item', item)!.data['qty'], '12');
      expect(surface.receiptFor(confirm)!.status, UiReceiptStatus.succeeded);
      expect(surface.receiptFor(confirm)!.isSimulated, isFalse);
      expect(
        await recoverUiPlanningOperation(
          host.personalAgent,
          task.id,
          checked.plan.surfaceId,
          confirm.events['confirm']!.operationKeyRef!,
        ),
        UiOperationRecovery.succeeded,
      );
      await surface.dispatch(event);
      expect(router.tasks, hasLength(1));
      final warning = checked.plan.nodes.firstWhere((n) => n.id == 'warning');
      await surface.dispatch(surface.eventFor(warning, 'tap'));
      expect(
        router.tasks,
        hasLength(2),
        reason: 'semantic event must return to actual harness once',
      );
      router.dispose();
      await host.close();
      host = await MuyonHost.open(root.path);
      await host.activateInquiry();
      expect(
        await recoverUiPlanningOperation(
          host.personalAgent,
          task.id,
          checked.plan.surfaceId,
          confirm.events['confirm']!.operationKeyRef!,
        ),
        UiOperationRecovery.succeeded,
      );
      expect(
        host.inquiry!.runtime.state.store
            .get('project_item', item)!
            .data['qty'],
        '12',
      );
    },
  );
}
