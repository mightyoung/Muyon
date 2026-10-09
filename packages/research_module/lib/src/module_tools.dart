import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'research_module.dart';
import 'core/store.dart';
import 'module_declarations.dart';

void registerResearchTools(ToolRegistrar registrar) {
  registrar.read(
    ToolSpec(
      name: 'objects',
      description:
          '在本次范围内检索科研对象：项目、文档和研究条目，按标题子串过滤，最多返回 50 条引用与标题。'
          '只读取本机科研库，不修改数据，也不发送到设备外。',
      operations: _operations('objects'),
      parameterSchema: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
        'additionalProperties': false,
      },
    ),
    (ctx) async {
      final call = ctx.call;
      final runtime = await ctx.runtime<ResearchRuntime>();
      final query = (call.request.parameters['query'] as String? ?? '')
          .toLowerCase();
      final rows = <Map<String, Object?>>[];
      final refs = <ObjectRef>[];
      for (final ref in call.resolvedScope.objects.where(
        (r) => r.moduleId == 'research' && const {'project','document','entry'}.contains(r.objectType),
      )) {
        runtime.requireCurrent(ref);
        final store = runtime.store;
        final String title;
        if (ref.objectType == 'project') {
          title = store
              .projects()
              .where((p) => p.id == ref.objectId)
              .first
              .title;
        } else if (ref.objectType == 'document') {
          title = store
              .documents(ref.nativeProjectId!)
              .where((d) => d.id == ref.objectId)
              .first
              .relativePath;
        } else {
          title = store
              .entries(ref.nativeProjectId!)
              .where((e) => e.id == ref.objectId)
              .first
              .title;
        }
        if (query.isNotEmpty && !title.toLowerCase().contains(query)) continue;
        refs.add(ref);
        rows.add({'ref': ref.toJson(), 'title': title});
        if (rows.length == 50) break;
      }
      return ToolCallResult(
        status: ToolCallStatus.succeeded,
        summary: '找到 ${rows.length} 个科研对象',
        data: {'objects': rows, 'limit': 50},
        objectRefs: refs,
      );
    },
  );
  registrar.read(ToolSpec(
    name: 'read_object', description: '读取本次范围内的科研项目、文档、条目、运行、提纲、段落、任务或卡片。',
    operations: _operations('read_object'),
    parameterSchema: {
      'type': 'object', 'properties': {
        'type': {'type': 'string', 'enum': ['project','document','entry','outline','section','task','run','card','note']},
        'id': {'type': 'string'},
      }, 'required': ['type','id'], 'additionalProperties': false,
    },
  ), (ctx) async {
    final ref = _selected(ctx, ctx.call.request.parameters['type'] as String,
      ctx.call.request.parameters['id'] as String);
    final runtime = await ctx.runtime<ResearchRuntime>();
    final session = await runtime.openScopeSession();
    try {
      final view = await session.resolve(ref);
      if (view == null) throw StateError('Object changed');
      runtime.requireCurrent(view.ref);
      final project = ref.nativeProjectId!;
      final data = switch (ref.objectType) {
        'project' => () {
          final p = runtime.store.projects().firstWhere((p) => p.id == ref.objectId);
          return <String,Object?>{'title': p.title, 'question': p.question, 'nextStep': p.nextStep};
        }(),
        'entry' => Map<String,Object?>.from(runtime.store.entries(project)
          .firstWhere((e) => e.id == ref.objectId).data),
        'run' => Map<String,Object?>.from(runtime.store.runs(project)
          .firstWhere((r) => r.id == ref.objectId).data),
        'task' => Map<String,Object?>.from(runtime.store.taskRevision(
          ref.objectId, int.parse(view.ref.revisionRef!))!.spec),
        'document' => _document(runtime, ref, view),
        'outline' || 'section' => Map<String,Object?>.from(runtime.store.db.select(
          'SELECT * FROM ${ref.objectType == 'outline' ? 'outline' : 'sections'} WHERE id=? AND project_id=?',
          [ref.objectId, project]).single),
        'note' => Map<String,Object?>.from(runtime.store.db.select(
          'SELECT n.* FROM notes n JOIN documents d ON d.id=n.document_id WHERE n.id=? AND d.project_id=?',
          [ref.objectId,project]).single),
        'card' => () {
          final rows = runtime.store.db.select(
            'SELECT v.envelope FROM rk_revisions v JOIN canonical_object_map m ON m.object_key=v.object_key '
            'WHERE m.local_object_id=? AND m.local_project_id=? AND v.revision_id=?',
            [ref.objectId,project,view.ref.revisionRef]);
          return Map<String,Object?>.from(jsonDecode(rows.single['envelope'] as String) as Map);
        }(),
        _ => throw StateError('Unsupported object type'),
      };
      return ToolCallResult(status: ToolCallStatus.succeeded,
        summary: '读取 ${view.title}', data: {'object': data}, objectRefs: [view.ref]);
    } finally { await session.dispose(); }
  });
  registrar.read(ToolSpec(
    name: 'relations', description: '读取本次范围内科研对象之间的任务运行、提纲证据和段落关系；不扩展资料范围。',
    operations: _operations('relations'),
  ), (ctx) async {
    final runtime = await ctx.runtime<ResearchRuntime>();
    final refs = ctx.call.resolvedScope.objects.where((r) => r.moduleId == 'research').toList();
    for (final ref in refs) { runtime.requireCurrent(ref); }
    final rows = <Map<String,Object?>>[];
    void link(ObjectRef from, String type, String? id, String relation, {String? revision}) {
      if (id == null) return;
      for (final target in refs.where((r) => r.objectType == type && r.objectId == id &&
          r.nativeProjectId == from.nativeProjectId &&
          (revision == null || r.revisionRef == revision))) {
        rows.add({'relation':relation,'from':from.toJson(),'to':target.toJson()});
      }
    }
    for (final ref in refs) {
      if (ref.objectType != 'project' && ref.objectType != 'run' && ref.objectType != 'note') {
        link(ref,'project',ref.nativeProjectId,'${ref.objectType}_project');
      }
      if (ref.objectType == 'run') {
        for (final row in runtime.store.db.select('SELECT task_id,task_revision FROM runs WHERE id=?',[ref.objectId])) {
          link(ref,'task',row['task_id'] as String,'run_task', revision: '${row['task_revision']}');
        }
      } else if (ref.objectType == 'note') {
        for (final row in runtime.store.db.select('SELECT document_id FROM notes WHERE id=?',[ref.objectId])) {
          link(ref,'document',row['document_id'] as String,'note_document');
        }
      } else if (ref.objectType == 'outline') {
        for (final row in runtime.store.db.select('SELECT evidence_id,section_id FROM outline WHERE id=? AND project_id=?',
            [ref.objectId,ref.nativeProjectId])) {
          link(ref,'section',row['section_id'] as String?,'outline_section');
          for (final type in ['entry','run','note']) {
            link(ref,type,row['evidence_id'] as String?,'outline_evidence');
          }
        }
      }
    }
    return ToolCallResult(status: ToolCallStatus.succeeded,
      summary: '找到 ${rows.length} 条范围内关系', data: {'relations': rows}, objectRefs: refs);
  });

  void write(String name, String type, String idParameter,
      Map<String,Object?> properties, List<String> required,
      void Function(WorkbenchStore, Map<String,Object?>) apply) {
    registrar.write(WriteToolSpec(
      name: name, description: '在已选择的科研范围内执行 $name；需用户确认，只修改本机科研库。',
      operations: _operations(name), targetTypes: {type}, affectsTypes: {type},
      parameterSchema: {'type': 'object', 'properties': properties,
        'required': required, 'additionalProperties': false},
    ), (ctx) async {
      final params = ctx.call.request.parameters;
      final ref = _selected(ctx, type, params[idParameter] as String);
      final runtime = await ctx.runtime<ResearchRuntime>();
      final store = runtime.store.scoped(ref.nativeProjectId!);
      ctx.call.cancellation.throwIfCancelled();
      await store.write(() {
        runtime.requireCurrent(ref);
        ctx.call.checkBeforeEffect();
        apply(store,params);
      });
      final session = await runtime.openScopeSession();
      try {
        final current = await session.resolve(ObjectRef(moduleId: 'research',
          objectType: type, objectId: ref.objectId, nativeProjectId: ref.nativeProjectId));
        return ToolCallResult(status: ToolCallStatus.succeeded,
          summary: '已执行 $name', objectRefs: [current!.ref],
          changes: [if (current.ref != ref) ObjectChange(current.ref, ChangeOp.upsert)]);
      } finally { await session.dispose(); }
    });
  }
  registrar.write(WriteToolSpec(
    name:'save_note', description:'为选中的科研文档新增阅读批注；需确认，只修改本机库。',
    operations:_operations('save_note'),
    targetTypes:{'document'}, createsTypes:{'note'},
    parameterSchema:{'type':'object','properties':{
      'document_id':{'type':'string'},'locator':{'type':'string'},
      'text':{'type':'string','minLength':1,'maxLength':4000},
    },'required':['document_id','locator','text'],'additionalProperties':false},
  ), (ctx) async {
    final params = ctx.call.request.parameters;
    final ref = _selected(ctx,'document',params['document_id'] as String);
    final runtime = await ctx.runtime<ResearchRuntime>();
    final store = runtime.store.scoped(ref.nativeProjectId!);
    late String noteId;
    ctx.call.cancellation.throwIfCancelled();
    await store.write(() {
      runtime.requireCurrent(ref);
      ctx.call.checkBeforeEffect();
      final before = {for (final n in store.notes(ref.objectId)) n.id};
      store.saveNote(ref.objectId, params['locator'] as String, params['text'] as String);
      noteId = store.notes(ref.objectId).singleWhere((n) => !before.contains(n.id)).id;
      ModuleChangeLog.record(store.db, ObjectRef(moduleId:'research',objectType:'note',
        objectId:noteId,nativeProjectId:ref.nativeProjectId), ChangeOp.upsert,
        summary: params['text'] as String);
    });
    final session = await runtime.openScopeSession();
    try {
      final note = (await session.resolve(ObjectRef(moduleId:'research',objectType:'note',
        objectId:noteId,nativeProjectId:ref.nativeProjectId)))!.ref;
      return ToolCallResult(status:ToolCallStatus.succeeded,summary:'已保存批注',
        objectRefs:[note],changes:[ObjectChange(note,ChangeOp.upsert)]);
    } finally {await session.dispose();}
  });
  write('accept_run', 'run', 'run_id', {'run_id': {'type':'string'}},
    ['run_id'], (s,p) => s.acceptRun(p['run_id'] as String));
  write('assess_run', 'run', 'run_id', {
    'run_id': {'type':'string'}, 'result': {'type':'string'},
    'discriminating': {'type':'boolean'}, 'reason': {'type':'string'},
  }, ['run_id','result','discriminating','reason'], (s,p) => s.assessRun(
    p['run_id'] as String, result: p['result'] as String,
    discriminating: p['discriminating'] as bool, reason: p['reason'] as String));
  registrar.write(WriteToolSpec(
    name: 'add_outline', description: '将选中的科研条目或运行作为证据添加到提纲；需确认，只修改本机库。',
    operations: _operations('add_outline'), targetTypes: {'entry','run'}, createsTypes: {'outline','section'},
    parameterSchema: {'type':'object', 'properties': {
      'evidence_type': {'type':'string','enum':['entry','run']},
      'evidence_id': {'type':'string'}, 'heading': {'type':'string','minLength':1,'maxLength':1000},
    }, 'required':['evidence_type','evidence_id','heading'], 'additionalProperties':false},
  ), (ctx) async {
    final params = ctx.call.request.parameters;
    final ref = _selected(ctx, params['evidence_type'] as String, params['evidence_id'] as String);
    final runtime = await ctx.runtime<ResearchRuntime>();
    final store = runtime.store.scoped(ref.nativeProjectId!);
    late List<ObjectRef> changed;
    ctx.call.cancellation.throwIfCancelled();
    await store.write(() {
      runtime.requireCurrent(ref);
      ctx.call.checkBeforeEffect();
      final oldSections = {for (final s in store.sections(ref.nativeProjectId!)) s.id};
      final oldLinks = {for (final r in store.db.select('SELECT id FROM outline WHERE project_id=?', [ref.nativeProjectId])) r['id']};
      store.addOutline(ref.nativeProjectId!, params['heading'] as String, ref.objectId);
      final section = store.sections(ref.nativeProjectId!).firstWhere((s) => s.heading == (params['heading'] as String).trim());
      final links = store.db.select('SELECT id FROM outline WHERE section_id=? AND evidence_id=?', [section.id, ref.objectId]);
      changed = [
        if (!oldSections.contains(section.id)) ObjectRef(moduleId:'research', objectType:'section', objectId:section.id, nativeProjectId:ref.nativeProjectId),
        for (final link in links) if (!oldLinks.contains(link['id'])) ObjectRef(moduleId:'research', objectType:'outline', objectId:link['id'] as String, nativeProjectId:ref.nativeProjectId),
      ];
    });
    final session = await runtime.openScopeSession();
    try {
      final views = [for (final r in changed) (await session.resolve(r))!.ref];
      return ToolCallResult(status:ToolCallStatus.succeeded, summary:'已添加提纲',
        objectRefs:views, changes:[for (final r in views) ObjectChange(r,ChangeOp.upsert)]);
    } finally { await session.dispose(); }
  });

}

