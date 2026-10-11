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
    root = Directory.systemTemp.createTempSync('reg3d-receipt-');
    host = await MuyonHost.open(p.join(root.path, 'data'));
    await host.activateResearch();
    final store = host.research!.store;
    await store.write(() {
      store.db.execute(
        'INSERT INTO projects(id,title,question,next_step) VALUES(?,?,?,?)',
        ['P', '研究', '问题', '下一步'],
      );
      store.db.execute(
        'INSERT INTO documents(id,project_id,relative_path,snapshot_path,sha256) VALUES(?,?,?,?,?)',
        ['D', 'P', 'a.md', 'a.md', 'h'],
      );
      store.saveNote('D', 'l1', 'note');
      store.saveTask(
        id: 'T',
        projectId: 'P',
        title: 'original',
        goal: 'goal',
        spec: {},
        expectedRevision: 0,
      );
      store.db.execute('INSERT INTO paper_bindings VALUES(?,?,?,?,?,?)', [
        'D',
        'E1',
        1,
        'match',
        1,
        1,
      ]);
      for (final id in ['E1', 'E2']) {
        store.db.execute(
          'INSERT INTO entries(id,project_id,kind,title,data) VALUES(?,?,?,?,?)',
          [id, 'P', 'claim', id, '{}'],
        );
      }
    });
    final file = File(store.documents('P').single.absolutePath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('A document');
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
    invocationId: 'reg3d-receipt-${++invocation}',
    toolId: tool,
    parameters: params,
    scope: AssistantScope.selectedObjects(refs),
  );

  Future<ToolCallResult> approved(ToolCallRequest call) async {
    final approval = await host.tools.approve(await host.tools.prepare(call));
    return host.tools.invoke(call.withApproval(approval));
  }

  test('report resolution failure rolls back project and change log', () async {
    final store = host.research!.store;
    final selected = await current('project', 'P');
    final beforeRows = store.db
        .select('SELECT * FROM projects')
        .map((r) => Map<String, Object?>.from(r))
        .toList();
    final beforeLog = store.db
        .select('SELECT * FROM muyon_change_log')
        .map((r) => Map<String, Object?>.from(r))
        .toList();
    // The domain UPDATE completes. Only its subsequent report resolution
    // reads the malformed title and throws, inside that same transaction.
    store.db.execute(
      "CREATE TRIGGER fail_report AFTER UPDATE OF question ON projects WHEN NEW.question='report-fault' BEGIN UPDATE projects SET title=X'00' WHERE id=NEW.id; END",
    );
    final call = request(
      'research.update_project',
      {
        'project_id': 'P',
        'question': 'report-fault',
        'next_step': 'must roll back',
        'expected_digest': selected.contentDigest,
      },
      [selected],
    );
    final result = await approved(call);
    expect(result.status, ToolCallStatus.interrupted);
    expect(
      store.db
          .select('SELECT * FROM projects')
          .map((r) => Map<String, Object?>.from(r))
          .toList(),
      beforeRows,
    );
    expect(
      store.db
          .select('SELECT * FROM muyon_change_log')
          .map((r) => Map<String, Object?>.from(r))
          .toList(),
      beforeLog,
    );
    expect(store.db.autocommit, isTrue);
    final receipt = host.tools.receiptFor(call.invocationId)!;
    expect(receipt.state, 'interrupted');
    expect(receipt.result!.status, ToolCallStatus.interrupted);
    expect(receipt.result!.changes, isEmpty);
  });

  for (final tool in [
    'update_project',
    'set_note_entry',
    'create_task',
    'revise_task',
    'confirm_binding',
  ]) {
    for (final deleteAfterCommit in [false, true]) {
      test(
        '$tool receipt keeps A snapshot when B ${deleteAfterCommit ? 'deletes' : 'updates'} after commit',
        () async {
          final original = host.research!;
          final store = original.store;
          final noteId = store.notes('D').single.id;
          final type = switch (tool) {
            'update_project' => 'project',
            'set_note_entry' => 'note',
            'create_task' => 'project',
            'revise_task' => 'task',
            _ => 'document',
          };
          final id = switch (tool) {
            'set_note_entry' => noteId,
            'revise_task' => 'T',
            'confirm_binding' => 'D',
            _ => 'P',
          };
          final selected = await current(type, id);
          final params = switch (tool) {
            'update_project' => <String, Object?>{
              'project_id': 'P',
              'question': 'A',
              'next_step': 'A next',
              'expected_digest': selected.contentDigest,
            },
            'set_note_entry' => <String, Object?>{
              'note_id': noteId,
              'entry_id': 'E1',
              'expected_digest': selected.contentDigest,
            },
            'create_task' => <String, Object?>{
              'project_id': 'P',
              'title': 'A',
              'goal': 'A goal',
            },
            'revise_task' => <String, Object?>{
              'task_id': 'T',
              'expected_revision': 1,
              'title': 'A',
              'goal': 'A goal',
            },
            _ => <String, Object?>{'document_id': 'D', 'paper_id': 'E1'},
          };
          if (tool == 'confirm_binding') {
            final bindings = await host.tools.invoke(
              request(
                'research.list_bindings',
                {'project_id': 'P'},
                [await current('project', 'P')],
              ),
            );
            expect(
              bindings.status,
              ToolCallStatus.succeeded,
              reason: bindings.summary,
            );
            params['expected_digest'] =
                ((bindings.data['bindings'] as List).single as Map)['digest'];
          }
          final refs = [
            selected,
            if (tool == 'set_note_entry') await current('entry', 'E1'),
          ];
          final resources = original.resources;
          late ObjectRef committedA;
          var bCommitted = false;
          final observed = _AfterCommitDatabase(resources.database, () async {
            expect(resources.database.raw.autocommit, isTrue);
            final resultType = tool == 'create_task' ? 'task' : type;
            final resultId = tool == 'create_task'
                ? store.db
                          .select("SELECT id FROM tasks WHERE title='A'")
                          .single['id']
                      as String
                : id;
            committedA = await current(resultType, resultId);
            if (tool == 'update_project') {
              expect(store.projects().single.question, 'A');
            }
            if (tool == 'set_note_entry') {
              expect(store.notes('D').single.entryId, 'E1');
            }
            if (tool == 'create_task' || tool == 'revise_task') {
              expect(
                store
                    .taskRevision(resultId, int.parse(committedA.revisionRef!))!
                    .title,
                'A',
              );
            }
            if (tool == 'confirm_binding') {
              expect(store.bindings('P').single.ambiguous, isFalse);
            }
            await store.write(() {
              if (deleteAfterCommit) {
                final table = switch (resultType) {
                  'project' => 'projects',
                  'note' => 'notes',
                  'task' => 'tasks',
                  _ => 'documents',
                };
                if (resultType == 'project') {
                  store.db.execute('DELETE FROM paper_bindings');
                  store.db.execute('DELETE FROM notes');
                  store.db.execute('DELETE FROM documents');
                  store.db.execute('DELETE FROM entries');
                  store.db.execute('DELETE FROM tasks');
                }
                if (resultType == 'document') {
                  store.db.execute(
                    'DELETE FROM paper_bindings WHERE document_id=?',
                    [resultId],
                  );
                  store.db.execute('DELETE FROM notes WHERE document_id=?', [
                    resultId,
                  ]);
                }
                store.db.execute('DELETE FROM $table WHERE id=?', [resultId]);
              } else {
                switch (tool) {
                  case 'update_project':
                    store.saveProject('P', question: 'B', nextStep: 'B next');
                  case 'set_note_entry':
                    store.setNoteEntry(noteId, 'E2');
                  case 'create_task' || 'revise_task':
                    store.saveTask(
                      id: resultId,
                      projectId: 'P',
                      title: 'B',
                      goal: 'B goal',
                      spec: {},
                      expectedRevision: int.parse(committedA.revisionRef!),
                    );
                  case 'confirm_binding':
                    File(store.documents('P').single.absolutePath)
                        .writeAsStringSync('B document');
                }
              }
            });
            bCommitted = true;
          });
          host.modules.setRuntimeForTesting(
            'research',
            ResearchRuntime(
              ModuleResources(
                database: observed,
                files: resources.files,
                capabilities: resources.capabilities,
              ),
            ),
          );
          final call = request('research.$tool', params, refs);
          final result = await approved(call);
          expect(bCommitted, isTrue);
          expect(observed.interceptions, 1);
          expect(
            result.status,
            ToolCallStatus.succeeded,
            reason: result.summary,
          );
          expect(host.tools.receiptFor(call.invocationId)!.state, 'succeeded');
          // Re-read the persisted JSON after B has committed; the returned
          // result alone cannot prove durable recovery retains A's snapshot.
          final persisted = host.tools.receiptFor(call.invocationId)!.result!;
          expect(persisted.objectRefs.map((ref) => ref.toJson()).toList(), [
            committedA.toJson(),
          ]);
          expect(
            persisted.objectRefs.single.contentDigest,
            committedA.contentDigest,
          );
          expect(
            persisted.objectRefs.single.revisionRef,
            committedA.revisionRef,
          );
          expect(persisted.objectRefs.single.toJson(), committedA.toJson());
          // ChangeOp persistence is deferred by CR13 N-3.
          expect(persisted.changes, isEmpty);
          expect(persisted.toJson(), result.toJson());
          expect(result.objectRefs.single.toJson(), committedA.toJson());
          expect(result.changes.single.ref.toJson(), committedA.toJson());
          expect(result.changes.single.op, ChangeOp.upsert);
          if (!deleteAfterCommit) {
            final latest = await current(
              committedA.objectType,
              committedA.objectId,
            );
            expect(latest.toJson(), isNot(committedA.toJson()));
            // Task refs carry revisionRef instead of contentDigest.
            final persistedRef = persisted.objectRefs.single;
            if (persistedRef.contentDigest != null) {
              expect(persistedRef.contentDigest, isNot(latest.contentDigest));
            } else {
              expect(persistedRef.revisionRef, isNot(latest.revisionRef));
            }
          }
        },
      );
    }
  }
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
