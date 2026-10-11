import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';

import 'research_module.dart';
import 'core/models.dart';
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
        (r) =>
            r.moduleId == 'research' &&
            const {'project', 'document', 'entry'}.contains(r.objectType),
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
  registrar.read(
    ToolSpec(
      name: 'read_object',
      description: '读取本次范围内的科研项目、文档、条目、运行、提纲、段落、任务或卡片。',
      operations: _operations('read_object'),
      parameterSchema: {
        'type': 'object',
        'properties': {
          'type': {
            'type': 'string',
            'enum': [
              'project',
              'document',
              'entry',
              'outline',
              'section',
              'task',
              'run',
              'card',
              'note',
            ],
          },
          'id': {'type': 'string'},
        },
        'required': ['type', 'id'],
        'additionalProperties': false,
      },
    ),
    (ctx) async {
      final ref = _selected(
        ctx,
        ctx.call.request.parameters['type'] as String,
        ctx.call.request.parameters['id'] as String,
      );
      final runtime = await ctx.runtime<ResearchRuntime>();
      final session = await runtime.openScopeSession();
      try {
        final view = await session.resolve(ref);
        if (view == null) throw StateError('Object changed');
        runtime.requireCurrent(view.ref);
        final project = ref.nativeProjectId!;
        final data = switch (ref.objectType) {
          'project' => () {
            final p = runtime.store.projects().firstWhere(
              (p) => p.id == ref.objectId,
            );
            return <String, Object?>{
              'title': p.title,
              'question': p.question,
              'nextStep': p.nextStep,
            };
          }(),
          'entry' => Map<String, Object?>.from(
            runtime.store
                .entries(project)
                .firstWhere((e) => e.id == ref.objectId)
                .data,
          ),
          'run' => Map<String, Object?>.from(
            runtime.store
                .runs(project)
                .firstWhere((r) => r.id == ref.objectId)
                .data,
          ),
          'task' => Map<String, Object?>.from(
            runtime.store
                .taskRevision(ref.objectId, int.parse(view.ref.revisionRef!))!
                .spec,
          ),
          'document' => _document(runtime, ref, view),
          'outline' || 'section' => Map<String, Object?>.from(
            runtime.store.db.select(
              'SELECT * FROM ${ref.objectType == 'outline' ? 'outline' : 'sections'} WHERE id=? AND project_id=?',
              [ref.objectId, project],
            ).single,
          ),
          'note' => Map<String, Object?>.from(
            runtime.store.db.select(
              'SELECT n.* FROM notes n JOIN documents d ON d.id=n.document_id WHERE n.id=? AND d.project_id=?',
              [ref.objectId, project],
            ).single,
          ),
          'card' => () {
            final rows = runtime.store.db.select(
              'SELECT v.envelope FROM rk_revisions v JOIN canonical_object_map m ON m.object_key=v.object_key '
              'WHERE m.local_object_id=? AND m.local_project_id=? AND v.revision_id=?',
              [ref.objectId, project, view.ref.revisionRef],
            );
            return Map<String, Object?>.from(
              jsonDecode(rows.single['envelope'] as String) as Map,
            );
          }(),
          _ => throw StateError('Unsupported object type'),
        };
        if (ref.objectType == 'project' || ref.objectType == 'note') {
          data['contentDigest'] = view.ref.contentDigest;
        }
        if (ref.objectType == 'task') {
          data['revision'] = int.parse(view.ref.revisionRef!);
        }
        if (ref.objectType == 'section') {
          data['deleteDigest'] = sectionDeleteDigest(
            runtime.store,
            project,
            ref.objectId,
          )!;
        }
        return ToolCallResult(
          status: ToolCallStatus.succeeded,
          summary: '读取 ${view.title}',
          data: {'object': data},
          objectRefs: [view.ref],
        );
      } finally {
        await session.dispose();
      }
    },
  );
  registrar.read(
    ToolSpec(
      name: 'relations',
      description: '读取本次范围内科研对象之间的任务运行、提纲证据和段落关系；不扩展资料范围。',
      operations: _operations('relations'),
    ),
    (ctx) async {
      final runtime = await ctx.runtime<ResearchRuntime>();
      final refs = ctx.call.resolvedScope.objects
          .where((r) => r.moduleId == 'research')
          .toList();
      for (final ref in refs) {
        runtime.requireCurrent(ref);
      }
      final rows = <Map<String, Object?>>[];
      void link(
        ObjectRef from,
        String type,
        String? id,
        String relation, {
        String? revision,
      }) {
        if (id == null) return;
        for (final target in refs.where(
          (r) =>
              r.objectType == type &&
              r.objectId == id &&
              r.nativeProjectId == from.nativeProjectId &&
              (revision == null || r.revisionRef == revision),
        )) {
          rows.add({
            'relation': relation,
            'from': from.toJson(),
            'to': target.toJson(),
          });
        }
      }

      for (final ref in refs) {
        if (ref.objectType != 'project' &&
            ref.objectType != 'run' &&
            ref.objectType != 'note') {
          link(
            ref,
            'project',
            ref.nativeProjectId,
            '${ref.objectType}_project',
          );
        }
        if (ref.objectType == 'run') {
          for (final row in runtime.store.db.select(
            'SELECT task_id,task_revision FROM runs WHERE id=?',
            [ref.objectId],
          )) {
            link(
              ref,
              'task',
              row['task_id'] as String,
              'run_task',
              revision: '${row['task_revision']}',
            );
          }
        } else if (ref.objectType == 'note') {
          for (final row in runtime.store.db.select(
            'SELECT document_id FROM notes WHERE id=?',
            [ref.objectId],
          )) {
            link(
              ref,
              'document',
              row['document_id'] as String,
              'note_document',
            );
          }
        } else if (ref.objectType == 'outline') {
          for (final row in runtime.store.db.select(
            'SELECT evidence_id,section_id FROM outline WHERE id=? AND project_id=?',
            [ref.objectId, ref.nativeProjectId],
          )) {
            link(
              ref,
              'section',
              row['section_id'] as String?,
              'outline_section',
            );
            for (final type in ['entry', 'run', 'note']) {
              link(
                ref,
                type,
                row['evidence_id'] as String?,
                'outline_evidence',
              );
            }
          }
        }
      }
      return ToolCallResult(
        status: ToolCallStatus.succeeded,
        summary: '找到 ${rows.length} 条范围内关系',
        data: {'relations': rows},
        objectRefs: refs,
      );
    },
  );
  registrar.read(
    ToolSpec(
      name: 'outline_rows',
      description: '读取选定科研项目的提纲证据行，按段落顺序排列。只读取本机科研库，不修改数据，也不发送到设备外。',
      operations: _operations('outline_rows'),
      parameterSchema: {
        'type': 'object',
        'properties': {
          'project_id': {'type': 'string'},
        },
        'required': ['project_id'],
        'additionalProperties': false,
      },
    ),
    (ctx) async {
      final ref = _selected(
        ctx,
        'project',
        ctx.call.request.parameters['project_id'] as String,
      );
      final runtime = await ctx.runtime<ResearchRuntime>();
      runtime.requireCurrent(ref);
      final rows = [
        for (final row
            in runtime.store.scoped(ref.nativeProjectId!).outline(ref.objectId))
          Map<String, Object?>.from(row),
      ];
      return ToolCallResult(
        status: ToolCallStatus.succeeded,
        summary: '找到 ${rows.length} 条提纲证据',
        data: {'outline': rows},
        objectRefs: [ref],
      );
    },
  );
  registrar.read(
    ToolSpec(
      name: 'outline_sections',
      description: '读取选定科研项目的提纲段落，并返回新增/移动用的 orderDigest 和各段落删除用的 deleteDigest。只读取本机科研库，不修改数据，也不发送到设备外。',
      operations: _operations('outline_sections'),
      parameterSchema: {
        'type': 'object',
        'properties': {
          'project_id': {'type': 'string'},
        },
        'required': ['project_id'],
        'additionalProperties': false,
      },
    ),
    (ctx) async {
      final ref = _selected(
        ctx,
        'project',
        ctx.call.request.parameters['project_id'] as String,
      );
      final runtime = await ctx.runtime<ResearchRuntime>();
      runtime.requireCurrent(ref);
      final store = runtime.store.scoped(ref.nativeProjectId!);
      return ToolCallResult(
        status: ToolCallStatus.succeeded,
        summary: '找到 ${_sectionRows(store, ref.objectId).length} 个提纲段落',
        data: {
          'sections': [
            for (final section in _sectionRows(store, ref.objectId))
              {
                ...section,
                'deleteDigest': sectionDeleteDigest(
                  store,
                  ref.objectId,
                  section['id'] as String,
                )!,
              },
          ],
          'orderDigest': _orderDigest(store, ref.objectId),
        },
        objectRefs: [ref],
      );
    },
  );

  void write(
    String name,
    String type,
    String idParameter,
    Map<String, Object?> properties,
    List<String> required,
    void Function(WorkbenchStore, Map<String, Object?>) apply,
  ) {
    registrar.write(
      WriteToolSpec(
        name: name,
        description: '在已选择的科研范围内执行 $name；需用户确认，只修改本机科研库。',
        operations: _operations(name),
        targetTypes: {type},
        affectsTypes: {type},
        parameterSchema: {
          'type': 'object',
          'properties': properties,
          'required': required,
          'additionalProperties': false,
        },
      ),
      (ctx) async {
        final params = ctx.call.request.parameters;
        final ref = _selected(ctx, type, params[idParameter] as String);
        final runtime = await ctx.runtime<ResearchRuntime>();
        final store = runtime.store.scoped(ref.nativeProjectId!);
        ctx.call.cancellation.throwIfCancelled();
        await store.write(() {
          runtime.requireCurrent(ref);
          ctx.call.checkBeforeEffect();
          apply(store, params);
        });
        final session = await runtime.openScopeSession();
        try {
          final current = await session.resolve(
            ObjectRef(
              moduleId: 'research',
              objectType: type,
              objectId: ref.objectId,
              nativeProjectId: ref.nativeProjectId,
            ),
          );
          return ToolCallResult(
            status: ToolCallStatus.succeeded,
            summary: '已执行 $name',
            objectRefs: [current!.ref],
            changes: [
              if (current.ref != ref)
                ObjectChange(current.ref, ChangeOp.upsert),
            ],
          );
        } finally {
          await session.dispose();
        }
      },
    );
  }

  registrar.write(
    WriteToolSpec(
      name: 'save_note',
      description: '为选中的科研文档新增阅读批注；需确认，只修改本机库。',
      operations: _operations('save_note'),
      targetTypes: {'document'},
      createsTypes: {'note'},
      parameterSchema: {
        'type': 'object',
        'properties': {
          'document_id': {'type': 'string'},
          'locator': {'type': 'string'},
          'text': {'type': 'string', 'minLength': 1, 'maxLength': 4000},
        },
        'required': ['document_id', 'locator', 'text'],
        'additionalProperties': false,
      },
    ),
    (ctx) async {
      final params = ctx.call.request.parameters;
      final ref = _selected(ctx, 'document', params['document_id'] as String);
      final runtime = await ctx.runtime<ResearchRuntime>();
      final store = runtime.store.scoped(ref.nativeProjectId!);
      late String noteId;
      ctx.call.cancellation.throwIfCancelled();
      await store.write(() {
        runtime.requireCurrent(ref);
        ctx.call.checkBeforeEffect();
        final before = {for (final n in store.notes(ref.objectId)) n.id};
        store.saveNote(
          ref.objectId,
          params['locator'] as String,
          params['text'] as String,
        );
        noteId = store
            .notes(ref.objectId)
            .singleWhere((n) => !before.contains(n.id))
            .id;
        ModuleChangeLog.record(
          store.db,
          ObjectRef(
            moduleId: 'research',
            objectType: 'note',
            objectId: noteId,
            nativeProjectId: ref.nativeProjectId,
          ),
          ChangeOp.upsert,
          summary: params['text'] as String,
        );
      });
      final session = await runtime.openScopeSession();
      try {
        final note = (await session.resolve(
          ObjectRef(
            moduleId: 'research',
            objectType: 'note',
            objectId: noteId,
            nativeProjectId: ref.nativeProjectId,
          ),
        ))!.ref;
        return ToolCallResult(
          status: ToolCallStatus.succeeded,
          summary: '已保存批注',
          objectRefs: [note],
          changes: [ObjectChange(note, ChangeOp.upsert)],
        );
      } finally {
        await session.dispose();
      }
    },
  );
  write(
    'accept_run',
    'run',
    'run_id',
    {
      'run_id': {'type': 'string'},
    },
    ['run_id'],
    (s, p) => s.acceptRun(p['run_id'] as String),
  );
  write(
    'assess_run',
    'run',
    'run_id',
    {
      'run_id': {'type': 'string'},
      'result': {'type': 'string'},
      'discriminating': {'type': 'boolean'},
      'reason': {'type': 'string'},
    },
    ['run_id', 'result', 'discriminating', 'reason'],
    (s, p) => s.assessRun(
      p['run_id'] as String,
      result: p['result'] as String,
      discriminating: p['discriminating'] as bool,
      reason: p['reason'] as String,
    ),
  );
  registrar.write(
    WriteToolSpec(
      name: 'add_outline',
      description: '将选中的科研条目或运行作为证据添加到提纲；需确认，只修改本机库。',
      operations: _operations('add_outline'),
      targetTypes: {'entry', 'run'},
      createsTypes: {'outline', 'section'},
      parameterSchema: {
        'type': 'object',
        'properties': {
          'evidence_type': {
            'type': 'string',
            'enum': ['entry', 'run'],
          },
          'evidence_id': {'type': 'string'},
          'heading': {'type': 'string', 'minLength': 1, 'maxLength': 1000},
        },
        'required': ['evidence_type', 'evidence_id', 'heading'],
        'additionalProperties': false,
      },
    ),
    (ctx) async {
      final params = ctx.call.request.parameters;
      final ref = _selected(
        ctx,
        params['evidence_type'] as String,
        params['evidence_id'] as String,
      );
      final runtime = await ctx.runtime<ResearchRuntime>();
      final store = runtime.store.scoped(ref.nativeProjectId!);
      ctx.call.cancellation.throwIfCancelled();
      return store.write(() {
        runtime.requireCurrent(ref);
        store.requireOutlineEvidence(
          ref.nativeProjectId!,
          ref.objectId,
          evidenceType: ref.objectType,
        );
        ctx.call.checkBeforeEffect();
        final oldSections = {
          for (final s in store.sections(ref.nativeProjectId!)) s.id,
        };
        final oldLinks = {
          for (final r in store.db.select(
            'SELECT id FROM outline WHERE project_id=?',
            [ref.nativeProjectId],
          ))
            r['id'],
        };
        store.addOutline(
          ref.nativeProjectId!,
          params['heading'] as String,
          ref.objectId,
          evidenceType: ref.objectType,
        );
        final section = store
            .sections(ref.nativeProjectId!)
            .firstWhere(
              (s) => s.heading == (params['heading'] as String).trim(),
            );
        final links = store.db.select(
          'SELECT id FROM outline WHERE section_id=? AND evidence_id=?',
          [section.id, ref.objectId],
        );
        final changed = [
          if (!oldSections.contains(section.id))
            ObjectRef(
              moduleId: 'research',
              objectType: 'section',
              objectId: section.id,
              nativeProjectId: ref.nativeProjectId,
            ),
          for (final link in links)
            if (!oldLinks.contains(link['id']))
              ObjectRef(
                moduleId: 'research',
                objectType: 'outline',
                objectId: link['id'] as String,
                nativeProjectId: ref.nativeProjectId,
              ),
        ];
        return _report(runtime, '已添加提纲', [
          for (final ref in changed) ObjectChange(ref, ChangeOp.upsert),
        ]);
      });
    },
  );
  registrar.write(
    WriteToolSpec(
      name: 'add_section',
      description:
          '在选定科研项目的提纲末尾新增段落；需确认，只修改本机库。'
          '确认前展示将新建的标题和层级，不按标题匹配已有段落；已有同名段落则拒绝，不改已有段落。'
          'expected_digest 必须是确认时 research.outline_sections 返回的 orderDigest，执行时在同一事务核对，不一致则拒绝。',
      operations: _operations('add_section'),
      targetTypes: {'project'},
      createsTypes: {'section'},
      parameterSchema: {
        'type': 'object',
        'properties': {
          'project_id': {'type': 'string'},
          'heading': {'type': 'string', 'minLength': 1, 'maxLength': 1000},
          'level': {'type': 'integer', 'minimum': 1, 'maximum': 3},
          'expected_digest': {'type': 'string', 'minLength': 1},
        },
        'required': ['project_id', 'heading', 'level', 'expected_digest'],
        'additionalProperties': false,
      },
    ),
    (ctx) async {
      final params = ctx.call.request.parameters;
      final ref = _selected(ctx, 'project', params['project_id'] as String);
      return _outlineWrite(
        ctx,
        [ref],
        (store) => _orderDigest(store, ref.objectId),
        (runtime, store) {
          final createdId = store
              .addSection(
                ref.objectId,
                params['heading'] as String,
                level: params['level'] as int,
              )
              .id;
          return _report(runtime, '已新增提纲段落', [
            ObjectChange(
              ObjectRef(
                moduleId: 'research',
                objectType: 'section',
                objectId: createdId,
                nativeProjectId: ref.nativeProjectId,
              ),
              ChangeOp.upsert,
            ),
          ]);
        },
        beforeEffect: (store) => _refuseSameHeading(
          store,
          ref.objectId,
          params['heading'] as String,
        ),
      );
    },
  );
  registrar.write(
    WriteToolSpec(
      name: 'update_section',
      description:
          '按 section_id 修改选定提纲段落的标题、层级、论证和支持程度；需确认，只修改本机库。'
          '不按标题寻找段落。把标题改成另一段落的已有标题则拒绝。'
          'expected_digest 必须是确认时该段落的 contentDigest，执行时在同一事务核对，不一致则拒绝。',
      operations: _operations('update_section'),
      targetTypes: {'section'},
      affectsTypes: {'section', 'outline'},
      parameterSchema: {
        'type': 'object',
        'properties': {
          'section_id': {'type': 'string'},
          'heading': {'type': 'string', 'minLength': 1, 'maxLength': 1000},
          'level': {'type': 'integer', 'minimum': 1, 'maximum': 3},
          'argument': {'type': 'string', 'maxLength': 4000},
          'support': {
            'type': 'string',
            'enum': ['unassessed', 'supported', 'partial', 'weak', 'contested'],
          },
          'expected_digest': {'type': 'string', 'minLength': 1},
        },
        'required': [
          'section_id',
          'heading',
          'level',
          'argument',
          'support',
          'expected_digest',
        ],
        'additionalProperties': false,
      },
    ),
    (ctx) async {
      final params = ctx.call.request.parameters;
      final ref = _selected(ctx, 'section', params['section_id'] as String);
      return _outlineWrite(
        ctx,
        [ref],
        (store) =>
            _rowDigestOf(store, 'sections', ref.nativeProjectId!, ref.objectId),
        (runtime, store) {
          final before = {
            for (final row in store.db.select(
              'SELECT * FROM outline WHERE section_id=?',
              [ref.objectId],
            ))
              row['id'] as String: _rowDigest(Map<String, Object?>.from(row)),
          };
          store.updateSection(
            ref.objectId,
            heading: params['heading'] as String,
            level: params['level'] as int,
            argument: params['argument'] as String,
            support: params['support'] as String,
          );
          final changedLinks = [
            for (final row in store.db.select(
              'SELECT * FROM outline WHERE section_id=?',
              [ref.objectId],
            ))
              if (before[row['id']] !=
                  _rowDigest(Map<String, Object?>.from(row)))
                row['id'] as String,
          ];
          return _report(runtime, '已修改提纲段落', [
            ObjectChange(ref, ChangeOp.upsert),
            for (final id in changedLinks)
              ObjectChange(
                ObjectRef(
                  moduleId: 'research',
                  objectType: 'outline',
                  objectId: id,
                  nativeProjectId: ref.nativeProjectId,
                ),
                ChangeOp.upsert,
              ),
          ]);
        },
        beforeEffect: (store) => _refuseSameHeading(
          store,
          ref.nativeProjectId!,
          params['heading'] as String,
          exceptId: ref.objectId,
        ),
      );
    },
  );
  registrar.write(
    WriteToolSpec(
      name: 'move_section',
      description:
          '将选定提纲段落与相邻段落交换位置；需确认，只修改本机库。'
          'expected_digest 必须是确认时 research.outline_sections 返回的 orderDigest，执行时在同一事务核对，不一致则拒绝。',
      operations: _operations('move_section'),
      targetTypes: {'section'},
      affectsTypes: {'section'},
      parameterSchema: {
        'type': 'object',
        'properties': {
          'section_id': {'type': 'string'},
          'delta': {
            'type': 'integer',
            'enum': [-1, 1],
          },
          'expected_digest': {'type': 'string', 'minLength': 1},
        },
        'required': ['section_id', 'delta', 'expected_digest'],
        'additionalProperties': false,
      },
    ),
    (ctx) async {
      final params = ctx.call.request.parameters;
      final ref = _selected(ctx, 'section', params['section_id'] as String);
      return _outlineWrite(
        ctx,
        [ref],
        (store) => _orderDigest(store, ref.nativeProjectId!),
        (runtime, store) {
          final before = {
            for (final section in store.sections(ref.nativeProjectId!))
              section.id: section.position,
          };
          store.moveSection(ref.objectId, params['delta'] as int);
          final moved = [
            for (final section in store.sections(ref.nativeProjectId!))
              if (before[section.id] != section.position) section.id,
          ];
          final summary = moved.isEmpty
              ? '已在${params['delta'] == -1 ? '首位' : '末位'}，位置未变化'
              : '已移动提纲段落';
          return _report(runtime, summary, [
            for (final id in moved)
              ObjectChange(
                ObjectRef(
                  moduleId: 'research',
                  objectType: 'section',
                  objectId: id,
                  nativeProjectId: ref.nativeProjectId,
                ),
                ChangeOp.upsert,
              ),
          ]);
        },
      );
    },
  );
  registrar.write(
    WriteToolSpec(
      name: 'delete_section',
      description:
          '删除选定提纲段落及其证据链接，证据本身保留；需确认，只修改本机库。'
          'expected_digest 必须是确认时 research.read_object 或 research.outline_sections 返回的该段落 deleteDigest'
          '（含段落及全部级联引用快照），执行时在同一事务核对，引用新增、移除或修改均拒绝旧确认。',
      operations: _operations('delete_section'),
      targetTypes: {'section'},
      deletesTypes: {'section', 'outline'},
      parameterSchema: {
        'type': 'object',
        'properties': {
          'section_id': {'type': 'string'},
          'expected_digest': {'type': 'string', 'minLength': 1},
        },
        'required': ['section_id', 'expected_digest'],
        'additionalProperties': false,
      },
    ),
    (ctx) async {
      final ref = _selected(
        ctx,
        'section',
        ctx.call.request.parameters['section_id'] as String,
      );
      return _outlineWrite(
        ctx,
        [ref],
        (store) =>
            sectionDeleteDigest(store, ref.nativeProjectId!, ref.objectId)!,
        (runtime, store) {
          final links = [
            for (final row in store.db.select(
              'SELECT * FROM outline WHERE section_id=?',
              [ref.objectId],
            ))
              ObjectRef(
                moduleId: 'research',
                objectType: 'outline',
                objectId: row['id'] as String,
                nativeProjectId: ref.nativeProjectId,
                contentDigest: _rowDigest(Map<String, Object?>.from(row)),
              ),
          ];
          store.deleteSection(ref.objectId);
          return _report(runtime, '已删除提纲段落', [
            ObjectChange(ref, ChangeOp.delete),
            for (final link in links) ObjectChange(link, ChangeOp.delete),
          ]);
        },
      );
    },
  );
  registrar.write(
    WriteToolSpec(
      name: 'cite',
      description:
          '把选定的科研条目、已接受运行或阅读批注引用到选定段落；需确认，只修改本机库。'
          'expected_digest 必须是确认时该段落的 contentDigest，执行时在同一事务核对，不一致则拒绝。',
      operations: _operations('cite'),
      targetTypes: {'section', 'entry', 'run', 'note'},
      createsTypes: {'outline'},
      parameterSchema: {
        'type': 'object',
        'properties': {
          'section_id': {'type': 'string'},
          'evidence_type': {
            'type': 'string',
            'enum': ['entry', 'run', 'note'],
          },
          'evidence_id': {'type': 'string'},
          'expected_digest': {'type': 'string', 'minLength': 1},
        },
        'required': [
          'section_id',
          'evidence_type',
          'evidence_id',
          'expected_digest',
        ],
        'additionalProperties': false,
      },
    ),
    (ctx) async {
      final params = ctx.call.request.parameters;
      final section = _selected(ctx, 'section', params['section_id'] as String);
      final evidence = _selected(
        ctx,
        params['evidence_type'] as String,
        params['evidence_id'] as String,
      );
      return _outlineWrite(
        ctx,
        [section, evidence],
        (store) => _rowDigestOf(
          store,
          'sections',
          section.nativeProjectId!,
          section.objectId,
        ),
        (runtime, store) {
          final before = {
            for (final row in store.db.select(
              'SELECT id FROM outline WHERE project_id=?',
              [section.nativeProjectId],
            ))
              row['id'] as String,
          };
          store.cite(
            section.objectId,
            evidence.objectId,
            evidenceType: evidence.objectType,
          );
          final created = [
            for (final row in store.db.select(
              'SELECT id FROM outline WHERE section_id=? AND evidence_id=?',
              [section.objectId, evidence.objectId],
            ))
              if (!before.contains(row['id'])) row['id'] as String,
          ];
          return _report(runtime, created.isEmpty ? '提纲引用未变化' : '已引用到提纲', [
            for (final id in created)
              ObjectChange(
                ObjectRef(
                  moduleId: 'research',
                  objectType: 'outline',
                  objectId: id,
                  nativeProjectId: section.nativeProjectId,
                ),
                ChangeOp.upsert,
              ),
          ]);
        },
        beforeEffect: (store) => store.requireOutlineEvidence(
          section.nativeProjectId!,
          evidence.objectId,
          evidenceType: evidence.objectType,
        ),
      );
    },
  );
  registrar.write(
    WriteToolSpec(
      name: 'remove_outline',
      description:
          '删除选定的提纲证据链接，证据本身保留；需确认，只修改本机库。'
          'expected_digest 必须是确认时该链接的 contentDigest，执行时在同一事务核对，不一致则拒绝。',
      operations: _operations('remove_outline'),
      targetTypes: {'outline'},
      deletesTypes: {'outline'},
      parameterSchema: {
        'type': 'object',
        'properties': {
          'outline_id': {'type': 'string'},
          'expected_digest': {'type': 'string', 'minLength': 1},
        },
        'required': ['outline_id', 'expected_digest'],
        'additionalProperties': false,
      },
    ),
    (ctx) async {
      final ref = _selected(
        ctx,
        'outline',
        ctx.call.request.parameters['outline_id'] as String,
      );
      return _outlineWrite(
        ctx,
        [ref],
        (store) =>
            _rowDigestOf(store, 'outline', ref.nativeProjectId!, ref.objectId),
        (runtime, store) {
          store.removeOutline(ref.objectId);
          return _report(runtime, '已移除提纲引用', [
            ObjectChange(ref, ChangeOp.delete),
          ]);
        },
      );
    },
  );
  registrar.read(
    ToolSpec(
      name: 'list_notes',
      description: '读取选定科研文档的阅读批注，每条带 digest。只读取本机科研库，不修改数据，也不发送到设备外。',
      operations: _operations('list_notes'),
      parameterSchema: {
        'type': 'object',
        'properties': {
          'document_id': {'type': 'string'},
        },
        'required': ['document_id'],
        'additionalProperties': false,
      },
    ),
    (ctx) async {
      final ref = _selected(
        ctx,
        'document',
        ctx.call.request.parameters['document_id'] as String,
      );
      final runtime = await ctx.runtime<ResearchRuntime>();
      runtime.requireCurrent(ref);
      final store = runtime.store.scoped(ref.nativeProjectId!);
      final notes = [
        for (final note in store.notes(ref.objectId))
          {
            'id': note.id,
            'documentId': note.documentId,
            'locator': note.locator,
            'text': note.text,
            'pageNumber': note.pageNumber,
            'quote': note.quote,
            'evidenceKind': note.evidenceKind,
            'doesNotSupport': note.doesNotSupport,
            'entryId': note.entryId,
            'digest': _noteDigest(store, ref.nativeProjectId!, note.id),
          },
      ];
      return ToolCallResult(
        status: ToolCallStatus.succeeded,
        summary: '找到 ${notes.length} 条批注',
        data: {'notes': notes},
        objectRefs: [ref],
      );
    },
  );
  registrar.read(
    ToolSpec(
      name: 'list_bindings',
      description:
          '读取选定科研项目的文献绑定，每条带 digest，可按 document_id 过滤。只读取本机科研库，不修改数据，也不发送到设备外。',
      operations: _operations('list_bindings'),
      parameterSchema: {
        'type': 'object',
        'properties': {
          'project_id': {'type': 'string'},
          'document_id': {'type': 'string'},
        },
        'required': ['project_id'],
        'additionalProperties': false,
      },
    ),
    (ctx) async {
      final params = ctx.call.request.parameters;
      final ref = _selected(ctx, 'project', params['project_id'] as String);
      final runtime = await ctx.runtime<ResearchRuntime>();
      runtime.requireCurrent(ref);
      final bindings = [
        for (final b
            in runtime.store
                .scoped(ref.nativeProjectId!)
                .bindings(ref.objectId))
          if (params['document_id'] == null ||
              params['document_id'] == b.documentId)
            {..._bindingJson(b), 'digest': _bindingDigest(b)},
      ];
      return ToolCallResult(
        status: ToolCallStatus.succeeded,
        summary: '找到 ${bindings.length} 条绑定',
        data: {'bindings': bindings},
        objectRefs: [ref],
      );
    },
  );
  registrar.write(
    WriteToolSpec(
      name: 'update_project',
      description:
          '修改选定科研项目的研究问题和下一步；需确认，只修改本机库。'
          'expected_digest 必须是确认时 research.read_object 返回的项目 contentDigest，执行时在同一事务核对，不一致则拒绝。',
      operations: _operations('update_project'),
      targetTypes: {'project'},
      affectsTypes: {'project'},
      parameterSchema: {
        'type': 'object',
        'properties': {
          'project_id': {'type': 'string'},
          'question': {'type': 'string', 'maxLength': 4000},
          'next_step': {'type': 'string', 'maxLength': 4000},
          'expected_digest': {'type': 'string', 'minLength': 1},
        },
        'required': ['project_id', 'question', 'next_step', 'expected_digest'],
        'additionalProperties': false,
      },
    ),
    (ctx) async {
      final params = ctx.call.request.parameters;
      final ref = _selected(ctx, 'project', params['project_id'] as String);
      return _outlineWrite(
        ctx,
        [ref],
        (store) => _projectDigest(store, ref.objectId),
        (runtime, store) {
          store.saveProject(
            ref.objectId,
            question: params['question'] as String,
            nextStep: params['next_step'] as String,
          );
          return _report(runtime, '已更新项目', [
            ObjectChange(ref, ChangeOp.upsert),
          ]);
        },
      );
    },
  );
  registrar.write(
    WriteToolSpec(
      name: 'set_note_entry',
      description:
          '把选定阅读批注关联到选定研究条目，entry_id 为空则清除关联；需确认，只修改本机库。'
          '条目须在同一项目且已选定。expected_digest 必须是确认时该批注的 contentDigest，执行时在同一事务核对，不一致则拒绝。',
      operations: _operations('set_note_entry'),
      targetTypes: {'note', 'entry'},
      affectsTypes: {'note'},
      parameterSchema: {
        'type': 'object',
        'properties': {
          'note_id': {'type': 'string'},
          'entry_id': {
            'type': ['string', 'null'],
          },
          'expected_digest': {'type': 'string', 'minLength': 1},
        },
        'required': ['note_id', 'entry_id', 'expected_digest'],
        'additionalProperties': false,
      },
    ),
    (ctx) async {
      final params = ctx.call.request.parameters;
      final note = _selected(ctx, 'note', params['note_id'] as String);
      final entryId = params['entry_id'] as String?;
      final entry = entryId == null ? null : _selected(ctx, 'entry', entryId);
      return _outlineWrite(
        ctx,
        [note, ?entry],
        (store) => _noteDigest(store, note.nativeProjectId!, note.objectId),
        (runtime, store) {
          store.setNoteEntry(note.objectId, entryId);
          return _report(runtime, '已更新批注关联', [
            ObjectChange(note, ChangeOp.upsert),
          ]);
        },
      );
    },
  );
  const taskSpecProperties = <String, Object?>{
    'parameters': {'type': 'object', 'additionalProperties': true},
    'data_references': {
      'type': 'array',
      'items': {'type': 'string', 'maxLength': 1000},
      'maxItems': 50,
    },
    'code_reference': {'type': 'string', 'maxLength': 1000},
    'environment': {'type': 'string', 'maxLength': 2000},
    'expected_results': {
      'type': 'array',
      'items': {'type': 'string', 'maxLength': 1000},
      'maxItems': 50,
    },
  };
  registrar.write(
    WriteToolSpec(
      name: 'create_task',
      description:
          '在选定科研项目新建任务（第 1 版）；需确认，只修改本机库，不运行任何命令。'
          '任务规格只接受参数、数据引用、代码引用、环境和预期产物，不含命令与来源。',
      operations: _operations('create_task'),
      targetTypes: {'project'},
      createsTypes: {'task'},
      parameterSchema: {
        'type': 'object',
        'properties': {
          'project_id': {'type': 'string'},
          'title': {'type': 'string', 'minLength': 1, 'maxLength': 1000},
          'goal': {'type': 'string', 'minLength': 1, 'maxLength': 4000},
          ...taskSpecProperties,
        },
        'required': ['project_id', 'title', 'goal'],
        'additionalProperties': false,
      },
    ),
    (ctx) async {
      final params = ctx.call.request.parameters;
      final ref = _selected(ctx, 'project', params['project_id'] as String);
      late String taskId;
      // Validate before the write starts so a refusal is "failed", not "may have happened".
      final spec = _taskSpec(const {}, params);
      return _taskWrite(ctx, ref, (runtime, store) {
        taskId = store
            .saveTask(
              projectId: ref.objectId,
              title: params['title'] as String,
              goal: params['goal'] as String,
              spec: spec,
              expectedRevision: 0,
            )
            .id;
        return _report(runtime, '已新建任务', [
          ObjectChange(
            ObjectRef(
              moduleId: 'research',
              objectType: 'task',
              objectId: taskId,
              nativeProjectId: ref.nativeProjectId,
            ),
            ChangeOp.upsert,
          ),
        ]);
      });
    },
  );
  registrar.write(
    WriteToolSpec(
      name: 'revise_task',
      description:
          '为选定科研任务追加新修订；需确认，只修改本机库，不运行任何命令。'
          'expected_revision 必须等于选定任务的当前修订号，执行时在同一事务核对，已有更新修订则拒绝。'
          '未给出的规格字段沿用上一修订，命令与来源字段不可修改。',
      operations: _operations('revise_task'),
      targetTypes: {'task'},
      affectsTypes: {'task'},
      parameterSchema: {
        'type': 'object',
        'properties': {
          'task_id': {'type': 'string'},
          'expected_revision': {'type': 'integer', 'minimum': 1},
          'title': {'type': 'string', 'minLength': 1, 'maxLength': 1000},
          'goal': {'type': 'string', 'minLength': 1, 'maxLength': 4000},
          ...taskSpecProperties,
        },
        'required': ['task_id', 'expected_revision', 'title', 'goal'],
        'additionalProperties': false,
      },
    ),
    (ctx) async {
      final params = ctx.call.request.parameters;
      final ref = _selected(ctx, 'task', params['task_id'] as String);
      final expected = params['expected_revision'] as int;
      late Map<String, Object?> spec;
      return _outlineWrite(
        ctx,
        [ref],
        (store) => '${_latestRevision(store, ref.objectId)}',
        (runtime, store) {
          store.saveTask(
            id: ref.objectId,
            projectId: ref.nativeProjectId!,
            title: params['title'] as String,
            goal: params['goal'] as String,
            spec: spec,
            expectedRevision: expected,
          );
          return _report(runtime, '已追加任务修订', [
            ObjectChange(ref, ChangeOp.upsert),
          ]);
        },
        beforeEffect: (store) {
          if (ref.revisionRef != '$expected') {
            throw StateError('Task revision changed');
          }
          final previous = store.taskRevision(ref.objectId, expected);
          if (previous == null) throw StateError('Task revision changed');
          spec = _taskSpec(previous.spec, params);
        },
        expected: '$expected',
      );
    },
  );
  registrar.write(
    WriteToolSpec(
      name: 'confirm_binding',
      description:
          '为选定科研文档确认一条待消歧的文献绑定，并丢弃同项目内竞争的待消歧候选；需确认，只修改本机库。'
          'expected_digest 必须是确认时 research.list_bindings 返回的该绑定 digest，执行时在同一事务核对；'
          '绑定不存在或已确认则拒绝。',
      operations: _operations('confirm_binding'),
      targetTypes: {'document'},
      affectsTypes: {'document'},
      parameterSchema: {
        'type': 'object',
        'properties': {
          'document_id': {'type': 'string'},
          'paper_id': {'type': 'string'},
          'expected_digest': {'type': 'string', 'minLength': 1},
        },
        'required': ['document_id', 'paper_id', 'expected_digest'],
        'additionalProperties': false,
      },
    ),
    (ctx) async {
      final params = ctx.call.request.parameters;
      final ref = _selected(ctx, 'document', params['document_id'] as String);
      final paper = params['paper_id'] as String;
      return _outlineWrite(
        ctx,
        [ref],
        (store) => _bindingDigest(
          store
              .bindings(ref.nativeProjectId!)
              .firstWhere(
                (b) => b.documentId == ref.objectId && b.paperId == paper,
                orElse: () =>
                    throw StateError('Outline changed; confirm again'),
              ),
        ),
        (runtime, store) {
          store.confirmBinding(ref.objectId, paper);
          return _report(runtime, '已确认绑定', [
            ObjectChange(ref, ChangeOp.upsert),
          ]);
        },
        beforeEffect: (store) {
          // Refuse a settled or missing candidate before the effect starts, so
          // the receipt says "failed" rather than "may have happened".
          final row = store
              .bindings(ref.nativeProjectId!)
              .where((b) => b.documentId == ref.objectId && b.paperId == paper);
          if (row.length != 1 || !row.single.ambiguous) {
            throw StateError('Binding is not waiting for a choice');
          }
        },
      );
    },
  );
}

