import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:muyon/screens/inquiry_import_context.dart';
import 'package:muyon/app/inquiry_list_review.dart';
import 'package:muyon_ui/dynamic_ui.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/adapters/inquiry_module.dart';
import 'package:muyon/services/models/model_gateway.dart';
import 'package:muyon/services/models/profile_repository.dart';
import 'package:muyon/workspace/import_coordinator.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:supplier_core/supplier_core.dart';

void main() {
  LiveTestWidgetsFlutterBinding();
  HttpOverrides.global = null;
  test(
    'project_preview_edit_invalidates_confirmation_and_freezes_after_creation',
    () async {
      final f = await _ListFixture.open();
      try {
        final dynamic draft = await f.prepare();
        final PreparedImport old = await draft.confirm(['r0']);
        await draft.editProject('name', '人工修改项目名');
        final c = ImportCoordinator(f.host.workspaces);
        await expectLater(
          f.runtime.commitImport(old, await c.record(old)),
          throwsStateError,
        );
        expect(f.projects, 0);
        final prepared = await draft.confirm(['r0']);
        final pending = c.pending('inquiry');
        await c.abandon('inquiry', f.runtime, pending.single.operationId);
        final receipt = await c.commit(
          f.runtime,
          prepared,
          await c.record(prepared),
        );
        expect(
          f.store.get('project', receipt.targetProjectId)!.data['name'],
          '人工修改项目名',
        );
        await expectLater(draft.editProject('name', '再次新建'), throwsStateError);
      } finally {
        await f.close();
      }
    },
  );
  test('created_project_version_change_blocks_remaining_list', () async {
    final f = await _ListFixture.open();
    try {
      final draft = await f.prepare();
      final c = ImportCoordinator(f.host.workspaces);
      final first = await draft.confirm(['r0']);
      await c.commit(f.runtime, first, await c.record(first));
      final project = f.store.get('project', f.target.binding.nativeProjectId)!;
      f.store.save('project', {
        ...project.data,
        'name': '已由其他操作更改',
      }, id: project.id);
      await expectLater(draft.confirm(['r1']), throwsStateError);
      expect(f.items, 1);
      expect(f.projects, 1);
    } finally {
      await f.close();
    }
  });
  for (final change in ['source', 'schema', 'edit']) {
    test('list_confirmation_rejects_$change', () async {
      final f = await _ListFixture.open();
      try {
        final draft = await f.prepare();
        final prepared = await draft.confirm(['r0']);
        final c = ImportCoordinator(f.host.workspaces);
        final intent = await c.record(prepared);
        if (change == 'edit') {
          await draft.edit('r0', 'qty', '9');
        } else {
          final key = 'inquiry-import:list-draft:${draft.draftId}';
          final d = jsonDecode(
            f.store.db.select('SELECT value FROM meta WHERE key=?', [
                  key,
                ]).single['value']
                as String,
          ) as Map;
          if (change == 'source') {
            File(d['path'] as String).writeAsStringSync('来源已改变');
          } else {
            d['listSchema'] = 'changed';
            f.store.db.execute('UPDATE meta SET value=? WHERE key=?', [
              jsonEncode(d),
              key,
            ]);
          }
        }
        await expectLater(
          f.runtime.commitImport(prepared, intent),
          throwsStateError,
        );
        expect(f.projects, 0);
        expect(f.items, 0);
        expect(await f.runtime.receipt(intent.operationId), isNull);
      } finally {
        await f.close();
      }
    });
  }
  test('list_receipt_failure_rolls_back_project_items_and_ai_marker', () async {
    final f = await _ListFixture.open();
    try {
      final draft = await f.prepare();
      final prepared = await draft.confirm(['r0']);
      final c = ImportCoordinator(f.host.workspaces);
      final intent = await c.record(prepared);
      f.store.db.execute(
        "CREATE TRIGGER reject_list_receipt BEFORE INSERT ON meta WHEN NEW.key LIKE 'inquiry-import:receipt:%' BEGIN SELECT RAISE(ABORT,'receipt failure'); END",
      );
      await expectLater(
        f.runtime.commitImport(prepared, intent),
        throwsA(anything),
      );
      expect(f.projects, 0);
      expect(f.items, 0);
      expect(await f.runtime.receipt(intent.operationId), isNull);
      expect(
        f.store.db.select("SELECT * FROM meta WHERE key LIKE 'ai_applied:%'"),
        isEmpty,
      );
      f.store.db.execute('DROP TRIGGER reject_list_receipt');
      final receipt = await c.commit(f.runtime, prepared, intent);
      expect(receipt.targetProjectId, f.target.binding.nativeProjectId);
      expect(f.projects, 1);
      expect(f.items, 1);
    } finally {
      await f.close();
    }
  });
  test(
    'list_preserves_existing_model_approval_and_rejects_existing_target',
    () async {
      final f = await _ListFixture.open();
      try {
        f.approve = false;
        await expectLater(f.prepare(), throwsA(anything));
        expect(f.requests, 0);
        expect(f.projects, 0);
        f.store.save('project', {
          for (final field in Project.fields) field: null,
          'name': '已有项目',
          'code': 'OLD',
          'status': 'active',
          'currency': 'CNY',
          'tax_mode': 'included',
          'markup_rate': '0',
        }, newId: f.target.binding.nativeProjectId);
        f.approve = true;
        await expectLater(f.prepare(), throwsStateError);
        expect(f.requests, 0);
        expect(f.projects, 1);
        expect(f.items, 0);
      } finally {
        await f.close();
      }
    },
  );
  test(
    'list_matched_candidate_reuses_original_quantity_and_unit_rules',
    () async {
      final f = await _ListFixture.open();
      try {
        final product = f.store.save('product', {
          for (final field in Product.fields) field: null,
          'name': '公开水泵',
          'unit': '个',
        });
        f.matchingProduct = product;
        final draft = await f.prepare();
        expect(draft.records.first.line.productId, product);
        final prepared = await draft.confirm(['r0']);
        final c = ImportCoordinator(f.host.workspaces);
        final intent = await c.record(prepared);
        await c.commit(f.runtime, prepared, intent);
        final line = f.store
            .budget(f.target.binding.nativeProjectId)
            .lines
            .single
            .data;
        expect(line['product_id'], product);
        expect(line['unit'], '个');
        expect(line['notes'], contains('清单单位：台'));
        expect(line['qty'], '2');
        expect(f.projects, 1);
        expect(f.items, 1);
        expect(f.requests, 2);
      } finally {
        await f.close();
      }
    },
  );
  testWidgets('list_project_metadata_has_one_editor_across_groups', (
    tester,
  ) async {
    final f = await _ListFixture.open();
    try {
      f.lineCount = 6;
      await f.addTask();
      final draft = await f.prepare();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InquiryListReviewPage(
              host: f.host,
              taskId: 'list-task',
              draft: draft,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final c = tester
          .widget<UiWorkspaceView>(find.byType(UiWorkspaceView))
          .controller;
      c.surface.session.edit('project:name', '统一人工项目名');
      await tester.tap(find.text('下一组'));
      await tester.pumpAndSettle();
      final second = tester
          .widget<UiWorkspaceView>(find.byType(UiWorkspaceView))
          .controller;
      expect(
        second.surface.current.snapshot.initialUiState.keys.where(
          (k) => k.startsWith('project:'),
        ),
        isEmpty,
      );
      expect(draft.project['name'], '统一人工项目名');
      await tester.tap(find.byKey(const ValueKey('list-select-r5')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认新建项目并导入'));
      await tester.pumpAndSettle();
      expect(f.projects, 1);
      expect(f.items, 1);
      await tester.tap(find.text('上一组'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('list-select-r0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认剩余清单'));
      await tester.pumpAndSettle();
      expect(f.items, 2);
      expect(
        f.store.get('project', f.target.binding.nativeProjectId)!.data['name'],
        '统一人工项目名',
      );
      expect(find.textContaining('未确认完成'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    } finally {
      await f.close();
    }
  });
  testWidgets('list_preview_distinguishes_candidates_and_actual_quote', (
    tester,
  ) async {
    final f = await _ListFixture.open();
    try {
      await f.addTask();
      final ids = <String>[];
      for (final model in ['A型', 'B型']) {
        ids.add(
          f.store.save('product', {
            for (final field in Product.fields) field: null,
            'name': '公开水泵',
            'unit': '个',
            'model': model,
            'specification': '规格$model',
          }),
        );
      }
      f.matchingProduct = ids.first;
      final supplier = f.store.save('supplier', {
        for (final field in Supplier.fields) field: null,
        'name': '公开供应商',
        'aliases': <String>[],
        'categories': <String>[],
      });
      final quoteProject = f.store.save('project', {
        for (final field in Project.fields) field: null,
        'name': '报价来源项目',
        'code': 'QUOTE-SOURCE',
        'status': 'active',
        'currency': 'CNY',
        'tax_mode': 'included',
        'markup_rate': '0',
      });
      f.store.save('quotation', {
        for (final field in Quotation.fields) field: null,
        'supplier_id': supplier,
        'product_id': ids.first,
        'price': '123',
        'currency': 'CNY',
        'tax_mode': 'included',
        'unit_snapshot': '个',
        'min_qty': '1',
        'quoted_on': '2026-10-01',
        'inquirer_name': '公开测试',
        'inquiry_precision': 'date',
        'inquiry_date': '2026-10-01',
        'project_id': quoteProject,
        'capture_mode': 'standard',
      });
      final draft = await f.prepare();
      expect(draft.records.first.line.quote?.price, '123');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InquiryListReviewPage(
              host: f.host,
              taskId: 'list-task',
              draft: draft,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('规格A型'), findsWidgets);
      expect(find.textContaining('123 CNY'), findsWidgets);
      expect(find.textContaining('入库数量：2 个'), findsWidgets);
      expect(find.textContaining('公开供应商'), findsWidgets);
      await tester.ensureVisible(find.byKey(const ValueKey('list-product-r0')));
      await tester.tap(find.byKey(const ValueKey('list-product-r0')));
      await tester.pumpAndSettle();
      expect(find.textContaining('规格B型'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    } finally {
      await f.close();
    }
  });
  for (final committed in [false, true]) {
    testWidgets('list_queries_real_receipt_without_replaying_$committed', (
      tester,
    ) async {
      final f = await _ListFixture.open();
      try {
        await f.addTask();
        final draft = await f.prepare();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InquiryListReviewPage(
                host: f.host,
                taskId: 'list-task',
                draft: draft,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final controller = tester
            .widget<UiWorkspaceView>(find.byType(UiWorkspaceView))
            .controller;
        final prepared = await draft.confirm(['r0']);
        final c = ImportCoordinator(f.host.workspaces);
        final intent = await c.record(prepared);
        controller.surface.lockRecoveredOperations([intent.operationId]);
        await controller.flush();
        if (committed) {
          await expectLater(
            c.commit(
              f.runtime,
              prepared,
              intent,
              interruptBeforeActivation: true,
            ),
            throwsStateError,
          );
        }
        final beforeProjects = f.projects, beforeItems = f.items;
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InquiryListReviewPage(
                host: f.host,
                taskId: 'list-task',
                draft: await f.runtime.resumeListImport(draft.draftId),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('查询提交回执'));
        await tester.pumpAndSettle();
        expect(f.projects, beforeProjects);
        expect(f.items, beforeItems);
        expect(f.requests, 1);
        expect(c.pending('inquiry').length, committed ? 0 : 1);
        expect(
          find.textContaining(committed ? '本草稿已创建项目' : '回执尚未确认'),
          findsWidgets,
        );
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      } finally {
        await f.close();
      }
    });
  }
  testWidgets('human_new_project_preview_commit_and_resume', (tester) async {
    final f = await _ListFixture.open();
    try {
      await f.host.foundation.database.write(
        (db) => db.execute('INSERT INTO execution_records VALUES(?,?,?)', [
          'list-task',
          'interrupted',
          jsonEncode({
            'kind': 'personal',
            'executionId': 'list-task',
            'prompt': '公开清单导入',
            'conversationId': 'list-conversation',
            'executionDeviceId': 'public-device',
            'updatedAt': '2026-10-09T00:00:00Z',
            'state': 'interrupted',
            'stage': 'interrupted',
            'scope': AssistantScope.workspace(f.target.binding.workspaceId)
                .toJson(),
          }),
        ]),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InquiryImportContextPage(
              host: f.host,
              taskId: 'list-task',
              pickInput: () async => f.input,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('import-plugin')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('询价').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('import-function')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建项目清单').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('list-project-name')),
        '公开新项目',
      );
      await tester.tap(find.text('选择本地文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('准备新项目清单'));
      await tester.pumpAndSettle();
      expect(find.textContaining('将新建项目：公开新项目'), findsWidgets);
      expect(f.projects, 0);
      await tester.tap(find.byKey(const ValueKey('list-select-r0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认新建项目并导入'));
      await tester.pumpAndSettle();
      expect(f.projects, 1);
      expect(f.items, 1);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续项目清单草稿').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('本草稿已创建项目'), findsWidgets);
      expect(f.requests, 1);
      expect(f.projects, 1);
      expect(f.items, 1);
      await tester.tap(find.byKey(const ValueKey('list-select-r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认剩余清单'));
      await tester.pumpAndSettle();
      expect(f.items, 2);
      expect(f.projects, 1);
      expect(f.requests, 1);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    } finally {
      await f.close();
    }
  });
  test(
    'new_project_list_partial_commit_and_recovery_never_creates_twice',
    () async {
      final root = Directory.systemTemp.createTempSync('reg4b-list-');
      var host = await MuyonHost.open(root.path);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      server.listen((request) async {
        await utf8.decoder.bind(request).join();
        requests++;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': jsonEncode({
                    'items': [
                      {
                        'name': '公开水泵',
                        'qty': '2',
                        'unit': '台',
                        'keywords': ['公开水泵'],
                      },
                      {
                        'name': '公开阀门',
                        'qty': '约4',
                        'unit': '个',
                        'keywords': ['公开阀门'],
                      },
                    ],
                  }),
                },
              },
            ],
          }),
        );
        await request.response.close();
      });
      try {
        await ProfileRepository(host.workspaces).save(
          ModelProfile(
            id: 'list-local',
            endpoint: Uri.parse(
              'http://127.0.0.1:${server.port}/v1/chat/completions',
            ),
            location: ModelLocation.local,
            modelId: 'public-fixture',
            endpointIdentity: 'public-local',
          ),
        );
        await host.workspaces.setSetting('activeModelProfileId', 'list-local');
        host.approveInquiryModelRequest = (_) async => true;
        await host.activateInquiry();
        dynamic runtime = host.modules.runtime<InquiryModuleRuntime>(
          'inquiry',
        )!;
        final workspace = await host.workspaces.create('清单工作区');
        final projectId = newUuid();
        final target = ImportTarget.create(
          WorkspaceBinding(
            workspaceId: workspace.id,
            moduleId: 'inquiry',
            nativeProjectId: projectId,
          ),
        );
        final file = File('${root.path}/list.txt')
          ..writeAsStringSync('公开水泵2台\n公开阀门约4个');
        final dynamic draft = await runtime.prepareListImport(
          SelectedInput(path: file.path, displayName: 'list.txt'),
          target,
          {'name': '明确新建项目', 'code': 'LIST-NEW'},
        );
        final store = host.inquiry!.runtime.state.store;
        expect(store.get('project', projectId), isNull);
        expect(draft.project['name'], '明确新建项目');
        final PreparedImport prepared = await draft.confirm(['r0']);
        final coordinator = ImportCoordinator(host.workspaces);
        final intent = await coordinator.record(prepared);
        final receipts = await Future.wait<ImportReceipt>([
          coordinator.commit(runtime, prepared, intent),
          coordinator.commit(runtime, prepared, intent),
        ]);
        expect(receipts[0].result, receipts[1].result);
        expect(receipts[0].result['projectId'], projectId);
        expect(
          (receipts[0].result['records'] as Map)['r1']['status'],
          'pending',
        );
        expect(
          (receipts[0].result['records'] as Map)['r1'].containsKey('error'),
          isTrue,
        );
        expect(
          store.db.select('SELECT count(*) AS n FROM project').single['n'],
          1,
        );
        expect(
          store.db.select('SELECT count(*) AS n FROM project_item').single['n'],
          1,
        );
        final id = draft.draftId as String;
        await host.close();
        host = await MuyonHost.open(root.path);
        await host.activateInquiry();
        runtime = host.modules.runtime<InquiryModuleRuntime>('inquiry')!;
        final dynamic resumed = await runtime.resumeListImport(id);
        expect(requests, 1);
        await expectLater(resumed.confirm(['r0']), throwsStateError);
        final PreparedImport rest = await resumed.confirm(['r1']);
        expect(rest.target.kind, ImportKind.refresh);
        final next = ImportCoordinator(host.workspaces);
        final result = await next.commit(
          runtime,
          rest,
          await next.record(rest),
        );
        expect(result.result['succeededRecordIds'], ['r1']);
        final reopened = host.inquiry!.runtime.state.store;
        expect(
          reopened.db.select('SELECT count(*) AS n FROM project').single['n'],
          1,
        );
        expect(
          reopened.db
              .select('SELECT count(*) AS n FROM project_item')
              .single['n'],
          2,
        );
        final row = reopened
            .budget(projectId)
            .lines
            .singleWhere((l) => l.data['name'] == '公开阀门')
            .data;
        expect(row['qty'], '4');
        expect(row['notes'], contains('约4'));
        expect(await runtime.receipt(intent.operationId), isNotNull);
        expect(requests, 1);
      } finally {
        await host.close();
        await server.close(force: true);
        root.deleteSync(recursive: true);
      }
    },
  );
}

class _ListFixture {
  _ListFixture(this.root, this.host, this.server, this.target, this.input);
  final Directory root;
  final MuyonHost host;
  final HttpServer server;
  final ImportTarget target;
  final SelectedInput input;
  String? matchingProduct;
  int lineCount = 2;
  int requests = 0;
  bool approve = true;
  Store get store => host.inquiry!.runtime.state.store;
  int get projects =>
      store.db.select('SELECT count(*) AS n FROM project').single['n'] as int;
  int get items =>
      store.db.select('SELECT count(*) AS n FROM project_item').single['n']
          as int;
  InquiryModuleRuntime get runtime =>
      host.modules.runtime<InquiryModuleRuntime>('inquiry')!;
  static Future<_ListFixture> open() async {
    final root = Directory.systemTemp.createTempSync('list-fixture-');
    final host = await MuyonHost.open(root.path);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    await ProfileRepository(host.workspaces).save(
      ModelProfile(
        id: 'list-local',
        endpoint: Uri.parse(
          'http://127.0.0.1:${server.port}/v1/chat/completions',
        ),
        location: ModelLocation.local,
        modelId: 'public-fixture',
        endpointIdentity: 'local-public',
      ),
    );
    await host.workspaces.setSetting('activeModelProfileId', 'list-local');
    await host.activateInquiry();
    final w = await host.workspaces.create('公开清单工作区');
    final file = File('${root.path}/list.txt')
      ..writeAsStringSync('公开水泵2台\n公开阀门约4个');
    final f = _ListFixture(
      root,
      host,
      server,
      ImportTarget.create(
        WorkspaceBinding(
          workspaceId: w.id,
          moduleId: 'inquiry',
          nativeProjectId: newUuid(),
        ),
      ),
      SelectedInput(path: file.path, displayName: 'list.txt'),
    );
    host.approveInquiryModelRequest = (_) async => f.approve;
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      f.requests++;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': jsonEncode(
                  f.requests > 1 && f.matchingProduct != null
                      ? {
                          'matches': [
                            {
                              'index': 0,
                              'product_id': f.matchingProduct,
                              'confidence': 'high',
                            },
                          ],
                        }
                      : {
                          'items': [
                            {
                              'name': '公开水泵',
                              'qty': '2',
                              'unit': '台',
                              'keywords': ['公开水泵'],
                            },
                            {
                              'name': '公开阀门',
                              'qty': '约4',
                              'unit': '个',
                              'keywords': ['公开阀门'],
                            },
                            for (var i = 2; i < f.lineCount; i++)
                              {
                                'name': '公开条目$i',
                                'qty': '1',
                                'unit': '项',
                                'keywords': ['公开条目$i'],
                              },
                          ],
                        },
                ),
              },
            },
          ],
        }),
      );
      await request.response.close();
    });
    return f;
  }

  Future<void> addTask() => host.foundation.database.write(
    (db) => db.execute('INSERT INTO execution_records VALUES(?,?,?)', [
      'list-task',
      'interrupted',
      jsonEncode({
        'kind': 'personal',
        'executionId': 'list-task',
        'prompt': '公开清单导入',
        'conversationId': 'list-conversation',
        'executionDeviceId': 'public-device',
        'updatedAt': '2026-10-09T00:00:00Z',
        'state': 'interrupted',
        'stage': 'interrupted',
        'scope': AssistantScope.workspace(target.binding.workspaceId).toJson(),
      }),
    ]),
  );
  Future<PreparedInquiryListDraft> prepare() => runtime.prepareListImport(
    input,
    target,
    {'name': '明确新建项目', 'code': 'LIST-NEW'},
  );
  Future<void> close() async {
    await host.close();
    await server.close(force: true);
    root.deleteSync(recursive: true);
  }
}