ObjectRef _selected(ModuleToolContext ctx, String type, String id) {
  final ref = ctx.call.resolvedScope.objects.where((r) =>
    r.moduleId == 'research' && r.objectType == type && r.objectId == id).firstOrNull;
  if (ref == null) throw StateError('Object outside scope');
  return ref;
}

Map<String,Object?> _document(ResearchRuntime runtime, ObjectRef ref, ObjectView view) {
  final document = runtime.store.documents(ref.nativeProjectId!).where((d) => d.id == ref.objectId).firstOrNull;
  if (document == null) {
    final rows = runtime.store.db.select(
      'SELECT d.file_name,length(d.bytes) AS byte_count FROM rk_documents d JOIN canonical_object_map m ON m.object_key=d.object_key '
      "WHERE m.local_object_id=? AND m.local_project_id=? AND m.object_type='document' AND d.deleted=0", [ref.objectId,ref.nativeProjectId]);
    return {'relativePath':rows.single['file_name'],'byteCount':rows.single['byte_count'],'contentDigest':view.ref.contentDigest};
  }
  final file = File(document.absolutePath);
  final data = <String,Object?>{'relativePath':document.relativePath,'contentDigest':view.ref.contentDigest,'missing':!file.existsSync()};
  if (!file.existsSync()) return data;
  // Bind returned text to the same bytes as the selected digest, rather than
  // reading a fresh unverified prefix after scope resolution.
  final bytes = file.readAsBytesSync();
  if (sha256.convert(bytes).toString() != view.ref.contentDigest) {
    throw StateError('Document changed during reading');
  }
  data['byteCount'] = bytes.length;
  if (const ['md','txt','csv','json'].any((ext) => document.relativePath.toLowerCase().endsWith('.$ext'))) {
    data['text'] = utf8.decode(bytes.take(16000).toList(),allowMalformed:true);
    data['truncated'] = bytes.length > 16000;
  }
  return data;
}

List<String> _operations(String name) => [
  for (final op in researchCoverage.operations)
    if (op.tools.contains('research.$name')) op.id,
];