ObjectRef _selected(ModuleToolContext ctx, String type, String id) {
  final ref = ctx.call.resolvedScope.objects
      .where(
        (r) =>
            r.moduleId == 'research' &&
            r.objectType == type &&
            r.objectId == id,
      )
      .firstOrNull;
  if (ref == null) throw StateError('Object outside scope');
  return ref;
}

/// Outline rows have no version column. [expected] is the state shown at
/// confirmation: delete passes the cascade snapshot; update, cite and remove
/// pass the row content digest exposed by [ResearchSession]; add and move pass
/// the ordered section digest
/// because the neighbour is not stored on the selected row.
void _requireExpected(Object? expected, String actual) {
  if (expected is! String || expected != actual) {
    throw StateError('Outline changed; confirm again');
  }
}

/// Section tools address a paragraph by id. A heading that already belongs to
/// another paragraph is refused here, instead of attaching to the first match.
/// [OutlineStore.addOutline] still matches by heading; this does not change it.
void _refuseSameHeading(
  WorkbenchStore store,
  String projectId,
  String heading, {
  String? exceptId,
}) {
  final trimmed = heading.trim();
  if (trimmed.isEmpty) throw StateError('Outline changed; confirm again');
  final sections = store.sections(projectId);
  if (exceptId != null &&
      sections.any(
        (section) => section.id == exceptId && section.heading == trimmed,
      )) {
    return;
  }
  if (sections.any(
    (section) => section.heading == trimmed && section.id != exceptId,
  )) {
    throw StateError('Same section heading; choose a section id');
  }
}

