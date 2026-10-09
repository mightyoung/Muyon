import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/module_host.dart';
import 'package:muyon/platform/object_pages.dart';
import 'package:muyon/platform/module_grants.dart';
import 'support/fake_v2_module.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:prototype_module/prototype_module.dart';
import 'package:research_module/research_module.dart';
import 'package:sqlite3/sqlite3.dart';

class _Declarations implements ToolRegistrar {
  _Declarations(this.moduleId);
  @override
  final String moduleId;
  final specs = <String,ToolSpec>{};
  void _add(ToolSpec spec) {specs['$moduleId.${spec.name}']=spec;}
  @override
  void read(ToolSpec spec,ModuleToolHandler handler) => _add(spec);
  @override
  void write(WriteToolSpec spec,ModuleToolHandler handler) => _add(spec);
  @override
  void external(ExternalToolSpec spec,ModuleToolHandler handler) => _add(spec);
  @override
  HostChannel channel(ChannelSpec spec) => throw UnimplementedError();
}

class _ObservedWrite implements ManagedDatabase {
  _ObservedWrite(this.delegate);
  final ManagedDatabase delegate;
  final queued = Completer<void>();
  @override
  Database get raw => delegate.raw;
  @override
  Future<T> write<T>(T Function(Database) body) {
    if (!queued.isCompleted) queued.complete();
    return delegate.write(body);
  }
}

