import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:research_module/research_module.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory root;
  late MuyonHost host;
  var invocation = 0;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('reg3cf-receipt-');
    host = await MuyonHost.open(p.join(root.path, 'data'));
    await host.activateResearch();
    final store = host.research!.store;
    await store.write(() {
      store.db.execute(
        'INSERT INTO projects(id,title,question,next_step) VALUES(?,?,?,?)',
        ['P', '研究', '问题', '下一步'],
      );
      for (final id in ['E1', 'E2']) {
        store.db.execute(
          'INSERT INTO entries(id,project_id,kind,title,data) VALUES(?,?,?,?,?)',
          [id, 'P', 'claim', id, '{}'],
        );
      }
    });
  });

  tearDown(() async {
    await host.close();
    root.deleteSync(recursive: true);
  });

  Future<ObjectRef> current(String type, String id) async {
    final session = await host.research!.openScopeSession();
    try {
      return (await session.resolve(
        ObjectRef(
          moduleId: 'research',
          objectType: type,
          objectId: id,
          nativeProjectId: 'P',
        ),
      ))!.ref;
    } finally {
      await session.dispose();
    }
  }

  ToolCallRequest request(
    String tool,
    Map<String, Object?> params,
    List<ObjectRef> refs,
  ) => ToolCallRequest(
    invocationId: 'reg3cf-receipt-${++invocation}',
    toolId: tool,
    parameters: params,
    scope: AssistantScope.selectedObjects(refs),
  );

  Future<ToolCallResult> approved(ToolCallRequest call) async {
    final approval = await host.tools.approve(await host.tools.prepare(call));
    return host.tools.invoke(call.withApproval(approval));
  }

  Future<List<OutlineSection>> seed(List<String> headings) async {
    final store = host.research!.store;
    return store.write(
      () => [for (final heading in headings) store.addSection('P', heading)],
    );
  }

  Future<String> orderDigest() async {
    final result = await host.tools.invoke(
      request(
        'research.outline_sections',
        {'project_id': 'P'},
        [await current('project', 'P')],
      ),
    );
    expect(result.status, ToolCallStatus.succeeded);
    return result.data['orderDigest'] as String;
  }

  Map<String, Object?> updateParams(ObjectRef ref, String heading) => {
    'section_id': ref.objectId,
    'heading': heading,
    'level': 2,
    'argument': 'A 的论证',
    'support': 'supported',
    'expected_digest': ref.contentDigest!,
  };

  Set<String> changes(ToolCallResult result) => {
    for (final change in result.changes)
      '${change.op.name}:${change.ref.objectType}:${change.ref.objectId}',
  };

  for (final deleteAfterCommit in [false, true]) {
    test(
      'I-2 receipt keeps A snapshot when B ${deleteAfterCommit ? 'deletes' : 'updates'} after commit',
      () async {
        final section = (await seed(['原段落'])).single;
        final selected = await current('section', section.id);
        final original = host.research!;
        final resources = original.resources;
        late ObjectRef committedA;
        var bCommitted = false;
        final observed = _AfterCommitDatabase(resources.database, () async {
          // The delegate future completes only after COMMIT. The wrapper has
          // not completed A's write future, so its handler cannot report yet.
          expect(resources.database.raw.autocommit, isTrue);
          expect(original.store.sections('P').single.heading, 'A 写入');
          committedA = await current('section', section.id);
          await original.store.write(() {
            if (deleteAfterCommit) {
              original.store.scoped('P').deleteSection(section.id);
            } else {
              original.store
                  .scoped('P')
                  .updateSection(
                    section.id,
                    heading: 'B 写入',
                    level: 3,
                    argument: 'B 的论证',
                    support: 'unassessed',
                  );
            }
          });
          bCommitted = true;
        });
        final runtime = ResearchRuntime(
          ModuleResources(
            database: observed,
            files: resources.files,
            capabilities: resources.capabilities,
          ),
        );
        host.modules.setRuntimeForTesting('research', runtime);
        final call = request(
          'research.update_section',
          updateParams(selected, 'A 写入'),
          [selected],
        );
        final result = await approved(call);
        expect(bCommitted, isTrue);
        expect(observed.interceptions, 1);
        expect(result.status, ToolCallStatus.succeeded, reason: result.summary);
        expect(host.tools.receiptFor(call.invocationId)!.state, 'succeeded');
        expect(result.summary, '已修改提纲段落');
        expect(changes(result), {'upsert:section:${section.id}'});
        expect(result.objectRefs.single.toJson(), committedA.toJson());
        expect(result.changes.single.ref.toJson(), committedA.toJson());
        expect(committedA.contentDigest, isNot(selected.contentDigest));
        if (deleteAfterCommit) {
          expect(runtime.store.sections('P'), isEmpty);
        } else {
          expect(runtime.store.sections('P').single.heading, 'B 写入');
          expect(
            result.objectRefs.single.contentDigest,
            isNot((await current('section', section.id)).contentDigest),
          );
        }
      },
    );
  }

  for (final boundary in [
    (headings: ['首段', '末段'], index: 0, delta: -1, label: '首位'),
    (headings: ['首段', '末段'], index: 1, delta: 1, label: '末位'),
    (headings: ['唯一段落'], index: 0, delta: -1, label: '首位'),
    (headings: ['唯一段落'], index: 0, delta: 1, label: '末位'),
  ]) {
    test(
      'N-1 ${boundary.headings.length} sections ${boundary.label} delta ${boundary.delta} reports unchanged position',
      () async {
        final sections = await seed(boundary.headings);
        final selected = await current('section', sections[boundary.index].id);
        final store = host.research!.store;
        final beforeSections = store.db
            .select('SELECT * FROM sections')
            .toList();
        final beforeLog = store.db
            .select('SELECT * FROM muyon_change_log ORDER BY sequence')
            .toList();
        final call = request(
          'research.move_section',
          {
            'section_id': selected.objectId,
            'delta': boundary.delta,
            'expected_digest': await orderDigest(),
          },
          [selected],
        );
        final result = await approved(call);
        expect(result.status, ToolCallStatus.succeeded);
        expect(result.summary, contains('已在${boundary.label}'));
        expect(result.summary, contains('位置未变化'));
        expect(result.changes, isEmpty);
        expect(result.objectRefs, isEmpty);
        expect(host.tools.receiptFor(call.invocationId)!.state, 'succeeded');
        expect(
          store.db.select('SELECT * FROM sections').toList(),
          beforeSections,
        );
        expect(
          store.db
              .select('SELECT * FROM muyon_change_log ORDER BY sequence')
              .toList(),
          beforeLog,
        );
      },
    );
  }

  test(
    'update receipt includes exactly the section and both changed links',
    () async {
      final sections = await seed(['甲', '无关']);
      final store = host.research!.store;
      await store.write(() {
        store.scoped('P').cite(sections.first.id, 'E1');
        store.scoped('P').cite(sections.first.id, 'E2');
        store.scoped('P').cite(sections.last.id, 'E1');
      });
      final links = store.db.select(
        'SELECT id FROM outline WHERE section_id=?',
        [sections.first.id],
      );
      final selected = await current('section', sections.first.id);
      final result = await approved(
        request('research.update_section', updateParams(selected, '更新甲'), [
          selected,
        ]),
      );
      expect(result.status, ToolCallStatus.succeeded);
      expect(changes(result), {
        'upsert:section:${sections.first.id}',
        for (final link in links) 'upsert:outline:${link['id']}',
      });
      expect(result.changes.length, 3);
      for (final ref in result.objectRefs) {
        expect(
          ref.toJson(),
          (await current(ref.objectType, ref.objectId)).toJson(),
        );
      }
    },
  );

  test('move receipt includes exactly the two swapped sections', () async {
    final sections = await seed(['甲', '乙', '无关']);
    final selected = await current('section', sections.first.id);
    final result = await approved(
      request(
        'research.move_section',
        {
          'section_id': selected.objectId,
          'delta': 1,
          'expected_digest': await orderDigest(),
        },
        [selected],
      ),
    );
    expect(result.status, ToolCallStatus.succeeded);
    expect(result.summary, '已移动提纲段落');
    expect(changes(result), {
      'upsert:section:${sections[0].id}',
      'upsert:section:${sections[1].id}',
    });
    expect(result.changes.length, 2);
    for (final ref in result.objectRefs) {
      expect(
        ref.toJson(),
        (await current(ref.objectType, ref.objectId)).toJson(),
      );
    }
  });

  test(
    'delete receipt includes exactly the section and its cascading links',
    () async {
      final sections = await seed(['甲', '无关']);
      final store = host.research!.store;
      await store.write(() {
        store.scoped('P').cite(sections.first.id, 'E1');
        store.scoped('P').cite(sections.first.id, 'E2');
        store.scoped('P').cite(sections.last.id, 'E1');
      });
      final links = store.db.select(
        'SELECT id FROM outline WHERE section_id=?',
        [sections.first.id],
      );
      final selected = await current('section', sections.first.id);
      final read = await host.tools.invoke(
        request(
          'research.read_object',
          {'type': 'section', 'id': selected.objectId},
          [selected],
        ),
      );
      final result = await approved(
        request(
          'research.delete_section',
          {
            'section_id': selected.objectId,
            'expected_digest': (read.data['object'] as Map)['deleteDigest'],
          },
          [selected],
        ),
      );
      expect(result.status, ToolCallStatus.succeeded);
      expect(changes(result), {
        'delete:section:${sections.first.id}',
        for (final link in links) 'delete:outline:${link['id']}',
      });
      expect(result.changes.length, 3);
      expect(store.sections('P').single.id, sections.last.id);
      expect(store.outline('P').single['section_id'], sections.last.id);
      expect(store.entries('P').length, 2);
    },
  );
}

/// Inserts a real second domain transaction after A's commit and before A's
/// awaiting handler resumes. Only the first observed write is intercepted.
class _AfterCommitDatabase implements ManagedDatabase {
  _AfterCommitDatabase(this.delegate, this.afterCommit);
  final ManagedDatabase delegate;
  final Future<void> Function() afterCommit;
  int interceptions = 0;

  @override
  Database get raw => delegate.raw;

  @override
  Future<T> write<T>(T Function(Database) body) async {
    final result = await delegate.write(body);
    if (interceptions == 0) {
      interceptions++;
      await afterCommit();
    }
    return result;
  }
}
