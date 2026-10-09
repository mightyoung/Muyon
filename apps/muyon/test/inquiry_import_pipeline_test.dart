import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart';
import 'package:muyon/workspace/import_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:muyon/app/import_review_projection.dart';
import 'package:muyon/screens/inquiry_import_context.dart';
import 'package:muyon/screens/platform_shell.dart';
import 'package:muyon/app/adapters/inquiry_module.dart';
import 'package:muyon_ui/dynamic_ui.dart';

void main() {
  LiveTestWidgetsFlutterBinding();
  testWidgets('task_center_menu_opens_production_file_context', (tester) async {
    final f = await _Fixture.open();
    try {
      await f.addTask();
      await tester.pumpWidget(
        MaterialApp(
          home: PlatformShell(
            host: f.host,
            themeMode: ThemeMode.light,
            onTheme: (_) {},
            onRestore: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final navigation = find.byType(NavigationBar).evaluate().isNotEmpty
          ? find.byType(NavigationBar) : find.byType(NavigationRail);
      await tester.tap(find.descendant(of: navigation, matching: find.text('任务')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('从文件导入业务'));
      await tester.pumpAndSettle();
      expect(find.byType(InquiryImportContextPage), findsOneWidget);
      expect(find.byKey(const ValueKey('import-plugin')), findsOneWidget);
      expect(f.quotationCount, 0);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    } finally {
      await f.close();
    }
  });
  testWidgets(
    'production_context_entry_reaches_real_review_and_resumes_without_parse',
    (tester) async {
      final f = await _Fixture.open();
      try {
        await f.addTask();
        final file = File('${f.root.path}/context.txt')
          ..writeAsStringSync('供应商\t产品名称\t型号\t单位\t单价\n公开供应商\t水泵\tM2\t台\t10');
        var picks = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InquiryImportContextPage(
                host: f.host,
                taskId: 'task',
                pickInput: () async {
                  picks++;
                  return SelectedInput(
                    path: file.path,
                    displayName: 'context.txt',
                  );
                },
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('import-plugin')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('询价').last);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            ValueKey('import-project-${f.target.binding.workspaceId}'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('公开项目').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('选择本地文件'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('进入用途选择'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('询价报价'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('准备预览'));
        await tester.pumpAndSettle();
        expect(f.quotationCount, 0);
        await tester.tap(find.byKey(const ValueKey('select-r0')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认导入'));
        await tester.pumpAndSettle();
        expect(f.quotationCount, 1);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('继续导入草稿').first);
        await tester.pumpAndSettle();
        expect(find.textContaining('已入库'), findsWidgets);
        expect(f.quotationCount, 1);
        expect(picks, 1);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      } finally {
        await f.close();
      }
    },
  );
  for (final committed in [false, true]) {
    testWidgets(
      'receipt_query_never_reexecutes_unknown_or_committed_$committed',
      (tester) async {
        final f = await _Fixture.open();
        UiWorkspaceController? controller;
        try {
          await f.addTask();
          final draft = await f.prepare();
          final projection = ImportReviewProjection(
            f.host,
            f.runtime as InquiryModuleRuntime,
            draft,
            taskId: 'task',
          );
          controller = await projection.open();
          final prepared = await draft.confirm(['r0']);
          final coordinator = ImportCoordinator(f.host.workspaces);
          final intent = await coordinator.record(prepared);
          controller.surface.lockRecoveredOperations([intent.operationId]);
          await controller.flush();
          if (committed) await f.runtime.commitImport(prepared, intent);
          final before = f.quotationCount;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ImportReviewView(
                  projection: projection,
                  controller: controller,
                ),
              ),
            ),
          );
          await tester.tap(find.text('查询提交回执'));
          await tester.pumpAndSettle();
          expect(f.quotationCount, before);
          expect(coordinator.pending('inquiry').length, committed ? 0 : 1);
          expect(
            find.textContaining(committed ? '已入库' : '回执尚未确认'),
            findsWidgets,
          );
          await tester.pumpWidget(const SizedBox());
          expect(tester.takeException(), isNull);
        } finally {
          controller?.dispose();
          await f.close();
        }
      },
    );
  }
  testWidgets('entry_requires_function_and_exposes_candidate_choice', (
    tester,
  ) async {
    final f = await _Fixture.open();
    try {
      await f.addTask();
      f.host.inquiry!.runtime.state.store.save('product', {
        for (final field in Product.fields) field: null,
        'name': '水泵',
        'unit': '台',
        'model': 'M1',
      });
      final file = File('${f.root.path}/entry.txt')
        ..writeAsStringSync('供应商\t产品名称\t型号\t单位\t单价\n公开供应商\t水泵\tM2\t台\t10');
      await tester.pumpWidget(
        MaterialApp(
          home: InquiryImportEntry(
            host: f.host,
            taskId: 'task',
            input: SelectedInput(path: file.path, displayName: 'entry.txt'),
            target: f.target,
          ),
        ),
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '准备预览'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('询价报价'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('准备预览'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择重复关系'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('product-choice-r0')), findsOneWidget);
      expect(f.quotationCount, 0);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    } finally {
      await f.close();
    }
  });
  test('queued_commit_rechecks_project_owner_inside_final_write', () async {
    final f = await _Fixture.open();
    final entered = Completer<void>(), release = Completer<void>();
    Future<String?>? blocker;
    try {
      final draft = await f.prepare();
      final prepared = await draft.confirm(['r0']);
      final coordinator = ImportCoordinator(f.host.workspaces);
      final intent = await coordinator.record(prepared);
      final other = await f.host.workspaces.create('其他工作区');
      blocker = f.host.inquiry!.runtime.state.writeInBackground((_) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final commit = f.runtime.commitImport(prepared, intent);
      await f.host.workspaces.bind(
        WorkspaceBinding(
          workspaceId: other.id,
          moduleId: 'inquiry',
          nativeProjectId: f.project,
        ),
      );
      release.complete();
      await blocker;
      await expectLater(commit, throwsStateError);
      expect(f.quotationCount, 0);
      expect(await f.runtime.receipt(intent.operationId), isNull);
      expect(
        coordinator.pending('inquiry').single.operationId,
        intent.operationId,
      );
    } finally {
      if (!release.isCompleted) release.complete();
      await blocker;
      await f.close();
    }
  });
  test(
    'project_owner_change_is_refused_before_intent_or_domain_write',
    () async {
      final f = await _Fixture.open();
      UiWorkspaceController? controller;
      try {
        await f.addTask();
        final draft = await f.prepare();
        final projection = ImportReviewProjection(
          f.host,
          f.runtime as InquiryModuleRuntime,
          draft,
          taskId: 'task',
        );
        controller = await projection.open();
        final other = await f.host.workspaces.create('其他工作区');
        await f.host.workspaces.bind(
          WorkspaceBinding(
            workspaceId: other.id,
            moduleId: 'inquiry',
            nativeProjectId: f.target.binding.nativeProjectId,
          ),
        );
        await expectLater(
          projection.commitSelected(controller, ['r0']),
          throwsStateError,
        );
        expect(f.quotationCount, 0);
        expect(
          ImportCoordinator(f.host.workspaces).pending('inquiry'),
          isEmpty,
        );
      } finally {
        controller?.dispose();
        await f.close();
      }
    },
  );
  testWidgets('context_project_selector_excludes_another_workspace_owner', (
    tester,
  ) async {
    final f = await _Fixture.open();
    try {
      await f.addTask();
      final other = await f.host.workspaces.create('其他工作区');
      await f.host.workspaces.bind(
        WorkspaceBinding(
          workspaceId: other.id,
          moduleId: 'inquiry',
          nativeProjectId: f.target.binding.nativeProjectId,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InquiryImportContextPage(host: f.host, taskId: 'task'),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('import-plugin')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('询价').last);
      await tester.pumpAndSettle();
      final dropdown = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byKey(
            ValueKey('import-project-${f.target.binding.workspaceId}'),
          ),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(
        dropdown.items!.where(
          (i) => i.value == f.target.binding.nativeProjectId,
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    } finally {
      await f.close();
    }
  });
  test('batch_duplicate_receipt_reports_actual_effects', () async {
    final f = await _Fixture.open();
    try {
      final file = File('${f.root.path}/duplicates.txt')
        ..writeAsStringSync(
          '供应商\t产品名称\t型号\t单位\t单价\n公开供应商\t水泵\tM2\t台\t10\n公开供应商\t水泵\tM2\t台\t10',
        );
      final draft = await f.runtime.prepareImport(
        SelectedInquiryInput(
          path: file.path,
          displayName: 'duplicates.txt',
          purpose: InquiryImportPurpose.quotations,
        ),
        f.target,
      ) as PreparedInquiryDraft;
      final prepared = await draft.confirm(['r0', 'r1']);
      final c = ImportCoordinator(f.host.workspaces);
      final receipt = await c.commit(
        f.runtime,
        prepared,
        await c.record(prepared),
      );
      expect(f.quotationCount, 1);
      expect(receipt.result['succeededRecordIds'], ['r0']);
      expect(receipt.result['skippedRecordIds'], ['r1']);
      expect((receipt.result['summary'] as Map)['duplicates'], 1);
      expect((receipt.result['records'] as Map)['r1']['status'], 'skipped');
      expect(draft.records.last.status, InquiryRecordStatus.duplicate);
    } finally {
      await f.close();
    }
  });
  test('failed_submission_can_retry_the_original_pending_operation', () async {
    final f = await _Fixture.open();
    UiWorkspaceController? controller;
    try {
      await f.addTask();
      final draft = await f.prepare();
      final projection = ImportReviewProjection(
        f.host,
        f.runtime as InquiryModuleRuntime,
        draft,
        taskId: 'task',
      );
      controller = await projection.open();
      final db = f.host.inquiry!.runtime.state.store.db;
      db.execute(
        "CREATE TRIGGER fail_import_receipt BEFORE INSERT ON meta WHEN new.key LIKE 'inquiry-import:receipt:%' BEGIN SELECT RAISE(ABORT,'fixture receipt failure'); END",
      );
      await expectLater(
        projection.commitSelected(controller, ['r0']),
        throwsA(anything),
      );
      final pending = ImportCoordinator(f.host.workspaces)
          .pending('inquiry')
          .single;
      expect(await f.runtime.receipt(pending.operationId), isNull);
      expect(f.quotationCount, 0);
      db.execute('DROP TRIGGER fail_import_receipt');
      final receipt = await projection.commitSelected(controller, ['r0']);
      expect(receipt.operationId, pending.operationId);
      expect(f.quotationCount, 1);
    } finally {
      controller?.dispose();
      await f.close();
    }
  });
  test('candidate_change_before_confirmation_requires_new_choice', () async {
    final f = await _Fixture.open();
    try {
      final store = f.host.inquiry!.runtime.state.store;
      final product = store.save('product', {
        for (final field in Product.fields) field: null,
        'name': '水泵',
        'unit': '台',
        'model': 'M1',
      });
      final draft = await f.prepare();
      await draft.choose('r0', productId: product);
      store.save('product', {
        ...store.get('product', product)!.data,
        'model': 'changed',
      }, id: product);
      expect(draft.records.single.status, InquiryRecordStatus.conflict);
      await expectLater(draft.confirm(['r0']), throwsStateError);
      expect(f.quotationCount, 0);
    } finally {
      await f.close();
    }
  });
  test('unsupported_html_and_image_refuse_without_domain_effect', () async {
    final f = await _Fixture.open();
    try {
      for (final extension in ['html', 'png']) {
        final file = File('${f.root.path}/unsupported.$extension')
          ..writeAsStringSync('public fixture');
        await expectLater(
          f.runtime.prepareImport(
            SelectedInquiryInput(
              path: file.path,
              displayName: 'unsupported.$extension',
              purpose: InquiryImportPurpose.quotations,
            ),
            f.target,
          ),
          throwsStateError,
        );
        expect(f.quotationCount, 0);
        expect(
          ImportCoordinator(f.host.workspaces).pending('inquiry'),
          isEmpty,
        );
      }
    } finally {
      await f.close();
    }
  });
  test('materials_category_table_reuses_existing_parser_without_ai', () async {
    final f = await _Fixture.open();
    try {
      final file = File('${f.root.path}/materials.md')
        ..writeAsStringSync('产品名称\t类别\t单位\n公开泵件\t设备\t台');
      final draft = await f.runtime.prepareImport(
        SelectedInquiryInput(
          path: file.path,
          displayName: 'materials.md',
          purpose: InquiryImportPurpose.materials,
        ),
        f.target,
      ) as PreparedInquiryDraft;
      final row = f.host.inquiry!.runtime.state.store.db.select(
        'SELECT value FROM meta WHERE key=?',
        ['inquiry-import:draft:${draft.draftId}'],
      ).single;
      expect((jsonDecode(row['value'] as String) as Map)['aiTaskId'], isNull);
      final prepared = await draft.confirm(['r0']);
      final c = ImportCoordinator(f.host.workspaces);
      final receipt = await c.commit(
        f.runtime,
        prepared,
        await c.record(prepared),
      );
      expect((receipt.result['summary'] as Map)['products'], 1);
      expect(f.quotationCount, 0);
      expect(
        (receipt.result['records'] as Map)['r0']['businessObjectId'],
        isNotEmpty,
      );
    } finally {
      await f.close();
    }
  });
  test(
    'mixed_materials_first_can_parse_original_quote_schema_without_ai',
    () async {
      final f = await _Fixture.open();
      try {
        final file = File('${f.root.path}/mixed-first.txt')
          ..writeAsStringSync('供应商\t产品名称\t单位\t单价\n公开供应商\t公开泵件\t台\t10');
        final draft = await f.runtime.prepareImport(
          SelectedInquiryInput(
            path: file.path,
            displayName: 'mixed-first.txt',
            purpose: InquiryImportPurpose.materials,
            additionalPurposes: {InquiryImportPurpose.quotations},
          ),
          f.target,
        ) as PreparedInquiryDraft;
        await draft.assignPurpose('r0', InquiryImportPurpose.quotations);
        final prepared = await draft.confirm(['r0']);
        final c = ImportCoordinator(f.host.workspaces);
        final receipt = await c.commit(
          f.runtime,
          prepared,
          await c.record(prepared),
        );
        expect((receipt.result['summary'] as Map)['quotations'], 1);
        expect(f.quotationCount, 1);
      } finally {
        await f.close();
      }
    },
  );
  test('large_import_review_stays_inside_shared_renderer_node_limit', () async {
    final f = await _Fixture.open();
    UiWorkspaceController? controller;
    try {
      await f.addTask();
      final file = File('${f.root.path}/many.txt')
        ..writeAsStringSync(
          '供应商\t产品名称\t型号\t单位\t单价\n${List.generate(12, (i) => '公开供应商\t公开设备$i\tM$i\t台\t10').join('\n')}',
        );
      final draft = await f.runtime.prepareImport(
        SelectedInquiryInput(
          path: file.path,
          displayName: 'many.txt',
          purpose: InquiryImportPurpose.quotations,
        ),
        f.target,
      ) as PreparedInquiryDraft;
      final projection = ImportReviewProjection(
        f.host,
        f.runtime as InquiryModuleRuntime,
        draft,
        taskId: 'task',
      );
      controller = await projection.open();
      expect(
        controller.surface.current.plan.nodes.length,
        lessThanOrEqualTo(200),
      );
      expect(draft.recordIds, hasLength(12));
    } finally {
      controller?.dispose();
      await f.close();
    }
  });
  test('skipped_record_status_is_restored_from_the_real_receipt', () async {
    final f = await _Fixture.open();
    try {
      final draft = await f.prepare();
      final store = f.host.inquiry!.runtime.state.store;
      final duplicate = draft.records.single.plan.offer;
      store.applyOffers(
        [(offer: duplicate, supplierId: null, productId: null)],
        projectId: f.project,
        inquirer: '-',
      );
      final file = File('${f.root.path}/two.txt')
        ..writeAsStringSync(
          '供应商\t产品名称\t型号\t单位\t单价\n公开供应商\t水泵\tM2\t台\t10\n公开供应商\t电缆\tC2\t米\t12',
        );
      final two = await f.runtime.prepareImport(
        SelectedInquiryInput(
          path: file.path,
          displayName: 'two.txt',
          purpose: InquiryImportPurpose.quotations,
        ),
        f.target,
      ) as PreparedInquiryDraft;
      final prepared = await two.confirm(['r1']);
      final coordinator = ImportCoordinator(f.host.workspaces);
      final intent = await coordinator.record(prepared);
      await coordinator.commit(f.runtime, prepared, intent);
      final resumed = await (f.runtime as InquiryModuleRuntime).resumeImport(
        two.draftId,
      );
      expect(resumed.records.first.status, InquiryRecordStatus.duplicate);
      expect(resumed.records.first.receiptRef, intent.operationId);
    } finally {
      await f.close();
    }
  });
  testWidgets(
    'human_review_click_confirms_the_selected_record_and_real_receipt',
    (tester) async {
      final f = await _Fixture.open();
      UiWorkspaceController? controller;
      try {
        await f.addTask();
        final draft = await f.prepare();
        final projection = ImportReviewProjection(
          f.host,
          f.runtime as InquiryModuleRuntime,
          draft,
          taskId: 'task',
        );
        controller = await projection.open();
        await tester.pumpWidget(
          MaterialApp(
            home: ImportReviewView(
              projection: projection,
              controller: controller,
            ),
          ),
        );
        expect(find.text('确认导入'), findsOneWidget);
        expect(f.quotationCount, 0);
        await tester.tap(find.byKey(const ValueKey('select-r0')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认导入'));
        await tester.pumpAndSettle();
        expect(f.quotationCount, 1);
        expect(find.textContaining('已入库 1'), findsOneWidget);
        expect(draft.records.single.receiptRef, isNotNull);
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      } finally {
        controller?.dispose();
        await f.close();
      }
    },
  );
  test('same_frozen_confirmation_retry_has_one_effect_and_changed_input_is_refused', () async {
    final f = await _Fixture.open();
    try {
      final draft = await f.prepare();
      final prepared = await draft.confirm(['r0']);
      final coordinator = ImportCoordinator(f.host.workspaces);
      final intent = await coordinator.record(prepared);
      final same = await coordinator.record(
        prepared,
        operationId: intent.operationId,
      );
      expect(same.sameIdentity(intent), isTrue);
      final results = await Future.wait([
        f.runtime.commitImport(prepared, intent),
        f.runtime.commitImport(prepared, same),
      ]);
      expect(results[0].result, results[1].result);
      expect(f.quotationCount, 1);
      final changed = PreparedImport(
        target: prepared.target,
        inputDigest: 'changed selection',
        stagingToken: prepared.stagingToken,
      );
      await expectLater(
        f.runtime.commitImport(changed, intent),
        throwsStateError,
      );
      final other = ImportIntent(
        operationId: 'same-draft-different-call',
        workspaceId: intent.workspaceId,
        moduleId: intent.moduleId,
        targetProjectId: intent.targetProjectId,
        kind: intent.kind,
        inputDigest: intent.inputDigest,
        stagingToken: intent.stagingToken,
      );
      await expectLater(
        f.runtime.commitImport(prepared, other),
        throwsStateError,
      );
      expect(await f.runtime.receipt(other.operationId), isNull);
      expect(f.quotationCount, 1);
    } finally {
      await f.close();
    }
  });
  test('restored_pending_ui_reference_reuses_coordinator_operation', () async {
    final f = await _Fixture.open();
    UiWorkspaceController? controller;
    try {
      await f.addTask();
      final draft = await f.prepare();
      final projection = ImportReviewProjection(
        f.host,
        f.runtime as InquiryModuleRuntime,
        draft,
        taskId: 'task',
      );
      final prepared = await draft.confirm(['r0']);
      final intent = await ImportCoordinator(f.host.workspaces)
          .record(prepared);
      controller = await projection.open();
      controller.surface.lockRecoveredOperations([intent.operationId]);
      controller.step = 'submitting';
      await controller.flush();
      controller.dispose();
      final restored = ImportReviewProjection(
        f.host,
        f.runtime as InquiryModuleRuntime,
        draft,
        taskId: 'task',
      );
      controller = await restored.open();
      expect(
        controller.recoveredOperations[intent.operationId],
        UiOperationRecovery.unknown,
      );
      final result = await restored.commitSelected(controller, ['r0']);
      expect(result.operationId, intent.operationId);
      expect(f.quotationCount, 1);
    } finally {
      controller?.dispose();
      await f.close();
    }
  });
  test('source_ai_apply_marker_and_domain_receipt_commit_atomically', () async {
    final f = await _Fixture.open();
    try {
      final draft = await f.prepare();
      final owner = f.host.inquiry!;
      final job = owner.jobs.create(AiTask.offerExtraction, {
        'source': 'public fixture',
      });
      owner.jobs.start(job.id).ready();
      final db = owner.runtime.state.store.db;
      final key = 'inquiry-import:draft:${draft.draftId}';
      final d = jsonDecode(
        db.select('SELECT value FROM meta WHERE key=?', [key]).single['value']
            as String,
      ) as Map;
      d['aiTaskId'] = job.id;
      db.execute('UPDATE meta SET value=? WHERE key=?', [jsonEncode(d), key]);
      final prepared = await draft.confirm(['r0']);
      final intent = await ImportCoordinator(f.host.workspaces)
          .record(prepared);
      db.execute(
        "CREATE TRIGGER fail_import_receipt BEFORE INSERT ON meta WHEN new.key LIKE 'inquiry-import:receipt:%' BEGIN SELECT RAISE(ABORT,'fixture receipt failure'); END",
      );
      await expectLater(
        f.runtime.commitImport(prepared, intent),
        throwsA(anything),
      );
      expect(f.quotationCount, 0);
      expect(await f.runtime.receipt(intent.operationId), isNull);
      expect(
        db.select('SELECT 1 FROM meta WHERE key=?', ['ai_applied:${job.id}']),
        isEmpty,
      );
      expect(owner.jobs.get(job.id).status, 'ready');
      db.execute('DROP TRIGGER fail_import_receipt');
      await f.runtime.commitImport(prepared, intent);
      expect(f.quotationCount, 1);
      expect(
        db.select('SELECT 1 FROM meta WHERE key=?', ['ai_applied:${job.id}']),
        hasLength(1),
      );
      expect(owner.jobs.get(job.id).status, 'finished');
    } finally {
      await f.close();
    }
  });
  test('shutdown_admission_refuses_import_commit', () async {
    final f = await _Fixture.open();
    try {
      final draft = await f.prepare();
      final prepared = await draft.confirm(['r0']);
      final intent = await ImportCoordinator(f.host.workspaces)
          .record(prepared);
      f.host.modules.stopAdmission();
      await expectLater(
        f.runtime.commitImport(prepared, intent),
        throwsStateError,
      );
      expect(f.quotationCount, 0);
    } finally {
      await f.close();
    }
  });
  test('mixed_selected_functions_use_their_existing_field_schema', () async {
    final f = await _Fixture.open();
    try {
      final file = File('${f.root.path}/mixed.md')
        ..writeAsStringSync(
          '供应商\t产品名称\t型号\t单位\t单价\n公开供应商\t水泵\tM2\t台\t10\n另一公开供应商\t电缆\tC2\t米\t30',
        );
      final draft = await f.runtime.prepareImport(
        SelectedInquiryInput(
          path: file.path,
          displayName: 'mixed.md',
          purpose: InquiryImportPurpose.quotations,
          additionalPurposes: {InquiryImportPurpose.materials},
        ),
        f.target,
      ) as PreparedInquiryDraft;
      await draft.assignPurpose('r1', InquiryImportPurpose.materials);
      expect(draft.records[1].plan.offer['supplier'], isNull);
      await expectLater(draft.edit('r1', 'price', '99'), throwsStateError);
      final confirmed = await draft.confirm(['r0', 'r1']);
      final coordinator = ImportCoordinator(f.host.workspaces);
      final intent = await coordinator.record(confirmed);
      final receipt = await coordinator.commit(f.runtime, confirmed, intent);
      expect(receipt.result['succeededRecordIds'], ['r0', 'r1']);
      expect(f.quotationCount, 1);
      expect(
        f.host.inquiry!.runtime.state.store.db
            .select('SELECT count(*) AS n FROM product')
            .single['n'],
        2,
      );
      expect(
        f.host.inquiry!.runtime.state.store.db
            .select('SELECT count(*) AS n FROM supplier')
            .single['n'],
        1,
      );
    } finally {
      await f.close();
    }
  });
  testWidgets('shared_review_edit_survives_return_and_commits_actual_value', (
    tester,
  ) async {
    final f = await _Fixture.open();
    UiWorkspaceController? controller;
    try {
      await f.host.foundation.database.write(
        (db) => db.execute('INSERT INTO execution_records VALUES(?,?,?)', [
          'task',
          'paused',
          jsonEncode({
            'kind': 'personal',
            'executionId': 'task',
            'state': 'interrupted',
            'stage': 'interrupted',
            'scope': AssistantScope.workspace(f.target.binding.workspaceId)
                .toJson(),
          }),
        ]),
      );
      final draft = await f.prepare();
      final projection = ImportReviewProjection(
        f.host,
        f.runtime as InquiryModuleRuntime,
        draft,
        taskId: 'task',
      );
      controller = await projection.open();
      await tester.pumpWidget(
        MaterialApp(
          home: UiWorkspaceView(
            controller: controller,
            originalAnswer: '实际文件导入',
          ),
        ),
      );
      final price = find.descendant(
        of: find.byKey(const ValueKey('r0:price-field')),
        matching: find.byType(TextField),
      );
      expect(price, findsOneWidget);
      final supplier = find.descendant(
        of: find.byKey(const ValueKey('r0:supplier-field')),
        matching: find.byType(TextField),
      );
      expect(
        tester.widget<TextField>(supplier).keyboardType,
        TextInputType.text,
      );
      await tester.ensureVisible(price);
      await tester.enterText(price, '12');
      await tester.pumpAndSettle();
      await controller.flush();
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      controller = await projection.open();
      await tester.pumpWidget(
        MaterialApp(
          home: UiWorkspaceView(
            controller: controller,
            originalAnswer: '实际文件导入',
          ),
        ),
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('r0:price-field')),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        '12',
      );
      final result = await projection.commitSelected(controller, ['r0']);
      expect(result.result['succeededRecordIds'], ['r0']);
      expect(
        f.host.inquiry!.runtime.state.store
            .listQuotations(projectId: f.project)
            .single
            .data['price'],
        '12',
      );
      expect(controller.surface.operationRefs, contains(result.operationId));
      await controller.flush();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    } finally {
      controller?.dispose();
      await f.close();
    }
  });
  test('clearing_a_field_keeps_the_human_override', () async {
    final f = await _Fixture.open();
    try {
      final draft = await f.prepare();
      await draft.edit('r0', 'unit', null);
      expect(draft.value('r0', 'unit'), isNull);
      expect(draft.records.single.status, InquiryRecordStatus.incomplete);
    } finally {
      await f.close();
    }
  });
  test('edited_confirmation_and_unconfirmed_payload_cannot_write', () async {
    final f = await _Fixture.open();
    try {
      final draft = await f.prepare();
      final confirmed = await draft.confirm(['r0']);
      final intent = await ImportCoordinator(f.host.workspaces)
          .record(confirmed);
      await draft.edit('r0', 'price', '12');
      await expectLater(
        f.runtime.commitImport(confirmed, intent),
        throwsStateError,
      );
      final fake = PreparedImport(
        target: draft.target,
        inputDigest: draft.inputDigest,
        stagingToken: draft.stagingToken,
      );
      final fakeIntent = ImportIntent(
        operationId: 'model-confirmed-true',
        workspaceId: fake.target.binding.workspaceId,
        moduleId: 'inquiry',
        targetProjectId: f.project,
        kind: fake.target.kind,
        inputDigest: fake.inputDigest,
        stagingToken: fake.stagingToken,
      );
      await expectLater(
        f.runtime.commitImport(fake, fakeIntent),
        throwsStateError,
      );
      expect(f.quotationCount, 0);
      expect(f.runtime, isNot(isA<ExchangeCapable>()));
    } finally {
      await f.close();
    }
  });
  test('source_or_schema_change_invalidates_confirmation', () async {
    for (final change in ['source', 'schema']) {
      final f = await _Fixture.open();
      try {
        final draft = await f.prepare();
        final confirmed = await draft.confirm(['r0']);
        final intent = await ImportCoordinator(f.host.workspaces)
            .record(confirmed);
        final db = f.host.inquiry!.runtime.state.store.db;
        final key = 'inquiry-import:draft:${draft.draftId}';
        final d = jsonDecode(
          db.select('SELECT value FROM meta WHERE key=?', [key]).single['value']
              as String,
        ) as Map;
        if (change == 'source') {
          File(d['path'] as String).writeAsStringSync('changed');
        } else {
          d['schemaDigest'] = 'a different field schema';
          db.execute('UPDATE meta SET value=? WHERE key=?', [
            jsonEncode(d),
            key,
          ]);
        }
        await expectLater(
          f.runtime.commitImport(confirmed, intent),
          throwsStateError,
        );
        expect(f.quotationCount, 0);
        expect(draft.value('r0', 'price'), '10');
      } finally {
        await f.close();
      }
    }
  });
  test(
    'chosen_existing_product_has_actual_receipt_and_stale_entity_is_refused',
    () async {
      for (final change in [false, true]) {
        final f = await _Fixture.open();
        try {
          final store = f.host.inquiry!.runtime.state.store;
          final product = store.save('product', {
            for (final field in Product.fields) field: null,
            'name': '水泵',
            'unit': '台',
            'model': 'M1',
          });
          final draft = await f.prepare();
          await draft.choose('r0', productId: product);
          final confirmed = await draft.confirm(['r0']);
          final coordinator = ImportCoordinator(f.host.workspaces);
          final intent = await coordinator.record(confirmed);
          if (change) {
            store.save('product', {
              ...store.get('product', product)!.data,
              'model': 'changed',
            }, id: product);
            await expectLater(
              coordinator.commit(f.runtime, confirmed, intent),
              throwsStateError,
            );
            expect(f.quotationCount, 0);
          } else {
            final receipt = await coordinator.commit(
              f.runtime,
              confirmed,
              intent,
            );
            final row = store.db
                .select('SELECT id FROM quotation WHERE deleted=0')
                .single;
            expect(
              store.get('quotation', row['id'] as String)!.data['product_id'],
              product,
            );
            expect(
              (receipt.result['records'] as Map)['r0']['businessObjectId'],
              row['id'],
            );
          }
        } finally {
          await f.close();
        }
      }
    },
  );
  test('uncertain_duplicate_requires_choice', () async {
    final f = await _Fixture.open();
    try {
      f.host.inquiry!.runtime.state.store.save('product', {
        for (final field in Product.fields) field: null,
        'name': '水泵',
        'unit': '台',
        'model': 'M1',
      });
      final draft = await f.prepare();
      expect(draft.records.single.status, InquiryRecordStatus.conflict);
      await expectLater(draft.confirm(['r0']), throwsStateError);
      await draft.choose('r0');
      expect(draft.records.single.status, InquiryRecordStatus.valid);
      final confirmed = await draft.confirm(['r0']);
      final coordinator = ImportCoordinator(f.host.workspaces);
      final intent = await coordinator.record(confirmed);
      await coordinator.commit(f.runtime, confirmed, intent);
      expect(f.quotationCount, 1);
    } finally {
      await f.close();
    }
  });
  test('edited_partial_import_preserves_receipts', () async {
    final root = Directory.systemTemp.createTempSync('reg4b-partial-');
    var host = await MuyonHost.open(root.path);
    try {
      await host.activateInquiry();
      var store = host.inquiry!.runtime.state.store;
      final project = store.save('project', {
        for (final f in Project.fields) f: null,
        'code': 'REG4B',
        'name': '公开导入夹具',
        'status': 'active',
        'type': 'market',
        'level': 'A',
        'currency': 'CNY',
        'tax_mode': 'included',
        'markup_rate': '0',
      });
      store.applyOffers(
        [
          (
            offer: cleanOffer({
              'supplier': '公开供应商',
              'name': '风机',
              'unit': '台',
              'price': '20',
              'quoted_on': '2026-10-01',
            }),
            supplierId: null,
            productId: null,
          ),
        ],
        projectId: project,
        inquirer: '-',
      );
      final workspace = await host.workspaces.create('REG4B');
      final target = ImportTarget.create(
        WorkspaceBinding(
          workspaceId: workspace.id,
          moduleId: 'inquiry',
          nativeProjectId: project,
        ),
      );
      final source = File('${root.path}/offers.txt')
        ..writeAsStringSync(
          '供应商\t产品名称\t单位\t单价\t报价日期\n公开供应商\t水泵\t台\t10\t2026-10-01\n公开供应商\t风机\t台\t20\t2026-10-01\n公开供应商\t电缆\t\t30\t2026-10-01',
        );
      var runtime = host.modules.runtime<ModuleRuntime>('inquiry')!;
      final dynamic draft = await runtime.prepareImport(
        SelectedInquiryInput(
          path: source.path,
          displayName: 'offers.txt',
          purpose: InquiryImportPurpose.quotations,
        ),
        target,
      );
      expect(draft.recordIds, ['r0', 'r1', 'r2']);
      await draft.edit('r0', 'price', '12');
      final PreparedImport confirmed = await draft.confirm(['r0']);
      final coordinator = ImportCoordinator(host.workspaces);
      final intent = await coordinator.record(confirmed);
      await expectLater(
        coordinator.commit(
          runtime,
          confirmed,
          intent,
          interruptBeforeActivation: true,
        ),
        throwsStateError,
      );
      final receipt = (await runtime.receipt(intent.operationId))!;
      expect(receipt.result['succeededRecordIds'], ['r0']);
      expect(receipt.result['skippedRecordIds'], ['r1']);
      expect(receipt.result['pendingRecordIds'], ['r2']);
      final rows = receipt.result['records'] as Map?;
      expect(rows, isNotNull);
      expect((rows!['r0'] as Map)['status'], 'succeeded');
      expect((rows['r0'] as Map)['businessObjectId'], isNotEmpty);
      expect((rows['r1'] as Map)['status'], 'skipped');
      expect((rows['r2'] as Map)['status'], 'pending');
      expect(
        store.db.select('SELECT count(*) AS n FROM quotation').single['n'],
        2,
      );
      expect(
        store
            .listQuotations(projectId: project)
            .any((q) => q.data['price'] == '12'),
        isTrue,
      );
      final String draftId = draft.draftId;
      await host.close();
      host = await MuyonHost.open(root.path);
      await host.activateInquiry();
      runtime = host.modules.runtime<ModuleRuntime>('inquiry')!;
      store = host.inquiry!.runtime.state.store;
      expect(
        host.workspaces.binding(workspace.id, 'inquiry')!.nativeProjectId,
        project,
      );
      expect(
        (await runtime.receipt(intent.operationId))!.result,
        receipt.result,
      );
      expect(
        (await runtime.commitImport(confirmed, intent)).result,
        receipt.result,
      );
      final dynamic resumed = await (runtime as dynamic).resumeImport(draftId);
      expect(resumed.value('r0', 'price'), '12');
      await resumed.edit('r2', 'unit', '米');
      final PreparedImport continuation = await resumed.confirm(['r2']);
      final next = await ImportCoordinator(host.workspaces)
          .record(continuation);
      expect(next.operationId, isNot(intent.operationId));
      await ImportCoordinator(host.workspaces)
          .commit(runtime, continuation, next);
      expect(
        store.db.select('SELECT count(*) AS n FROM quotation').single['n'],
        3,
      );
      expect(
        (await runtime.receipt(intent.operationId))!.result,
        receipt.result,
      );
      await expectLater(resumed.confirm(['r0']), throwsStateError);
    } finally {
      await host.close();
      root.deleteSync(recursive: true);
    }
  });
  test('choose_purpose_before_preview', () async {
    final root = Directory.systemTemp.createTempSync('reg4b-purpose-');
    final host = await MuyonHost.open(root.path);
    try {
      await host.activateInquiry();
      final module = host.registry.require('inquiry');
      expect(module.manifest.features, contains(ModuleFeature.importPipeline));
      final runtime = host.modules.runtime<ModuleRuntime>('inquiry')!;
      expect(runtime, isA<ImportCapable>());
      final source = File('${root.path}/quote.txt')
        ..writeAsStringSync('产品名称\t单位\n水泵\t台');
      await expectLater(
        runtime.prepareImport(
          SelectedInput(path: source.path, displayName: 'quote.txt'),
          const ImportTarget.create(
            WorkspaceBinding(
              workspaceId: 'w',
              moduleId: 'inquiry',
              nativeProjectId: 'p',
            ),
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'reason',
            'Choose an import purpose first',
          ),
        ),
      );
      expect(
        host.inquiry!.runtime.state.store.db
            .select('SELECT count(*) AS n FROM product')
            .single['n'],
        0,
      );
    } finally {
      await host.close();
      root.deleteSync(recursive: true);
    }
  });
}

class _Fixture {
  _Fixture(this.root, this.host, this.project, this.target);
  final Directory root;
  final MuyonHost host;
  final String project;
  final ImportTarget target;
  ModuleRuntime get runtime => host.modules.runtime<ModuleRuntime>('inquiry')!;
  int get quotationCount =>
      host.inquiry!.runtime.state.store.db
              .select('SELECT count(*) AS n FROM quotation')
              .single['n']
          as int;
  static Future<_Fixture> open() async {
    final root = Directory.systemTemp.createTempSync('reg4b-case-');
    final host = await MuyonHost.open(root.path);
    await host.activateInquiry();
    final project = host.inquiry!.runtime.state.store.save('project', {
      for (final f in Project.fields) f: null,
      'code': 'REG4B',
      'name': '公开项目',
      'status': 'active',
      'type': 'market',
      'level': 'A',
      'currency': 'CNY',
      'tax_mode': 'included',
      'markup_rate': '0',
    });
    final workspace = await host.workspaces.create('公开夹具');
    return _Fixture(
      root,
      host,
      project,
      ImportTarget.create(
        WorkspaceBinding(
          workspaceId: workspace.id,
          moduleId: 'inquiry',
          nativeProjectId: project,
        ),
      ),
    );
  }

  Future<PreparedInquiryDraft> prepare() async {
    final file = File('${root.path}/offers.txt')
      ..writeAsStringSync('供应商\t产品名称\t型号\t单位\t单价\n公开供应商\t水泵\tM2\t台\t10');
    return await runtime.prepareImport(
      SelectedInquiryInput(
        path: file.path,
        displayName: 'offers.txt',
        purpose: InquiryImportPurpose.quotations,
      ),
      target,
    ) as PreparedInquiryDraft;
  }

  Future<void> close() async {
    await host.close();
    root.deleteSync(recursive: true);
  }

  Future<void> addTask() => host.foundation.database.write(
    (db) => db.execute('INSERT INTO execution_records VALUES(?,?,?)', [
      'task',
      'interrupted',
      jsonEncode({
        'kind': 'personal',
        'executionId': 'task',
        'prompt': '公开文件导入',
        'conversationId': 'public-conversation',
        'executionDeviceId': 'public-device',
        'updatedAt': '2026-10-09T00:00:00Z',
        'state': 'interrupted',
        'stage': 'interrupted',
        'scope': AssistantScope.workspace(target.binding.workspaceId).toJson(),
      }),
    ]),
  );
}