String _rowDigest(Map<String, Object?> row) =>
    sha256.convert(utf8.encode(jsonEncode(row))).toString();

String _rowDigestOf(
  WorkbenchStore store,
  String table,
  String projectId,
  String id,
) {
  if (table != 'sections' && table != 'outline') {
    throw StateError('Outline changed; confirm again');
  }
  final rows = table == 'sections'
      ? store.db.select('SELECT * FROM sections WHERE id=? AND project_id=?', [
          id,
          projectId,
        ])
      : store.db.select('SELECT * FROM outline WHERE id=? AND project_id=?', [
          id,
          projectId,
        ]);
  if (rows.length != 1) throw StateError('Outline changed; confirm again');
  return _rowDigest(Map<String, Object?>.from(rows.single));
}

List<Map<String, Object?>> _sectionRows(
  WorkbenchStore store,
  String projectId,
) => [
  for (final section in store.sections(projectId))
    {
      'id': section.id,
      'projectId': section.projectId,
      'heading': section.heading,
      'level': section.level,
      'position': section.position,
      'argument': section.argument,
      'support': section.support,
    },
];

String _orderDigest(WorkbenchStore store, String projectId) => sha256
    .convert(utf8.encode(jsonEncode(_sectionRows(store, projectId))))
    .toString();

