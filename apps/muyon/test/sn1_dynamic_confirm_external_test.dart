import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/screens/dynamic_workspace.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart' show AssistantScope;
import 'package:muyon_module_api/ui_contract.dart';
import 'package:muyon_ui/dynamic_ui.dart';
import 'package:muyon_ui/muyon_ui.dart';

import '../../../packages/muyon_ui/test/dynamic_fixtures.dart';

/// SN-1: the dynamic confirm cards take "external content" only from the host
/// taint state of the owning task, and fail closed on anything but `clean`.
void main() {
  LiveTestWidgetsFlutterBinding();
  late Directory root;
  late StorageManager storage;
  late FoundationRepository repo;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('sn1-confirm-');
    storage = StorageManager(root.path);
    repo = FoundationRepository(
      await storage.open('muyon', WorkspaceRepository.schema),
    );
    await repo.database.write(
      (db) => db.execute('INSERT INTO execution_records VALUES(?,?,?)', [
        'task',
        'paused',
        jsonEncode({
          'kind': 'personal',
          'executionId': 'task',
          'scope': AssistantScope.workspace('w1').toJson(),
        }),
      ]),
    );
  });
  tearDown(() async {
    await storage.close();
    root.deleteSync(recursive: true);
  });

  Future<void> setTaint(String? state) async {
    if (state == null) return; // no host fact row at all: lookup finds nothing
    await repo.database.write(
      (db) => db.execute('INSERT INTO settings(key,value) VALUES(?,?)', [
        'auth1b:task:task',
        jsonEncode({
          'version': 1,
          'taskId': 'task',
          'conversationId': 'c1',
          'taintState': state,
          'sourceDigests': <String>[],
        }),
      ]),
    );
  }

  // [forged] plants "externalContent: false" in the snapshot's UI state.
  ValidatedUiPlan plan({required bool batch, bool forged = false}) {
    final base = actionPlan();
    final p = base.plan.copyWith(
      nodes: [
        for (final n in base.plan.nodes)
          if (n.id == 'confirm')
            n.copyWith(component: batch ? 'BatchConfirmCard' : 'ConfirmCard')
          else
            n,
      ],
    );
    final b = base.snapshot;
    final snapshot = DataSnapshot(
      ref: b.ref,
      facts: b.facts,
      initialUiState: {
        ...b.initialUiState,
        if (forged) 'externalContent': false,
      },
      computations: b.computations,
      sources: b.sources,
      sourceDigests: b.sourceDigests,
      actionContext: b.actionContext,
    );
    final checked = validateUiPlan(p, snapshot, base.intent, dynamicUiCatalog);
    expect(checked.isValid, isTrue, reason: '${checked.errors}');
    return checked.validatedPlan!;
  }

  Future<void> open(WidgetTester tester, ValidatedUiPlan p) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DynamicWorkspace(
          key: UniqueKey(),
          repository: repo,
          taskId: 'task',
          surfaceId: p.plan.surfaceId,
          plan: p,
          originalAnswer: 'Original answer',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final warn = find.descendant(
    of: find.byType(ConfirmCard),
    matching: find.byType(WarnBanner),
  );

  for (final state in <String?>['tainted', 'unknown', null]) {
    final name = state ?? 'missing';
    testWidgets('confirm_card_shows_external_warning_when_taint_is_$name', (
      tester,
    ) async {
      await setTaint(state);
      await open(tester, plan(batch: false));
      expect(find.byType(ConfirmCard), findsOneWidget);
      expect(
        tester.widget<ConfirmCard>(find.byType(ConfirmCard)).externalContent,
        isTrue,
      );
      expect(warn, findsOneWidget);
    });
    testWidgets('batch_card_has_no_allow_all_when_taint_is_$name', (
      tester,
    ) async {
      await setTaint(state);
      await open(tester, plan(batch: true));
      expect(find.byType(BatchConfirmCard), findsOneWidget);
      expect(find.text('全部允许'), findsNothing);
      expect(find.text('逐项决定'), findsOneWidget);
    });
  }

  testWidgets('clean_task_keeps_current_behaviour', (tester) async {
    await setTaint('clean');
    await open(tester, plan(batch: false));
    expect(
      tester.widget<ConfirmCard>(find.byType(ConfirmCard)).externalContent,
      isFalse,
    );
    expect(warn, findsNothing);
    await open(tester, plan(batch: true));
    expect(find.text('全部允许'), findsOneWidget);
  });

  test('plan_node_cannot_carry_an_external_content_flag', () {
    final base = actionPlan();
    final p = base.plan.copyWith(
      nodes: [
        for (final n in base.plan.nodes)
          if (n.id == 'confirm')
            n.copyWith(properties: {...n.properties, 'externalContent': false})
          else
            n,
      ],
    );
    final r = validateUiPlan(p, base.snapshot, base.intent, dynamicUiCatalog);
    expect(r.isValid, isFalse);
  });

  testWidgets('forged_ui_state_flag_cannot_clean_a_tainted_task', (
    tester,
  ) async {
    await setTaint('tainted');
    await open(tester, plan(batch: false, forged: true));
    expect(
      tester.widget<ConfirmCard>(find.byType(ConfirmCard)).externalContent,
      isTrue,
    );
    expect(warn, findsOneWidget);
    await open(tester, plan(batch: true, forged: true));
    expect(find.text('全部允许'), findsNothing);
  });
}
