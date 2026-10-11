import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/app/host_tool_registrar.dart';
import 'package:muyon/app/module_host.dart';
import 'package:muyon/platform/tool_registry.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:research_module/research_module.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/reg3c_fixture.dart';

void main() {
  late Directory root;
  late MuyonHost host;
  var invocation = 0;
  const stale =
      '0000000000000000000000000000000000000000000000000000000000000000';

  setUp(() async {
    root = Directory.systemTemp.createTempSync('reg3c-');
    host = await MuyonHost.open(p.join(root.path, 'data'));
  });
  tearDown(() async {
    await host.close();
    root.deleteSync(recursive: true);
  });

  Future<ObjectRef> current(String type, String id, String project) =>
      currentResearchRef(host, type, id, project);

  Future<void> research() => seedPqeResearch(host);

  ToolCallRequest request(
    String tool,
    Map<String, Object?> params,
    List<ObjectRef> refs,
  ) => ToolCallRequest(
    invocationId: 'reg3c-${++invocation}',
    toolId: tool,
    parameters: params,
    scope: AssistantScope.selectedObjects(refs),
  );

  Future<ToolCallResult> invokeApproved(ToolCallRequest call) =>
      invokeApprovedResearchCall(host, call);

  Future<void> refuses(ToolCallRequest call, void Function() unchanged) async {
    final denied = await invokeApproved(call);
    expect(denied.status, ToolCallStatus.failed);
    expect(denied.changes, isEmpty);
    expect(host.tools.receiptFor(call.invocationId)!.state, 'failed');
    unchanged();
  }

  Future<void> unapproved(
    ToolCallRequest call,
    void Function() unchanged,
  ) async {
    await expectLater(host.tools.invoke(call), throwsA(isA<Exception>()));
    expect(host.tools.receiptFor(call.invocationId), isNull);
    unchanged();
  }

  Future<ToolCallResult> confirmed(ToolCallRequest call) async {
    final result = await invokeApproved(call);
    expect(result.status, ToolCallStatus.succeeded);
    expect(result.changes, isNotEmpty);
    expect(host.tools.receiptFor(call.invocationId)!.state, 'succeeded');
    return result;
  }

  List<String> headings() => host.research!.store
      .sections('P')
      .map((section) => section.heading)
      .toList();

  Future<ObjectRef> project(String id) => current('project', id, id);

  Future<String> orderDigest(ObjectRef selected) async {
    final listed = await host.tools.invoke(
      request(
        'research.outline_sections',
        {'project_id': selected.objectId},
        [selected],
      ),
    );
    expect(listed.status, ToolCallStatus.succeeded, reason: listed.summary);
    return listed.data['orderDigest'] as String;
  }

  Future<String> deleteDigest(ObjectRef section) async {
    final read = await host.tools.invoke(
      request(
        'research.read_object',
        {'type': 'section', 'id': section.objectId},
        [section],
      ),
    );
    expect(read.status, ToolCallStatus.succeeded);
    return (read.data['object'] as Map)['deleteDigest'] as String;
  }

  Future<List<OutlineSection>> seed(List<String> titles) =>
      seedPSections(host, titles);

  test('outline operations register tools and write actions', () {
    final module = ResearchModule();
    final operations = {for (final op in module.coverage.operations) op.id: op};
    final actions = {
      for (final action in module.ontology.actions) action.operationId: action,
    };
    const reads = {
      'research.query.outline_rows': 'research.outline_rows',
      'research.outline.sections': 'research.outline_sections',
    };
    const writes = {
      'research.outline.add_section': 'research.add_section',
      'research.outline.update_section': 'research.update_section',
      'research.outline.move_section': 'research.move_section',
      'research.outline.delete_section': 'research.delete_section',
      'research.outline.cite': 'research.cite',
      'research.outline.remove': 'research.remove_outline',
    };
    for (final entry in {...reads, ...writes}.entries) {
      expect(operations[entry.key]!.notExposed, isNull, reason: entry.key);
      expect(operations[entry.key]!.tools, [entry.value], reason: entry.key);
    }
    for (final entry in writes.entries) {
      expect(actions[entry.key]!.tool, entry.value);
      expect(actions[entry.key]!.description, '本机写入，宿主确认与回执');
    }
    for (final id in reads.keys) {
      expect(actions[id]!.tool, reads[id]);
      expect(actions[id]!.description, '本机只读，不修改科研库');
    }
  });

  test('outline reads stay inside the selected project', () async {
    await research();
    final created = await seed(['甲', '乙']);
    await host.research!.store.write(
      () => host.research!.store.scoped('P').cite(created.first.id, 'E'),
    );
    await host.research!.store.write(
      () => host.research!.store.addSection('Q', '越界'),
    );
    final selected = await project('P');
    final sections = await host.tools.invoke(
      request('research.outline_sections', {'project_id': 'P'}, [selected]),
    );
    expect(sections.status, ToolCallStatus.succeeded);
    expect(
      (sections.data['sections'] as List).map((row) => (row as Map)['heading']),
      ['甲', '乙'],
    );
    final firstSection = await current('section', created.first.id, 'P');
    expect(
      (sections.data['sections'] as List).first['deleteDigest'],
      await deleteDigest(firstSection),
    );
    expect(sections.data['orderDigest'], isA<String>());
    expect((sections.data['orderDigest'] as String).length, 64);
    final rows = await host.tools.invoke(
      request('research.outline_rows', {'project_id': 'P'}, [selected]),
    );
    expect(rows.status, ToolCallStatus.succeeded);
    expect((rows.data['outline'] as List).single['evidence_id'], 'E');
    final other = await project('Q');
    final denied = await host.tools.invoke(
      request('research.outline_sections', {'project_id': 'P'}, [other]),
    );
    expect(denied.status, ToolCallStatus.failed);
    expect(denied.data, isEmpty);
    final own = await host.tools.invoke(
      request('research.outline_rows', {'project_id': 'Q'}, [other]),
    );
    expect(own.status, ToolCallStatus.succeeded);
    expect(own.data['outline'], isEmpty);
    expect(headings(), ['甲', '乙']);
  });

  test('add_section writes once after confirmation and refuses scope, missing approval, stale order and replay', () async {
    await research();
    final selected = await project('P');
    final other = await project('Q');
    final digest = await orderDigest(selected);
    Map<String, Object?> params(String digest) => {
      'project_id': 'P',
      'heading': '论证',
      'level': 2,
      'expected_digest': digest,
    };
    void empty() => expect(headings(), isEmpty);
    await refuses(
      request('research.add_section', params(digest), [other]),
      empty,
    );
    await unapproved(
      request('research.add_section', params(digest), [selected]),
      empty,
    );
    await refuses(
      request('research.add_section', params(stale), [selected]),
      empty,
    );
    final call = request('research.add_section', params(digest), [selected]);
    final result = await confirmed(call);
    expect(result.changes.single.ref.objectType, 'section');
    expect(headings(), ['论证']);
    expect(host.research!.store.sections('P').single.level, 2);
    final replay = await invokeApproved(call);
    expect(replay.status, ToolCallStatus.succeeded);
    expect(headings(), ['论证']);
  });

  test('section writes locate by id, refuse a same heading, and show creation before confirmation', () async {
    await research();
    final selected = await project('P');
    final digest = await orderDigest(selected);
    final preview = request(
      'research.add_section',
      {
        'project_id': 'P',
        'heading': '新段落',
        'level': 2,
        'expected_digest': digest,
      },
      [selected],
    );
    final prepared = await host.tools.prepare(preview);
    expect(prepared.request.parameters['heading'], '新段落');
    expect(prepared.request.parameters['level'], 2);
    expect(
      host.tools.inspect('research.add_section')!.descriptor.description,
      contains('将新建的标题和层级'),
    );
    expect(headings(), isEmpty);

    final created = await seed(['甲', '甲']);
    final fresh = await orderDigest(selected);
    await refuses(
      request(
        'research.add_section',
        {
          'project_id': 'P',
          'heading': '甲',
          'level': 1,
          'expected_digest': fresh,
        },
        [selected],
      ),
      () {
        expect(headings(), ['甲', '甲']);
        expect(
          host.research!.store.sections('P').map((section) => section.id),
          [created.first.id, created.last.id],
        );
      },
    );

    final second = await current('section', created.last.id, 'P');
    final first = await current('section', created.first.id, 'P');
    await confirmed(
      request(
        'research.update_section',
        {
          'section_id': second.objectId,
          'heading': '甲',
          'level': 1,
          'argument': '只改这一节',
          'support': 'supported',
          'expected_digest': second.contentDigest,
        },
        [second],
      ),
    );
    final sections = host.research!.store.sections('P');
    expect(sections.first.id, created.first.id);
    expect(sections.first.argument, '');
    expect(sections.last.id, created.last.id);
    expect(sections.last.argument, '只改这一节');

    final entry = await current('entry', 'E', 'P');
    final cited = await current('section', created.last.id, 'P');
    await confirmed(
      request(
        'research.cite',
        {
          'section_id': cited.objectId,
          'evidence_type': 'entry',
          'evidence_id': 'E',
          'expected_digest': cited.contentDigest,
        },
        [cited, entry],
      ),
    );
    expect(
      host.research!.store.outline('P').single['section_id'],
      created.last.id,
    );

    final renamed = await current('section', created.last.id, 'P');
    await confirmed(
      request(
        'research.update_section',
        {
          'section_id': renamed.objectId,
          'heading': '改后',
          'level': 1,
          'argument': '只改这一节',
          'support': 'supported',
          'expected_digest': renamed.contentDigest,
        },
        [renamed],
      ),
    );
    await refuses(
      request(
        'research.update_section',
        {
          'section_id': first.objectId,
          'heading': '改后',
          'level': 1,
          'argument': '',
          'support': 'unassessed',
          'expected_digest': first.contentDigest,
        },
        [first],
      ),
      () => expect(headings(), ['甲', '改后']),
    );
    await expectLater(
      host.tools.prepare(
        request(
          'research.update_section',
          {
            'heading': '甲',
            'level': 1,
            'argument': '',
            'support': 'unassessed',
            'expected_digest': first.contentDigest,
          },
          [first],
        ),
      ),
      throwsA(isA<Exception>()),
    );
    expect(headings(), ['甲', '改后']);
    expect(
      host.research!.store.outline('P').single['section_id'],
      created.last.id,
    );
  });

  test('update_section writes once after confirmation and refuses scope, missing approval, stale digest and replay', () async {
    await research();
    final created = await seed(['甲', '乙']);
    await host.research!.store.write(
      () => host.research!.store.scoped('P').cite(created.first.id, 'E'),
    );
    final section = await current('section', created.first.id, 'P');
    final neighbour = await current('section', created.last.id, 'P');
    Map<String, Object?> params(String id, String digest) => {
      'section_id': id,
      'heading': '改后',
      'level': 2,
      'argument': '因为',
      'support': 'supported',
      'expected_digest': digest,
    };
    void original() {
      expect(headings(), ['甲', '乙']);
      expect(host.research!.store.outline('P').single['heading'], '甲');
    }

    await refuses(
      request(
        'research.update_section',
        params(neighbour.objectId, neighbour.contentDigest!),
        [section],
      ),
      original,
    );
    await unapproved(
      request(
        'research.update_section',
        params(section.objectId, section.contentDigest!),
        [section],
      ),
      original,
    );
    await refuses(
      request('research.update_section', params(section.objectId, stale), [
        section,
      ]),
      original,
    );
    final call = request(
      'research.update_section',
      params(section.objectId, section.contentDigest!),
      [section],
    );
    await confirmed(call);
    final updated = host.research!.store.sections('P').first;
    expect(updated.heading, '改后');
    expect(updated.level, 2);
    expect(updated.argument, '因为');
    expect(updated.support, 'supported');
    expect(host.research!.store.outline('P').single['heading'], '改后');
    expect(host.research!.store.entries('P').single.id, 'E');
    await expectLater(invokeApproved(call), throwsStateError);
    expect(headings().first, '改后');
  });

  test('move_section writes once after confirmation and refuses scope, missing approval, stale order and replay', () async {
    await research();
    final created = await seed(['甲', '乙']);
    final first = await current('section', created.first.id, 'P');
    final second = await current('section', created.last.id, 'P');
    final selected = await project('P');
    final digest = await orderDigest(selected);
    Map<String, Object?> params(String id, String digest, {int delta = 1}) => {
      'section_id': id,
      'delta': delta,
      'expected_digest': digest,
    };
    void original() => expect(headings(), ['甲', '乙']);
    await refuses(
      request(
        'research.move_section',
        params(second.objectId, digest, delta: -1),
        [first],
      ),
      original,
    );
    await unapproved(
      request('research.move_section', params(first.objectId, digest), [first]),
      original,
    );
    await refuses(
      request('research.move_section', params(first.objectId, stale), [first]),
      original,
    );
    final call = request(
      'research.move_section',
      params(first.objectId, digest),
      [first],
    );
    await confirmed(call);
    expect(headings(), ['乙', '甲']);
    await expectLater(invokeApproved(call), throwsStateError);
    expect(headings(), ['乙', '甲']);
  });

  test('delete_section writes once after confirmation and refuses scope, missing approval, stale digest and replay', () async {
    await research();
    final created = await seed(['甲', '乙']);
    await host.research!.store.write(
      () => host.research!.store.scoped('P').cite(created.first.id, 'E'),
    );
    final section = await current('section', created.first.id, 'P');
    final digest = await deleteDigest(section);
    final neighbour = await current('section', created.last.id, 'P');
    Map<String, Object?> params(String id, String digest) => {
      'section_id': id,
      'expected_digest': digest,
    };
    void original() {
      expect(headings(), ['甲', '乙']);
      expect(host.research!.store.outline('P'), hasLength(1));
    }

    await refuses(
      request('research.delete_section', params(section.objectId, digest), [
        neighbour,
      ]),
      original,
    );
    await unapproved(
      request('research.delete_section', params(section.objectId, digest), [
        section,
      ]),
      original,
    );
    await refuses(
      request('research.delete_section', params(section.objectId, stale), [
        section,
      ]),
      original,
    );
    // A row-only digest cannot approve a cascade, even if the section is current.
    await refuses(
      request(
        'research.delete_section',
        params(section.objectId, section.contentDigest!),
        [section],
      ),
      original,
    );
    final call = request(
      'research.delete_section',
      params(section.objectId, digest),
      [section],
    );
    final result = await confirmed(call);
    expect(
      result.changes
          .singleWhere((change) => change.ref.objectId == section.objectId)
          .op,
      ChangeOp.delete,
    );
    expect(headings(), ['乙']);
    expect(host.research!.store.outline('P'), isEmpty);
    expect(host.research!.store.entries('P').single.id, 'E');
    await expectLater(invokeApproved(call), throwsStateError);
    expect(headings(), ['乙']);
    expect(host.research!.store.entries('P').single.id, 'E');
  });

  test('cite writes once after confirmation and refuses scope, missing approval, stale digest and replay', () async {
    await research();
    final created = await seed(['甲']);
    final section = await current('section', created.single.id, 'P');
    final evidence = await current('entry', 'E', 'P');
    Map<String, Object?> params(String digest) => {
      'section_id': section.objectId,
      'evidence_type': 'entry',
      'evidence_id': 'E',
      'expected_digest': digest,
    };
    void empty() => expect(host.research!.store.outline('P'), isEmpty);
    await refuses(
      request('research.cite', params(section.contentDigest!), [section]),
      empty,
    );
    await unapproved(
      request('research.cite', params(section.contentDigest!), [
        section,
        evidence,
      ]),
      empty,
    );
    await refuses(
      request('research.cite', params(stale), [section, evidence]),
      empty,
    );
    final call = request('research.cite', params(section.contentDigest!), [
      section,
      evidence,
    ]);
    final result = await confirmed(call);
    expect(result.changes.single.ref.objectType, 'outline');
    expect(host.research!.store.outline('P').single['evidence_id'], 'E');
    expect(host.research!.store.outline('P').single['heading'], '甲');
    final replay = await invokeApproved(call);
    expect(replay.status, ToolCallStatus.succeeded);
    expect(host.research!.store.outline('P'), hasLength(1));
    final linkId = host.research!.store.outline('P').single['id'];
    await host.research!.store.write(
      () => host.research!.store.db.execute('DELETE FROM outline WHERE id=?', [
        linkId,
      ]),
    );
    final again = await invokeApproved(call);
    expect(again.status, ToolCallStatus.succeeded);
    expect(host.research!.store.outline('P'), isEmpty);
  });

  test('remove_outline writes once after confirmation and refuses scope, missing approval, stale digest and replay', () async {
    await research();
    final created = await seed(['甲']);
    await host.research!.store.write(
      () => host.research!.store.scoped('P').cite(created.single.id, 'E'),
    );
    final linkId = host.research!.store.outline('P').single['id'] as String;
    final link = await current('outline', linkId, 'P');
    final section = await current('section', created.single.id, 'P');
    Map<String, Object?> params(String digest) => {
      'outline_id': linkId,
      'expected_digest': digest,
    };
    void present() {
      expect(host.research!.store.outline('P'), hasLength(1));
      expect(headings(), ['甲']);
    }

    await refuses(
      request('research.remove_outline', params(link.contentDigest!), [
        section,
      ]),
      present,
    );
    await unapproved(
      request('research.remove_outline', params(link.contentDigest!), [link]),
      present,
    );
    await refuses(
      request('research.remove_outline', params(stale), [link]),
      present,
    );
    final call = request(
      'research.remove_outline',
      params(link.contentDigest!),
      [link],
    );
    final result = await confirmed(call);
    expect(result.changes.single.op, ChangeOp.delete);
    expect(host.research!.store.outline('P'), isEmpty);
    expect(headings(), ['甲']);
    expect(host.research!.store.entries('P').single.id, 'E');
    await expectLater(invokeApproved(call), throwsStateError);
    expect(host.research!.store.outline('P'), isEmpty);
    expect(host.research!.store.entries('P').single.id, 'E');
  });

  for (final mutation in ['add', 'remove']) {
    test(
      'delete_section refuses $mutation of links after approval before dispatch',
      () async {
        await research();
        final created = await seed(['甲']);
        final store = host.research!.store;
        if (mutation == 'remove') {
          await store.write(
            () => store.scoped('P').cite(created.single.id, 'E'),
          );
        }
        final section = await current('section', created.single.id, 'P');
        final digest = await deleteDigest(section);
        final call = request(
          'research.delete_section',
          {'section_id': section.objectId, 'expected_digest': digest},
          [section],
        );
        final approval = await host.tools.approve(
          await host.tools.prepare(call),
        );
        await store.write(() {
          if (mutation == 'add') {
            store.scoped('P').cite(section.objectId, 'E');
          } else {
            store
                .scoped('P')
                .removeOutline(store.outline('P').single['id'] as String);
          }
        });
        final links = store.outline('P');
        expect(
          (await current('section', section.objectId, 'P')).contentDigest,
          section.contentDigest,
        );
        expect(await deleteDigest(section), isNot(digest));
        final result = await host.tools.invoke(call.withApproval(approval));
        expect(result.status, ToolCallStatus.failed);
        expect(result.changes, isEmpty);
        expect(host.tools.receiptFor(call.invocationId)!.state, 'failed');
        expect(headings(), ['甲']);
        expect(store.outline('P'), links);
        expect(store.entries('P').single.id, 'E');
      },
    );
  }

  for (final mutation in ['add', 'remove', 'replace', 'edit']) {
    test('queued delete_section refuses $mutation of approved cascade', () async {
      await research();
      final created = await seed(['甲', '乙']);
      final store = host.research!.store;
      await store.write(() => store.scoped('P').cite(created.first.id, 'E'));
      final section = await current('section', created.first.id, 'P');
      final digest = await deleteDigest(section);
      final sectionRow = Map<String, Object?>.from(
        store.db.select('SELECT * FROM sections WHERE id=?', [
          section.objectId,
        ]).single,
      );
      final link = store.outline('P').single;
      final original = host.research!.resources;
      final observed = _ObservedWrite(original.database);
      final runtime = ResearchRuntime(
        ModuleResources(
          database: observed,
          files: original.files,
          capabilities: original.capabilities,
        ),
      );
      host.modules.setRuntimeForTesting('research', runtime);
      final call = request(
        'research.delete_section',
        {'section_id': section.objectId, 'expected_digest': digest},
        [section],
      );
      final approval = await host.tools.approve(await host.tools.prepare(call));
      final entered = Completer<void>();
      final release = Completer<void>();
      late List<Map<String, Object?>> linksAfterConcurrentWrite;
      final holding = (original.database as ExclusiveDatabase)
          .exclusiveAsync<void>((db) async {
            entered.complete();
            await release.future;
            if (mutation == 'add') {
              db.execute(
                'INSERT INTO entries(id,project_id,kind,title,data) VALUES(?,?,?,?,?)',
                ['E2', 'P', 'claim', '新增证据', '{}'],
              );
              store.scoped('P').cite(section.objectId, 'E2');
            } else if (mutation == 'remove') {
              store.scoped('P').removeOutline(link['id'] as String);
            } else if (mutation == 'replace') {
              store.scoped('P').removeOutline(link['id'] as String);
              store.scoped('P').cite(section.objectId, 'E');
            } else {
              db.execute('UPDATE outline SET heading=? WHERE id=?', [
                '并发修改引用',
                link['id'],
              ]);
            }
            linksAfterConcurrentWrite = store.outline('P');
            expect(
              Map<String, Object?>.from(
                store.db.select('SELECT * FROM sections WHERE id=?', [
                  section.objectId,
                ]).single,
              ),
              sectionRow,
            );
          });
      await entered.future;
      try {
        final resultFuture = host.tools.invoke(call.withApproval(approval));
        await observed.queued.future.timeout(const Duration(seconds: 5));
        release.complete();
        await holding;
        final result = await resultFuture;
        expect(result.status, ToolCallStatus.failed);
        expect(result.changes, isEmpty);
        expect(host.tools.receiptFor(call.invocationId)!.state, 'failed');
        expect(headings(), ['甲', '乙']);
        expect(store.outline('P'), linksAfterConcurrentWrite);
        expect(store.entries('P').map((entry) => entry.id), contains('E'));
        final replay = await host.tools.invoke(call.withApproval(approval));
        expect(replay.status, ToolCallStatus.failed);
        expect(replay.changes, isEmpty);
        expect(store.outline('P'), linksAfterConcurrentWrite);
        // A new snapshot and a fresh one-time approval can delete the cascade.
        final fresh = await current('section', section.objectId, 'P');
        expect(fresh.contentDigest, section.contentDigest);
        final freshDigest = await deleteDigest(fresh);
        expect(freshDigest, isNot(digest));
        final retried = await confirmed(
          request(
            'research.delete_section',
            {'section_id': fresh.objectId, 'expected_digest': freshDigest},
            [fresh],
          ),
        );
        expect(retried.changes.map((change) => change.ref.objectId).toSet(), {
          fresh.objectId,
          for (final row in linksAfterConcurrentWrite) row['id'],
        });
        expect(headings(), ['乙']);
        expect(store.outline('P'), isEmpty);
        expect(store.entries('P').map((entry) => entry.id), contains('E'));
      } finally {
        if (!release.isCompleted) release.complete();
        await holding;
      }
    });
  }

  test('delete_section permits unrelated and duplicate citations after approval', () async {
    await research();
    final created = await seed(['甲', '乙']);
    final store = host.research!.store;
    await store.write(() => store.scoped('P').cite(created.first.id, 'E'));
    final section = await current('section', created.first.id, 'P');
    final digest = await deleteDigest(section);
    final approvedLink = store.outline('P').single['id'];
    final call = request(
      'research.delete_section',
      {'section_id': section.objectId, 'expected_digest': digest},
      [section],
    );
    final approval = await host.tools.approve(await host.tools.prepare(call));
    await store.write(() {
      store.scoped('P').cite(section.objectId, 'E'); // no-op
      store.scoped('P').cite(created.last.id, 'E');
      final other = store.addSection('Q', '另一项目');
      store.db.execute(
        'INSERT INTO entries(id,project_id,kind,title,data) VALUES(?,?,?,?,?)',
        ['EQ', 'Q', 'claim', '另一项目证据', '{}'],
      );
      store.scoped('Q').cite(other.id, 'EQ');
    });
    expect(
      (await current('section', section.objectId, 'P')).contentDigest,
      section.contentDigest,
    );
    final result = await host.tools.invoke(call.withApproval(approval));
    expect(result.status, ToolCallStatus.succeeded);
    expect(result.changes.map((change) => change.ref.objectId).toSet(), {
      section.objectId,
      approvedLink,
    });
    expect(headings(), ['乙']);
    expect(store.outline('P').single['section_id'], created.last.id);
    expect(store.outline('Q').single['evidence_id'], 'EQ');
    expect(store.entries('P').single.id, 'E');
  });

  test('cite rejects current evidence from another project before writing', () async {
    await research();
    final created = await seed(['甲']);
    final store = host.research!.store;
    await store.write(
      () => store.db.execute(
        'INSERT INTO entries(id,project_id,kind,title,data) VALUES(?,?,?,?,?)',
        ['EQ', 'Q', 'claim', '另一项目证据', '{}'],
      ),
    );
    final section = await current('section', created.single.id, 'P');
    final evidence = await current('entry', 'EQ', 'Q');
    final registry = ToolRegistry(
      database: host.tools.database,
      resolveScope: host.tools.resolveScope,
    );
    // Observe the real handler error before the registry sanitizes StateError.
    // Lower-level cite also refuses cross-project evidence; failed alone would
    // pass even if the earlier Object outside scope guard were removed.
    final registrar = _ObservedToolRegistrar(registry, host.modules);
    ResearchModule().registerTools(registrar);
    registrar.seal();
    final call = request(
      'research.cite',
      {
        'section_id': section.objectId,
        'evidence_type': 'entry',
        'evidence_id': evidence.objectId,
        'expected_digest': section.contentDigest!,
      },
      [section, evidence],
    );
    final changes = store.db.select('SELECT * FROM change_log').toList();
    try {
      final prepared = await registry.prepare(call);
      expect(prepared.resolvedScope.objects.map((ref) => ref.nativeProjectId), [
        'P',
        'Q',
      ]);
      final approval = await registry.approve(prepared);
      final result = await registry.invoke(call.withApproval(approval));
      expect(
        registrar.error,
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Object outside scope',
        ),
      );
      expect(result.status, ToolCallStatus.failed);
      expect(result.changes, isEmpty);
      expect(registry.receiptFor(call.invocationId)!.state, 'failed');
      expect(store.outline('P'), isEmpty);
      expect(store.outline('Q'), isEmpty);
      expect(headings(), ['甲']);
      expect(store.entries('Q').single.id, 'EQ');
      expect(store.db.select('SELECT * FROM change_log').toList(), changes);
    } finally {
      await registry.close();
    }
  });

  test(
    'queued add_section refuses authority withdrawn before effect',
    () async {
      await research();
      final selected = await project('P');
      final digest = await orderDigest(selected);
      final original = host.research!.resources;
      final observed = _ObservedWrite(original.database);
      final runtime = ResearchRuntime(
        ModuleResources(
          database: observed,
          files: original.files,
          capabilities: original.capabilities,
        ),
      );
      host.modules.setRuntimeForTesting('research', runtime);
      final call = request(
        'research.add_section',
        {
          'project_id': 'P',
          'heading': '确认新增',
          'level': 1,
          'expected_digest': digest,
        },
        [selected],
      );
      final approval = await host.tools.approve(await host.tools.prepare(call));
      final changes = runtime.store.db
          .select('SELECT * FROM change_log')
          .toList();
      final entered = Completer<void>();
      final release = Completer<void>();
      final holding = (original.database as ExclusiveDatabase)
          .exclusiveAsync<void>((_) async {
            entered.complete();
            await release.future;
          });
      await entered.future;
      try {
        final pending = host.tools.invoke(call.withApproval(approval));
        await observed.queued.future.timeout(const Duration(seconds: 5));
        host.tools.setAvailability('research.add_section', available: false);
        release.complete();
        await holding;
        final result = await pending;
        expect(runtime.store.sections('P'), isEmpty);
        expect(
          runtime.store.db.select('SELECT * FROM change_log').toList(),
          changes,
        );
        expect(result.status, ToolCallStatus.failed);
        expect(result.summary, contains('Tool authority was withdrawn'));
        expect(result.changes, isEmpty);
        // The registry creates a running receipt before dispatch. A refusal
        // therefore leaves a failed audit receipt, never a success receipt.
        expect(host.tools.receiptFor(call.invocationId)!.state, 'failed');
      } finally {
        if (!release.isCompleted) release.complete();
        await holding;
      }
    },
  );

  test(
    'queued cite refuses evidence no longer matching the confirmed object',
    () async {
      await research();
      final created = await seed(['甲']);
      final section = await current('section', created.single.id, 'P');
      final evidence = await current('entry', 'E', 'P');
      final original = host.research!.resources;
      final observed = _ObservedWrite(original.database);
      final runtime = ResearchRuntime(
        ModuleResources(
          database: observed,
          files: original.files,
          capabilities: original.capabilities,
        ),
      );
      host.modules.setRuntimeForTesting('research', runtime);
      final call = request(
        'research.cite',
        {
          'section_id': section.objectId,
          'evidence_type': 'entry',
          'evidence_id': evidence.objectId,
          'expected_digest': section.contentDigest!,
        },
        [section, evidence],
      );
      final approval = await host.tools.approve(await host.tools.prepare(call));
      final changes = runtime.store.db
          .select('SELECT * FROM change_log')
          .toList();
      final entered = Completer<void>();
      final release = Completer<void>();
      final holding = (original.database as ExclusiveDatabase)
          .exclusiveAsync<void>((db) async {
            entered.complete();
            await release.future;
            db.execute('UPDATE entries SET data=? WHERE id=?', [
              '{"claim":"changed"}',
              'E',
            ]);
          });
      await entered.future;
      try {
        final pending = host.tools.invoke(call.withApproval(approval));
        await observed.queued.future.timeout(const Duration(seconds: 5));
        release.complete();
        await holding;
        final result = await pending;
        expect(runtime.store.outline('P'), isEmpty);
        expect(result.status, ToolCallStatus.failed);
        expect(result.changes, isEmpty);
        expect(host.tools.receiptFor(call.invocationId)!.state, 'failed');
        expect(
          runtime.store.db.select('SELECT * FROM change_log').toList(),
          changes,
        );
        expect(
          (await current('section', section.objectId, 'P')).contentDigest,
          section.contentDigest,
        );
        expect(
          (await current('entry', 'E', 'P')).contentDigest,
          isNot(evidence.contentDigest),
        );
        expect(headings(), ['甲']);
      } finally {
        if (!release.isCompleted) release.complete();
        await holding;
      }
    },
  );

  test(
    'queued add_section rechecks the order digest inside the transaction',
    () async {
      await research();
      final selected = await project('P');
      final digest = await orderDigest(selected);
      final original = host.research!.resources;
      final observed = _ObservedWrite(original.database);
      final runtime = ResearchRuntime(
        ModuleResources(
          database: observed,
          files: original.files,
          capabilities: original.capabilities,
        ),
      );
      host.modules.setRuntimeForTesting('research', runtime);
      final call = request(
        'research.add_section',
        {
          'project_id': 'P',
          'heading': '确认新增',
          'level': 1,
          'expected_digest': digest,
        },
        [selected],
      );
      final approval = await host.tools.approve(await host.tools.prepare(call));
      final entered = Completer<void>();
      final release = Completer<void>();
      final holding = (original.database as ExclusiveDatabase)
          .exclusiveAsync<void>((db) async {
            entered.complete();
            await release.future;
            db.execute(
              'INSERT INTO sections(id,project_id,heading,level,position,argument,support) VALUES(?,?,?,?,?,?,?)',
              ['queued-section', 'P', '排队插入', 1, 1, '', 'unassessed'],
            );
          });
      await entered.future;
      try {
        final resultFuture = host.tools.invoke(call.withApproval(approval));
        await observed.queued.future.timeout(const Duration(seconds: 5));
        release.complete();
        await holding;
        final result = await resultFuture;
        expect(result.status, ToolCallStatus.failed);
        expect(result.changes, isEmpty);
        expect(host.tools.receiptFor(call.invocationId)!.state, 'failed');
        expect(runtime.store.sections('P').map((section) => section.heading), [
          '排队插入',
        ]);
      } finally {
        if (!release.isCompleted) release.complete();
        await holding;
      }
    },
  );
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

class _ObservedToolRegistrar extends HostToolRegistrar {
  _ObservedToolRegistrar(ToolRegistry registry, ModuleHost modules)
    : super('research', registry, ResearchModule().manifest, modules);

  Object? error;

  @override
  void write(WriteToolSpec spec, ModuleToolHandler handler) {
    super.write(spec, (context) async {
      try {
        return await handler(context);
      } catch (caught) {
        error = caught;
        rethrow;
      }
    });
  }
}