Map<String, Object?> _bindingJson(PaperBinding b) => {
  'documentId': b.documentId,
  'paperId': b.paperId,
  'paperRev': b.paperRev,
  'method': b.method,
  'hashOk': b.hashOk,
  'ambiguous': b.ambiguous,
};

String _bindingDigest(PaperBinding b) =>
    sha256.convert(utf8.encode(jsonEncode(_bindingJson(b)))).toString();

String _projectDigest(WorkbenchStore store, String id) {
  final p = store.projects().firstWhere(
    (p) => p.id == id,
    orElse: () => throw StateError('Outline changed; confirm again'),
  );
  return sha256
      .convert(utf8.encode(jsonEncode([p.title, p.question, p.nextStep])))
      .toString();
}

String _noteDigest(WorkbenchStore store, String projectId, String id) {
  final rows = store.db.select(
    'SELECT n.* FROM notes n JOIN documents d ON d.id=n.document_id WHERE n.id=? AND d.project_id=?',
    [id, projectId],
  );
  if (rows.length != 1) throw StateError('Outline changed; confirm again');
  return _rowDigest(Map<String, Object?>.from(rows.single));
}

int _latestRevision(WorkbenchStore store, String id) {
  final rows = store.db.select(
    'SELECT MAX(revision) AS r FROM tasks WHERE id=?',
    [id],
  );
  final latest = rows.single['r'] as int?;
  if (latest == null) throw StateError('Task revision changed');
  return latest;
}