void main() {
  late Directory root;
  late MuyonHost host;
  var invocation = 0;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('reg3a-');
    host = await MuyonHost.open(p.join(root.path, 'data'));
  });
  tearDown(() async {
    await host.close();
    root.deleteSync(recursive: true);
  });

  Future<ObjectRef> current(String type, String id, String project) async {
    final session = await host.research!.openScopeSession();
    try {
      return (await session.resolve(ObjectRef(moduleId: 'research',
        objectType: type, objectId: id, nativeProjectId: project)))!.ref;
    } finally { await session.dispose(); }
  }

  Future<void> research() async {
    await host.activateResearch();
    final store = host.research!.store;
    await store.write(() {
      store.db.execute('INSERT INTO projects(id,title,question,next_step) VALUES(?,?,?,?)', ['P','研究','问题','下一步']);
      store.db.execute('INSERT INTO projects(id,title,question,next_step) VALUES(?,?,?,?)', ['Q','另一项目','','']);
      store.db.execute('INSERT INTO entries(id,project_id,kind,title,data) VALUES(?,?,?,?,?)', ['E','P','claim','证据','{}']);
      final task = store.saveTask(projectId: 'P', title: '实验', goal: '对比', spec: {});
      store.db.execute('INSERT INTO runs VALUES(?,?,?,?,?,?)', ['R',task.id,task.revision,'completed',0,'{}']);
    });
    final file = File(p.join(root.path, 'paper.md'))..writeAsStringSync('原文');
    await store.write(() => store.db.execute(
      'INSERT INTO documents(id,project_id,relative_path,snapshot_path,sha256) VALUES(?,?,?,?,?)',
      ['D','P','paper.md',file.path,'obsolete-database-digest'],
    ));
  }

  ToolCallRequest request(String tool, Map<String,Object?> params, ObjectRef ref) =>
    ToolCallRequest(invocationId:'reg3a-${++invocation}', toolId:tool,
      parameters:params, scope:AssistantScope.selectedObjects([ref]));

  Future<ToolCallResult> approved(ToolCallRequest r) async {
    final prepared = await host.tools.prepare(r);
    final approval = await host.tools.approve(prepared);
    final result = await host.tools.invoke(r.withApproval(approval));
    expect(result.status, ToolCallStatus.succeeded);
    expect(host.workspaces.database.raw.select(
      'SELECT state FROM tool_invocation_receipts WHERE invocation_id=?',
      [r.invocationId]).single['state'], 'succeeded');
    // A changed selected ref may refuse before receipt replay; neither path writes twice.
    try {
      final replay = await host.tools.invoke(r.withApproval(approval));
      expect(replay.status, result.status);
    } on StateError {
      // ScopeResolver refuses a now-stale selected digest before dispatch.
    }
    return result;
  }

  test('both modules declare v2 ontology and bounded coverage, no raw tools capability', () {
    for (final module in <BusinessModuleV2>[ResearchModule(), PrototypeModule()]) {
      expect(module.manifest.apiVersion, 2);
      if (module.manifest.id == 'research') expect(module.routes, isEmpty);
      expect(module.ontology.objectTypes, isNotEmpty);
      expect(module.coverage.operations, isNotEmpty);
      expect(module.manifest.capabilities.map((c) => c.id), isNot(contains('tools')));
      final declarations = _Declarations(module.manifest.id);
      module.registerTools(declarations);
      final operations = {for (final op in module.coverage.operations) op.id:op};
      for (final entry in declarations.specs.entries) {
        expect(entry.value.operations,isNotEmpty);
        for (final id in entry.value.operations) {
          expect(operations[id]?.tools,contains(entry.key));
        }
      }
      for (final action in module.ontology.actions) {
        expect(declarations.specs[action.tool],isNotNull);
        expect(operations[action.operationId]?.tools,contains(action.tool));
      }
      for (final relation in module.ontology.relations) {
        expect(module.ontology.type(relation.from),isNotNull);
        expect(module.ontology.type(relation.to),isNotNull);
        expect(module.ontology.type(relation.from)!.fields.map((f) => f.name),contains(relation.field));
        expect(declarations.specs[relation.queryTool],isNotNull);
      }
      final members = [for (final op in module.coverage.operations) ...op.members];
      expect(members.toSet().length, members.length);
      for (final op in module.coverage.operations) {
        expect(op.tools.isNotEmpty != (op.notExposed != null), isTrue);
        for (final tool in op.tools) {
          expect(host.tools.inspect(tool), isNotNull, reason: op.id);
          expect(declarations.specs[tool]?.operations,contains(op.id),reason:op.id);
        }
      }
    }
    expect(host.tools.list().where((t) => [
      'prototype.list_pages','prototype.page_detail','research.objects',
    ].contains(t.descriptor.toolId)).map((t) => t.descriptor.toolId), [
      'prototype.list_pages','prototype.page_detail','research.objects',
    ]);
    expect(host.tools.inspect('research.objects')!.descriptor.description,
      '在本次范围内检索科研对象：项目、文档和研究条目，按标题子串过滤，最多返回 50 条引用与标题。'
      '只读取本机科研库，不修改数据，也不发送到设备外。');
  });

  test('cross-project canonical project and disk bytes reject stale digest', () async {
    await research();
    final pRef = await current('project','P','P');
    final qRef = await current('project','Q','Q');
    expect(pRef.contentDigest, isNotNull);
    expect(qRef.nativeProjectId, 'Q');
    final ref = await current('document','D','P');
    expect(ref.contentDigest, isNot('obsolete-database-digest'));
    File(p.join(root.path,'paper.md')).writeAsStringSync('变更原文');
    await expectLater(host.scopeResolver.resolve(AssistantScope.selectedObjects([ref])), throwsStateError);
    final newRef = await current('document','D','P');
    expect(newRef.contentDigest, isNot(ref.contentDigest));
    File(p.join(root.path,'paper.md')).deleteSync();
    expect((await current('document','D','P')).contentDigest, 'missing');
  });

  test('selected research reads return details and relations without outside content', () async {
    await research();
    final document = await current('document','D','P');
    final detail = await host.tools.invoke(request('research.read_object',{'type':'document','id':'D'},document));
    expect(detail.status,ToolCallStatus.succeeded);
    expect((detail.data['object'] as Map)['text'],'原文');
    final outside = await host.tools.invoke(request('research.read_object',{'type':'document','id':'D'},await current('project','Q','Q')));
    expect(outside.status,ToolCallStatus.failed);
    expect(outside.objectRefs,isEmpty);
    final project = await current('project','P','P');
    final entry = await current('entry','E','P');
    final relation = await host.tools.invoke(ToolCallRequest(invocationId:'relations-${++invocation}',
      toolId:'research.relations',scope:AssistantScope.selectedObjects([project,entry])));
    expect((relation.data['relations'] as List).single['relation'],'entry_project');
    expect(relation.objectRefs.toSet(),{project,entry});
  });

  for (final name in ['save_note','accept_run','assess_run','add_outline']) {
    test('$name requires selected target and confirmation, writes once with receipt', () async {
      await research();
      final type = name == 'save_note' ? 'document' : name == 'add_outline' ? 'entry' : 'run';
      final id = type == 'document' ? 'D' : type == 'entry' ? 'E' : 'R';
      final params = switch(name) {
        'save_note' => <String,Object?>{'document_id':id,'locator':'1','text':'批注'},
        'accept_run' => <String,Object?>{'run_id':id},
        'assess_run' => <String,Object?>{'run_id':id,'result':'supporting','discriminating':true,'reason':'比较结果'},
        _ => <String,Object?>{'evidence_type':type,'evidence_id':id,'heading':'论证'},
      };
      final ref = await current(type,id,'P');
      final outside = request('research.$name', params, await current('project','Q','Q'));
      final denied = await host.tools.invoke(outside.withApproval(await host.tools.approve(await host.tools.prepare(outside))));
      expect(denied.status, ToolCallStatus.failed);
      final r = request('research.$name',params,ref);
      await expectLater(host.tools.invoke(r), throwsA(isA<Exception>()));
      expect(host.research!.store.notes('D'), isEmpty);
      expect(host.research!.store.runs('P').single.accepted, isFalse);
      expect(host.research!.store.sections('P'), isEmpty);
      final result = await approved(r);
      expect(result.changes, isNotEmpty);
      if (name == 'save_note') expect(host.research!.store.notes('D').single.text,'批注');
      if (name == 'accept_run' || name == 'assess_run') {
        await expectLater(host.scopeResolver.resolve(AssistantScope.selectedObjects([ref])), throwsStateError);
      }
      if (name == 'accept_run') {
        expect(host.research!.store.runs('P').single.accepted,isTrue);
        final noop = await approved(request('research.accept_run',params,await current('run','R','P')));
        expect(noop.changes,isEmpty);
      }
      if (name == 'assess_run') expect(host.research!.store.runs('P').single.data['workbench_assessment'],isNotNull);
      if (name == 'add_outline') {
        expect(host.research!.store.sections('P').single.heading,'论证');
        expect(result.changes.map((c) => c.ref.objectType).toSet(), {'section','outline'});
        final noop = await approved(request('research.add_outline',params,ref));
        expect(noop.changes,isEmpty);
        expect(host.research!.store.db.select('SELECT id FROM outline WHERE project_id=?',['P']),hasLength(1));
      }
    });
  }

  test('queued research write rechecks its selected run inside the transaction', () async {
    await research();
    final original = host.research!.resources;
    final observed = _ObservedWrite(original.database);
    final runtime = ResearchRuntime(ModuleResources(database:observed,
      files:original.files,capabilities:original.capabilities));
    host.modules.setRuntimeForTesting('research',runtime);
    final ref = await current('run','R','P');
    final r = request('research.accept_run',{'run_id':'R'},ref);
    final approval = await host.tools.approve(await host.tools.prepare(r));
    final entered = Completer<void>();
    final release = Completer<void>();
    final holding = (original.database as ExclusiveDatabase).exclusiveAsync<void>((db) async {
      entered.complete();
      await release.future;
      db.execute('UPDATE runs SET data=? WHERE id=?',['{"changed":"while queued"}','R']);
    });
    await entered.future;
    try {
      final resultFuture = host.tools.invoke(r.withApproval(approval));
      await observed.queued.future.timeout(const Duration(seconds:5));
      release.complete();
      await holding;
      final result = await resultFuture;
      expect(result.status,ToolCallStatus.failed);
      expect(runtime.store.runs('P').single.accepted,isFalse);
      expect(result.changes,isEmpty);
      expect(host.tools.receiptFor(r.invocationId)!.state,'failed');
    } finally {
      if (!release.isCompleted) release.complete();
      await holding;
    }
  });

  for (final restart in [false,true]) {
    test('models withdrawal blocks tools ${restart ? 'after restart' : 'immediately'}, reconsideration keeps facade denied', () async {
      await host.activateResearch();
      await host.modules.revokeCapability('research','models');
      if (restart) {
        await host.close();
        host = await MuyonHost.open(p.join(root.path,'data'));
      }
      expect(host.tools.inspect('research.objects')!.available,isFalse);
      await host.activateResearch();
      expect(host.modules.state('research').status,ModuleStatus.failed);
      await expectLater(host.tools.invoke(ToolCallRequest(invocationId:'withdraw-$restart',
        toolId:'research.objects',scope:const AssistantScope.global())), throwsA(isA<Exception>()));
      await host.modules.reconsiderCapability('research','models');
      expect(host.modules.state('research').status,ModuleStatus.ready);
      expect(host.tools.inspect('research.objects')!.available,isTrue);
      final decision = host.grants.forModule('research').singleWhere((g) => g.capability == 'models');
      expect(decision.granted,isFalse);
      expect(decision.policy,GrantPolicy.facadePending);
    });
  }

  test('host reconsideration restores only a capability allowed by static policy', () async {
    await host.close();
    final module = FakeV2Module('scanner', capabilities:{
      const CapabilityRequest(id:'ocr',reason:'扫描'),
    }, onRegisterTools:(registrar) => registrar.read(ToolSpec(name:'read',description:'读取'),
      (_) async => ToolCallResult(status:ToolCallStatus.succeeded,summary:'读取')));
    host = await MuyonHost.open(p.join(root.path,'scanner'),modules:[module]);
    await host.modules.activate('scanner');
    expect(host.grants.forModule('scanner').single.granted,isTrue);
    await host.modules.revokeCapability('scanner','ocr');
    await host.modules.activate('scanner');
    expect(host.modules.state('scanner').status,ModuleStatus.failed);
    await host.modules.reconsiderCapability('scanner','ocr');
    expect(host.modules.state('scanner').status,ModuleStatus.ready);
    expect(host.grants.forModule('scanner').single.granted,isTrue);
    expect(module.lastResources!.capabilities.available,contains('ocr'));
    expect(host.tools.inspect('scanner.read')!.available,isTrue);
    expect((await host.tools.invoke(ToolCallRequest(invocationId:'restored-scanner',
      toolId:'scanner.read',scope:const AssistantScope.global()))).status,ToolCallStatus.succeeded);
  });

  testWidgets('prototype opens without a binding and adds feedback after confirmation', (tester) async {
    await tester.runAsync(() => host.activatePrototype());
    final build = Directory(p.join(root.path,'build'))..createSync();
    File(p.join(build.path,'index.html')).writeAsStringSync('<p>原型</p>');
    final version = (await tester.runAsync(() => host.prototype!.store.importBuild(sourceDir:build.path,title:'页面')))!;
    final session = await host.prototype!.openScopeSession();
    final ref = (await session.resolve(ObjectRef(moduleId:'prototype',objectType:'version',
      objectId:version.id,nativeProjectId:version.pageId)))!.ref;
    await session.dispose();
    final pageRef = ObjectRef(moduleId:'prototype',objectType:'page',objectId:version.pageId,nativeProjectId:version.pageId);
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(c) {context=c;return const SizedBox();})));
    final lease = await openModuleObjectPage(context,host,pageRef);
    expect(lease,isNotNull);
    expect(host.workspaces.ownerWorkspace('prototype',version.pageId),isNull);
    await lease!.dispose();
    final r=request('prototype.add_feedback',{'version_id':version.id,'text':'反馈'},ref);
    await expectLater(host.tools.invoke(r),throwsA(isA<Exception>()));
    expect(host.prototype!.store.feedback(version.pageId),isEmpty);
    final result = await approved(r);
    expect(host.prototype!.store.feedback(version.pageId).single.text,'反馈');
    expect(result.changes.single.ref.contentDigest,isNotNull);
  });
}
