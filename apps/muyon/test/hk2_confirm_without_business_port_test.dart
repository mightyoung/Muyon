import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/assistant/personal_agent.dart';
import 'package:muyon/assistant/ui_planning.dart';
import 'package:muyon/assistant/ui_presentation_preference.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon/screens/dynamic_workspace.dart';
import 'package:muyon_module_api/muyon_module_api.dart' show AssistantScope;
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:muyon_ui/muyon_ui.dart';

import '../../../packages/muyon_ui/test/dynamic_fixtures.dart';

/// HK-2 / invariant 2: a confirm card whose business event has no mapped
/// business port must never report success and must never call a write tool.
void main() {
  LiveTestWidgetsFlutterBinding();
  late Directory root;
  final planners = <MuyonHost, (PersonalAgent, ToolRegistry)>{};
  setUp(() {
    root = Directory.systemTemp.createTempSync('hk2-confirm-');
  });
  tearDown(() {
    root.deleteSync(recursive: true);
  });

  Future<void> close(WidgetTester tester, MuyonHost host) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    final planner = planners.remove(host)!;
    await tester.runAsync(() async {
      await planner.$1.close();
      await planner.$2.close();
      await host.close();
    });
  }

  Future<(MuyonHost, ValidatedUiPlan, String)> open(
    WidgetTester tester, {
    UiPresentationMode mode = UiPresentationMode.automatic,
    bool installPlan = true,
  }) async {
    final (host, taskId) = (await tester.runAsync(() async {
      final h = await MuyonHost.open(root.path);
      // Freeze the real host request after committing the presentation choice.
      // A legacy boolean toggle cannot grant content eligibility to a task.
      await h.personalAgent.savePresentationMode(mode);
      final conversation = await h.foundation.createConversation();
      final task = await h.personalAgent.start(
        conversationId: conversation.id,
        prompt: 'Show fixture confirmation',
        scope: const AssistantScope.global(),
      );
      // Task taint is clean, so external-content warnings cannot explain the
      // missing-business-port outcome under test.
      expect(
        h.foundation.authorizationFacts.readTask(task.id).requiresConfirmation,
        isFalse,
      );
      return (h, task.id);
    }))!;
    final base = actionPlan();
    final p = base.plan.copyWith(
      nodes: [
        for (final n in base.plan.nodes)
          if (n.id == 'confirm') n.copyWith(component: 'ConfirmCard') else n,
      ],
    );
    final checked = validateUiPlan(
      p,
      base.snapshot,
      base.intent,
      dynamicUiCatalog,
    );
    expect(checked.isValid, isTrue, reason: '${checked.errors}');
    // Keep the actual host repository, policy, grants and SQLite receipts.
    // A separate registry avoids duplicate registration of host-ui-planning.
    final hostTools = host.tools;
    final tools = ToolRegistry(
      database: hostTools.database,
      resolveScope: hostTools.resolveScope,
      clock: hostTools.clock,
      grants: hostTools.grants,
      grantContext: hostTools.grantContext,
      categoryAllowed: hostTools.categoryAllowed,
      policyRevision: hostTools.policyRevision,
      hostToolScopeResolver: hostTools.hostToolScopeResolver,
    );
    final agent = PersonalAgent(
      repository: host.foundation,
      gateway: host.services.gateway,
      tools: tools,
      executionDeviceId: host.personalAgent.executionDeviceId,
      gate: host.personalAgent.gate,
      modelAuthorization: host.personalAgent.modelAuthorization,
      toolReviewer: host.personalAgent.toolReviewer,
      presentationPreference: UiPresentationPreference(host.foundation),
      uiPlanningSource: (_) async => !installPlan
          ? null
          : UiPlanningHostState(
              snapshot: base.snapshot,
              intent: base.intent,
              catalog: dynamicUiCatalog,
              allowedActionRefs: base.intent.allowedActionRefs,
              currentView: UiCurrentView(
                surfaceId: p.surfaceId,
                revision: p.revision - 1,
              ),
            ),
      uiPlanningProviders: {
        UiPlanningMode.intelligent: FixtureUiPlanningProvider(
          (_) async => UiPlanningResult(
            decision: UiDisplayDecision.supplement,
            reasonCode: 'fixture',
            plan: p,
          ),
        ),
      },
    );
    planners[host] = (agent, tools);
    addTearDown(() async {
      if (planners.containsKey(host)) {
        await close(tester, host);
      }
    });
    final presentation = (await tester.runAsync(() async {
      final task = host.foundation.task(taskId)!;
      await host.foundation.updateTask(
        task.copy({'summary': 'Original answer'}),
      );
      return agent.planUiFromUserControl(taskId);
    }))!;
    expect(agent.presentationMode, mode);
    if (mode != UiPresentationMode.textOnly && installPlan) {
      expect(presentation.validated, isNotNull);
      expect(presentation.request!.taskId, taskId);
      expect(agent.isCurrentUiRequest(presentation.request!), isTrue);
      expect(agent.uiPresentation(taskId), same(presentation));
      expect(
        agent.uiPresentation(taskId)!.validated,
        same(presentation.validated),
      );
      return (host, presentation.validated!, taskId);
    }
    expect(presentation.validated, isNull);
    expect(agent.uiPresentation(taskId), isNull);
    return (host, checked.validatedPlan!, taskId);
  }

  Future<void> openWorkspace(
    WidgetTester tester,
    MuyonHost host,
    ValidatedUiPlan plan,
    String taskId, {
    UiEventSink? onEvent,
  }) async {
    // NO businessActions: the router maps nothing for the confirm action.
    await tester.pumpWidget(
      MaterialApp(
        home: DynamicWorkspace(
          key: UniqueKey(),
          repository: host.foundation,
          host: host,
          agent: planners[host]!.$1,
          taskId: taskId,
          onEvent: onEvent,
          surfaceId: plan.plan.surfaceId,
          plan: plan,
          originalAnswer: 'Original answer',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The event port is async (sqlite-backed); let it finish outside fake time.
  Future<void> confirm(WidgetTester tester) async {
    expect(find.byType(ConfirmCard), findsOneWidget);
    await tester.ensureVisible(find.text('仅这一次'));
    await tester.tap(find.text('仅这一次'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  const portError = 'Event port unavailable. Original answer retained.';

  testWidgets('unbound old manual plan cannot acquire current host ownership', (
    tester,
  ) async {
    final (host, plan, taskId) = await open(tester, installPlan: false);
    final agent = planners[host]!.$1;
    expect(agent.presentationMode, UiPresentationMode.automatic);
    expect(agent.allowsUiContent(taskId), isTrue);
    expect(agent.uiPresentation(taskId), isNull);
    final history = host.tools.history().length;
    final events = <UiEvent>[];
    await openWorkspace(
      tester,
      host,
      plan,
      taskId,
      onEvent: (event) async => events.add(event),
    );
    expect(find.byType(DynamicUiSurface), findsNothing);
    expect(find.byType(ConfirmCard), findsNothing);
    expect(find.text('仅这一次'), findsNothing);
    expect(find.text('Original answer'), findsOneWidget);
    expect(find.text('已成功'), findsNothing);
    expect(events, isEmpty);
    expect(host.tools.history().length, history);
    await close(tester, host);
  });

  testWidgets(
    'confirm_with_planning_enabled_reports_business_port_unavailable',
    (tester) async {
      final (host, plan, taskId) = await open(tester);
      expect(host.personalAgent.presentationMode, UiPresentationMode.automatic);
      expect(host.personalAgent.uiPlanningEnabled, isTrue);
      expect(host.personalAgent.allowsUiContent(taskId), isTrue);
      final history = host.tools.history().length;
      await openWorkspace(tester, host, plan, taskId);
      await confirm(tester);
      expect(find.text(portError), findsOneWidget);
      expect(find.text('已成功'), findsNothing);
      expect(find.text('进行中'), findsOneWidget);
      expect(host.tools.history().length, history);
      await close(tester, host);
    },
  );

  testWidgets('text_only_hides_optional_confirm_without_callbacks_or_calls', (
    tester,
  ) async {
    final (host, plan, taskId) = await open(
      tester,
      mode: UiPresentationMode.textOnly,
    );
    host.personalAgent.configureUiPlanning(enabled: true);
    expect(host.personalAgent.presentationMode, UiPresentationMode.textOnly);
    expect(host.personalAgent.uiPlanningEnabled, isFalse);
    expect(host.personalAgent.allowsUiContent(taskId), isFalse);
    final history = host.tools.history().length;
    final events = <UiEvent>[];
    await openWorkspace(
      tester,
      host,
      plan,
      taskId,
      onEvent: (event) async => events.add(event),
    );
    expect(find.byType(DynamicUiSurface), findsNothing);
    expect(find.byType(ConfirmCard), findsNothing);
    expect(find.text('仅这一次'), findsNothing);
    expect(find.text('Original answer'), findsOneWidget);
    expect(find.text('已成功'), findsNothing);
    expect(events, isEmpty);
    expect(host.tools.history().length, history);
    await close(tester, host);
  });

  testWidgets('confirm_card_without_receipt_stays_pending', (tester) async {
    final (host, plan, taskId) = await open(tester);
    expect(host.personalAgent.allowsUiContent(taskId), isTrue);
    final history = host.tools.history().length;
    await openWorkspace(tester, host, plan, taskId);
    await confirm(tester);
    // No acceptReceipt was called: the card must remain waiting for a host
    // receipt and must not turn into a success on its own.
    expect(
      find.text('Request pending: waiting for host receipt.'),
      findsOneWidget,
    );
    expect(find.text('已成功'), findsNothing);
    expect(find.textContaining('succeeded'), findsNothing);
    expect(find.text(portError), findsOneWidget);
    expect(find.text('进行中'), findsOneWidget);
    expect(host.tools.history().length, history);
    await close(tester, host);
  });
}