/// Only these keys can come from the model; `command` and `source` stay as the
/// previous revision had them (or absent), so a task cannot be given a command.
Map<String, Object?> _taskSpec(
  Map<String, Object?> previous,
  Map<String, Object?> params,
) {
  const keys = {
    'parameters': 'parameters',
    'data_references': 'dataReferences',
    'code_reference': 'codeReference',
    'environment': 'environment',
    'expected_results': 'expectedResults',
  };
  final spec = Map<String, Object?>.from(previous);
  for (final entry in keys.entries) {
    if (params.containsKey(entry.key)) spec[entry.value] = params[entry.key];
  }
  if (jsonEncode(spec).length > 8000) throw StateError('Task spec too large');
  return spec;
}

Future<ToolCallResult> _taskWrite(
  ModuleToolContext ctx,
  ObjectRef project,
  ToolCallResult Function(ResearchRuntime runtime, WorkbenchStore store) apply,
) async {
  final runtime = await ctx.runtime<ResearchRuntime>();
  final store = runtime.store.scoped(project.nativeProjectId!);
  ctx.call.cancellation.throwIfCancelled();
  return store.write(() {
    runtime.requireCurrent(project);
    ctx.call.checkBeforeEffect();
    return apply(runtime, store);
  });
}

Future<ToolCallResult> _outlineWrite(
  ModuleToolContext ctx,
  List<ObjectRef> refs,
  String Function(WorkbenchStore store) digest,
  ToolCallResult Function(ResearchRuntime runtime, WorkbenchStore store)
  apply, {
  void Function(WorkbenchStore store)? beforeEffect,
  Object? expected,
}) async {
  final runtime = await ctx.runtime<ResearchRuntime>();
  final projectId = refs.first.nativeProjectId!;
  if (refs.any((ref) => ref.nativeProjectId != projectId)) {
    throw StateError('Object outside scope');
  }
  final store = runtime.store.scoped(projectId);
  expected ??= ctx.call.request.parameters['expected_digest'];
  ctx.call.cancellation.throwIfCancelled();
  return store.write(() {
    for (final ref in refs) {
      runtime.requireCurrent(ref);
    }
    beforeEffect?.call(store);
    _requireExpected(expected, digest(store));
    ctx.call.checkBeforeEffect();
    return apply(runtime, store);
  });
}

