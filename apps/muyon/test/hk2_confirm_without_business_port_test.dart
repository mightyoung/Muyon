import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
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
  setUp(() {
    root = Directory.systemTemp.createTempSync('hk2-confirm-');
  });
  tearDown(() {
    root.deleteSync(recursive: true);
  });

  // Same task-row shape as SN-1 (`sn1_dynamic_confirm_external_test.dart`),
  // plus the `state` key that PersonalTask parsing needs on host close.
  Future<(MuyonHost, ValidatedUiPlan)> open(WidgetTester tester) async {
    final host = (await tester.runAsync(() async {
      final h = await MuyonHost.open(root.path);
      final conversation = await h.foundation.createConversation();
      await h.foundation.database.write(
        (db) => db.execute('INSERT INTO execution_records VALUES(?,?,?)', [
          'task',
          'paused',
          jsonEncode({
            'kind': 'personal',
            'state': 'paused',
            'executionId': 'task',
            'conversationId': conversation.id,
            'scope': const AssistantScope.global().toJson(),
          }),
        ]),
      );
      // Task taint is `clean`, so external-content warnings cannot explain
      // the outcome under test.
      await h.foundation.database.write(
        (db) => db.execute('INSERT INTO settings(key,value) VALUES(?,?)', [
          'auth1b:task:task',
          jsonEncode({
            'version': 1,
            'taskId': 'task',
            'conversationId': conversation.id,
            'taintState': 'clean',
            'sourceDigests': <String>[],
          }),
        ]),
      );
      return h;
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
    return (host, checked.validatedPlan!);
  }

  Future<void> openWorkspace(
    WidgetTester tester,
    MuyonHost host,
    ValidatedUiPlan plan,
  ) async {
    // NO businessActions: the router maps nothing for the confirm action.
    await tester.pumpWidget(
      MaterialApp(
        home: DynamicWorkspace(
          key: UniqueKey(),
          repository: host.foundation,
          host: host,
          agent: host.personalAgent,
          taskId: 'task',
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

  Future<void> close(WidgetTester tester, MuyonHost host) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.runAsync(host.close);
  }

  const portError = 'Event port unavailable. Original answer retained.';

  testWidgets(
    'confirm_with_planning_enabled_reports_business_port_unavailable',
    (tester) async {
      final (host, plan) = await open(tester);
      // The same switch the assistant page exposes (`assistant_page.dart:604`).
      host.personalAgent.configureUiPlanning(enabled: true);
      expect(host.personalAgent.uiPlanningEnabled, isTrue);
      final history = host.tools.history().length;
      await openWorkspace(tester, host, plan);
      await confirm(tester);
      expect(find.text(portError), findsOneWidget);
      expect(find.text('已成功'), findsNothing);
      expect(find.text('进行中'), findsOneWidget);
      expect(host.tools.history().length, history);
      await close(tester, host);
    },
  );

  testWidgets('confirm_with_planning_disabled_stays_pending_without_calls', (
    tester,
  ) async {
    final (host, plan) = await open(tester);
    expect(host.personalAgent.uiPlanningEnabled, isFalse);
    final history = host.tools.history().length;
    await openWorkspace(tester, host, plan);
    await confirm(tester);
    expect(find.text('已成功'), findsNothing);
    // Observed: the operation is locked as in-progress and the failure hint
    // shows; the planning gate throws before any port or tool is reached.
    expect(find.text(portError), findsOneWidget);
    expect(find.text('进行中'), findsOneWidget);
    expect(host.tools.history().length, history);
    await close(tester, host);
  });

  testWidgets('confirm_card_without_receipt_stays_pending', (tester) async {
    final (host, plan) = await open(tester);
    host.personalAgent.configureUiPlanning(enabled: true);
    await openWorkspace(tester, host, plan);
    await confirm(tester);
    // No acceptReceipt was called: the card must remain waiting for a host
    // receipt and must not turn into a success on its own.
    expect(
      find.text('Request pending: waiting for host receipt.'),
      findsOneWidget,
    );
    expect(find.text('已成功'), findsNothing);
    expect(find.textContaining('succeeded'), findsNothing);
    await close(tester, host);
  });
}
