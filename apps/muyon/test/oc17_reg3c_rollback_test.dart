import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:research_module/research_module.dart';
import 'package:sqlite3/sqlite3.dart';

// OC-17: pins that a multi-row research write either commits whole or rolls
// back whole. A TEMP trigger on the test database injects an ABORT when the
// second outline link of S1 is deleted or updated; the business rows, the
// import change_log and the module change log must all keep the old state.
void main() {
  late Directory root;
  late MuyonHost host;
  var invocation = 0;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('oc17-');
    host = await MuyonHost.open(p.join(root.path, 'data'));
  });
  tearDown(() async {
    await host.close();
    root.deleteSync(recursive: true);
  });

  Future<ObjectRef> current(String type, String id, String project) async {
    final session = await host.research!.openScopeSession();
    try {
      return (await session.resolve(
        ObjectRef(
          moduleId: 'research',
          objectType: type,
          objectId: id,
          nativeProjectId: project,
        ),
      ))!.ref;
    } finally {
      await session.dispose();
    }
  }

  Future<void> research() async {
    await host.activateResearch();
    final store = host.research!.store;
    await store.write(() {
      store.db.execute(
        'INSERT INTO projects(id,title,question,next_step) VALUES(?,?,?,?)',
        ['P', '研究', '问题', '下一步'],
      );
      store.db.execute(
        'INSERT INTO projects(id,title,question,next_step) VALUES(?,?,?,?)',
        ['Q', '另一项目', '', ''],
      );
      store.db.execute(
        'INSERT INTO entries(id,project_id,kind,title,data) VALUES(?,?,?,?,?)',
        ['E', 'P', 'claim', '证据', '{}'],
      );
    });
  }

  ToolCallRequest request(
    String tool,
    Map<String, Object?> params,
    List<ObjectRef> refs,
  ) => ToolCallRequest(
    invocationId: 'oc17-${++invocation}',
    toolId: tool,
    parameters: params,
    scope: AssistantScope.selectedObjects(refs),
  );

  Future<ToolCallResult> invokeApproved(ToolCallRequest call) async {
    final approval = await host.tools.approve(await host.tools.prepare(call));
    return host.tools.invoke(call.withApproval(approval));
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

  Future<List<OutlineSection>> seed(List<String> titles) async {
    final store = host.research!.store;
    final created = <OutlineSection>[];
    await store.write(() {
      for (final title in titles) {
        created.add(store.addSection('P', title));
      }
    });
    return created;
  }

  /// S1/S2/S3 with two evidence links under S1, in insertion order.
  Future<({String sectionId, List<String> linkIds})> seededChain() async {
    final created = await seed(['S1', 'S2', 'S3']);
    final store = host.research!.store;
    await store.write(() {
      store.db.execute(
        'INSERT INTO entries(id,project_id,kind,title,data) VALUES(?,?,?,?,?)',
        ['E2', 'P', 'claim', '证据2', '{}'],
      );
      store.scoped('P').cite(created.first.id, 'E');
      store.scoped('P').cite(created.first.id, 'E2');
    });
    final links = [
      for (final row in store.outline('P'))
        if (row['section_id'] == created.first.id) row['id'] as String,
    ];
    expect(links, hasLength(2));
    return (sectionId: created.first.id, linkIds: links);
  }

  Future<String> deleteDigest(ObjectRef section) async {
    final read = await host.tools.invoke(
      request(
        'research.read_object',
        {'type': 'section', 'id': section.objectId},
        [section],
      ),
    );
    expect(read.status, ToolCallStatus.succeeded, reason: read.summary);
    return (read.data['object'] as Map)['deleteDigest'] as String;
  }

  List<Map<String, Object?>> sectionsSnapshot() => host.research!.store.db
      .select('SELECT * FROM sections WHERE project_id=? ORDER BY position', [
        'P',
      ])
      .map((row) => Map<String, Object?>.from(row))
      .toList();

  List<Map<String, Object?>> outlineSnapshot() => host.research!.store.db
      .select('SELECT * FROM outline WHERE project_id=? ORDER BY rowid', ['P'])
      .map((row) => Map<String, Object?>.from(row))
      .toList();

  List<Map<String, Object?>> importLog() => host.research!.store.db
      .select('SELECT * FROM change_log ORDER BY sequence')
      .map((row) => Map<String, Object?>.from(row))
      .toList();

  List<Map<String, Object?>> moduleLog() => host.research!.store.db
      .select('SELECT * FROM muyon_change_log ORDER BY sequence')
      .map((row) => Map<String, Object?>.from(row))
      .toList();

  test(
    'delete_section rolls back when an outline delete fails midway',
    () async {
      await research();
      final chain = await seededChain();
      final store = host.research!.store;
      store.db.execute(
        "CREATE TEMP TRIGGER oc17_deny_second_outline_delete "
        "BEFORE DELETE ON outline WHEN OLD.id = '${chain.linkIds[1]}' "
        "BEGIN SELECT RAISE(ABORT,'injected outline delete'); END",
      );
      // Premise: the trigger really blocks deleting the second link.
      await expectLater(
        store.write(
          () => store.db.execute('DELETE FROM outline WHERE id=?', [
            chain.linkIds[1],
          ]),
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(
        store.outline('P').map((row) => row['id']),
        containsAll(chain.linkIds),
      );

      final beforeSections = sectionsSnapshot();
      final beforeOutline = outlineSnapshot();
      final beforeImportLog = importLog();
      final beforeModuleLog = moduleLog();

      final first = await current('section', chain.sectionId, 'P');
      final digest = await deleteDigest(first);
      final call = request(
        'research.delete_section',
        {'section_id': first.objectId, 'expected_digest': digest},
        [first],
      );
      final result = await invokeApproved(call);
      expect(result.status, isNot(ToolCallStatus.succeeded));
      expect(result.changes, isEmpty);

      expect(sectionsSnapshot(), beforeSections);
      expect(outlineSnapshot(), beforeOutline);
      expect(importLog(), beforeImportLog);
      expect(moduleLog(), beforeModuleLog);
      expect(headings(), ['S1', 'S2', 'S3']);
    },
  );

  test(
    'update_section heading rolls back when a linked outline update fails',
    () async {
      await research();
      final chain = await seededChain();
      final store = host.research!.store;
      store.db.execute(
        "CREATE TEMP TRIGGER oc17_deny_second_outline_update "
        "BEFORE UPDATE ON outline WHEN OLD.id = '${chain.linkIds[1]}' "
        "BEGIN SELECT RAISE(ABORT,'injected outline update'); END",
      );
      // Premise: the trigger really blocks updating the second link.
      await expectLater(
        store.write(
          () => store.db.execute('UPDATE outline SET heading=? WHERE id=?', [
            '触发器注入',
            chain.linkIds[1],
          ]),
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(
        store
            .outline('P')
            .where((row) => row['id'] == chain.linkIds[1])
            .single['heading'],
        'S1',
      );

      final beforeSections = sectionsSnapshot();
      final beforeOutline = outlineSnapshot();
      final beforeImportLog = importLog();
      final beforeModuleLog = moduleLog();

      final first = await current('section', chain.sectionId, 'P');
      final call = request(
        'research.update_section',
        {
          'section_id': first.objectId,
          'heading': '改后 S1',
          'level': 1,
          'argument': '',
          'support': 'unassessed',
          'expected_digest': first.contentDigest!,
        },
        [first],
      );
      final result = await invokeApproved(call);
      expect(result.status, isNot(ToolCallStatus.succeeded));
      expect(result.changes, isEmpty);

      expect(
        store
            .sections('P')
            .firstWhere((section) => section.id == chain.sectionId)
            .heading,
        'S1',
      );
      for (final row in store.outline('P')) {
        expect(row['heading'], 'S1');
      }
      expect(sectionsSnapshot(), beforeSections);
      expect(outlineSnapshot(), beforeOutline);
      expect(importLog(), beforeImportLog);
      expect(moduleLog(), beforeModuleLog);
    },
  );

  test('delete_section succeeds without the trigger', () async {
    await research();
    final chain = await seededChain();
    final store = host.research!.store;
    final beforeModuleLog = moduleLog();
    final beforeImportLog = importLog();

    final first = await current('section', chain.sectionId, 'P');
    final digest = await deleteDigest(first);
    final result = await confirmed(
      request(
        'research.delete_section',
        {'section_id': first.objectId, 'expected_digest': digest},
        [first],
      ),
    );
    expect(result.changes, hasLength(3));
    expect(headings(), ['S2', 'S3']);
    expect(
      store.outline('P').where((row) => row['section_id'] == chain.sectionId),
      isEmpty,
    );
    final added = moduleLog().sublist(beforeModuleLog.length);
    expect(added, hasLength(3));
    expect(added.map((row) => row['object_id']).toSet(), {
      chain.sectionId,
      ...chain.linkIds,
    });
    expect(added.map((row) => row['op']).toSet(), {'delete'});
    expect(importLog(), beforeImportLog);
  });
}
