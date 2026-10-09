import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/module_catalog.dart';
import 'package:muyon/screens/dynamic_workspace.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:supplier_core/supplier_core.dart';

import '../../../../packages/muyon_ui/test/dynamic_fixtures.dart';

class NavigationFixture {
  NavigationFixture(this.root, this.host, this.conversationId);
  final Directory root;
  final MuyonHost host;
  final String conversationId;

  static Future<NavigationFixture> open(
    WidgetTester tester, {
    List<BusinessModule> extra = const [],
  }) async {
    final root = Directory.systemTemp.createTempSync('ui2a-');
    final f = (await tester.runAsync(() async {
      final host = await MuyonHost.open(
        '${root.path}/data',
        modules: extra.isEmpty ? null : [...extra, ...moduleCatalog()],
      );
      final conversation = await host.foundation.createConversation();
      await host.foundation.database.write(
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
      return NavigationFixture(root, host, conversation.id);
    }))!;
    addTearDown(() async {
      await tester.runAsync(f.host.close);
      root.deleteSync(recursive: true);
    });
    return f;
  }

  Future<ObjectRef> seedObject(WidgetTester tester, String module) async =>
      (await tester.runAsync(() async {
        final workspace = await host.workspaces.create('公开导航夹具');
        String project;
        if (module == 'research') {
          await host.activateResearch();
          final db = host.research!.store.db;
          db.execute(
            "INSERT INTO projects(id,title,question,next_step,layout,skill_root) VALUES('project','导航研究项目','','','generic','')",
          );
          db.execute(
            "INSERT INTO entries(id,project_id,kind,title,data) VALUES('entry','project','claims','真实研究对象','{\"statement\":\"研究原始内容\"}')",
          );
          project = 'project';
        } else {
          await host.activateInquiry();
          project = host.inquiry!.runtime.state.store.save('project', {
            for (final field in Project.fields) field: null,
            'code': 'UI2A',
            'name': '真实询价对象',
            'status': 'active',
            'type': 'market',
            'level': 'A',
            'currency': 'CNY',
            'tax_mode': 'included',
            'markup_rate': '0',
          });
        }
        await host.workspaces.bind(
          WorkspaceBinding(
            workspaceId: workspace.id,
            moduleId: module,
            nativeProjectId: project,
          ),
        );
        return ObjectRef(
          moduleId: module,
          objectType: module == 'research' ? 'entry' : 'project',
          objectId: module == 'research' ? 'entry' : project,
          nativeProjectId: project,
        );
      }))!;

  ValidatedUiPlan plan(ObjectRef ref, {ArtifactRef? artifact}) {
    final original = actionPlan();
    final source = original.snapshot;
    final s = DataSnapshot(
      ref: source.ref,
      facts: {
        for (final e in source.facts.entries)
          e.key: SnapshotFact(
            object: ref,
            field: e.value.field,
            value: e.value.value,
            state: e.value.state,
            unit: e.value.unit,
            sourceRefs: e.value.sourceRefs,
          ),
      },
      initialUiState: source.initialUiState,
      computations: source.computations,
      sources: artifact == null
          ? source.sources
          : {
              'source': SourceSpanRef(
                artifact: artifact,
                originalText: '公开文件原文',
                start: 0,
                end: 6,
              ),
            },
      sourceDigests: artifact == null
          ? source.sourceDigests
          : {artifact.artifactId: artifact.contentDigest},
      actionContext: source.actionContext,
    );
    return validateUiPlan(
      original.plan,
      s,
      original.intent,
      original.catalog,
    ).validatedPlan!;
  }

  Future<void> show(WidgetTester tester, ValidatedUiPlan plan) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DynamicWorkspace(
          repository: host.foundation,
          taskId: 'task',
          surfaceId: plan.plan.surfaceId,
          plan: plan,
          originalAnswer: '原对话回答',
          host: host,
        ),
      ),
    );
    await frames(tester);
  }

  static Future<void> frames(WidgetTester tester, {int count = 10}) async {
    for (var i = 0; i < count; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 25));
    }
  }
}