ToolCallResult _report(
  ResearchRuntime runtime,
  String summary,
  List<ObjectChange> changes,
) {
  if (changes.isEmpty) {
    return ToolCallResult(status: ToolCallStatus.succeeded, summary: summary);
  }
  final reported = <ObjectChange>[];
  for (final change in changes) {
    if (change.op == ChangeOp.delete) {
      reported.add(change);
      continue;
    }
    final resolved = runtime.resolveCurrent(
      ObjectRef(
        moduleId: change.ref.moduleId,
        objectType: change.ref.objectType,
        objectId: change.ref.objectId,
        nativeProjectId: change.ref.nativeProjectId,
      ),
    )!;
    reported.add(ObjectChange(resolved.ref, change.op));
  }
  return ToolCallResult(
    status: ToolCallStatus.succeeded,
    summary: summary,
    objectRefs: [for (final change in reported) change.ref],
    changes: reported,
  );
}

Map<String, Object?> _document(
  ResearchRuntime runtime,
  ObjectRef ref,
  ObjectView view,
) {
  final document = runtime.store
      .documents(ref.nativeProjectId!)
      .where((d) => d.id == ref.objectId)
      .firstOrNull;
  if (document == null) {
    final rows = runtime.store.db.select(
      'SELECT d.file_name,length(d.bytes) AS byte_count FROM rk_documents d JOIN canonical_object_map m ON m.object_key=d.object_key '
      "WHERE m.local_object_id=? AND m.local_project_id=? AND m.object_type='document' AND d.deleted=0",
      [ref.objectId, ref.nativeProjectId],
    );
    return {
      'relativePath': rows.single['file_name'],
      'byteCount': rows.single['byte_count'],
      'contentDigest': view.ref.contentDigest,
    };
  }
  final file = File(document.absolutePath);
  final data = <String, Object?>{
    'relativePath': document.relativePath,
    'contentDigest': view.ref.contentDigest,
    'missing': !file.existsSync(),
  };
  if (!file.existsSync()) return data;
  // Bind returned text to the same bytes as the selected digest, rather than
  // reading a fresh unverified prefix after scope resolution.
  final bytes = file.readAsBytesSync();
  if (sha256.convert(bytes).toString() != view.ref.contentDigest) {
    throw StateError('Document changed during reading');
  }
  data['byteCount'] = bytes.length;
  if (const [
    'md',
    'txt',
    'csv',
    'json',
  ].any((ext) => document.relativePath.toLowerCase().endsWith('.$ext'))) {
    data['text'] = utf8.decode(
      bytes.take(16000).toList(),
      allowMalformed: true,
    );
    data['truncated'] = bytes.length > 16000;
  }
  return data;
}

List<String> _operations(String name) => [
  for (final op in researchCoverage.operations)
    if (op.tools.contains('research.$name')) op.id,
];
