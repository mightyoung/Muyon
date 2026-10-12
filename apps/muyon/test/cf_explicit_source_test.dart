import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/inquiry_ui_planning_source.dart';
import 'package:muyon/platform/ui_workspace_store.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:muyon_module_api/ui_contract.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/aiui6_snapshot_fixture.dart';

void main() {
  late InquirySnapshotFixture f;
  setUp(() async => f = await InquirySnapshotFixture.open());
  tearDown(() async => f.close());

  Future<PersonalTask> taskFor(List<ObjectRef> refs) async {
    final conversation = await f.host.foundation.createConversation(
      scope: AssistantScope.selectedObjects(refs),
    );
    return f.host.personalAgent.start(
      conversationId: conversation.id,
      prompt: '本地只读事实',
    );
  }

  for (final selection in ['multi', 'mixed', 'unsupported']) {
    test(
      'rejects $selection selection instead of silently choosing a target',
      () async {
        final selected = f.refs['project_item']!;
        const unsupported = ObjectRef(
          moduleId: 'inquiry',
          objectType: 'supplier',
          objectId: 'not-read',
          revisionRef: '1',
          contentDigest: 'not-read',
        );
        const foreign = ObjectRef(
          moduleId: 'research',
          objectType: 'note',
          objectId: 'not-read',
          revisionRef: '1',
          contentDigest: 'not-read',
        );
        final refs = switch (selection) {
          'multi' => [selected, f.refs['quotation']!],
          'mixed' => [selected, foreign],
          _ => [unsupported],
        };
        final task = await taskFor(refs);
        expect(await InquiryUiPlanningSource(f.host).read(task), isNull);
        expect(f.host.tools.history(), isEmpty);
      },
    );
  }

  test('host scope rejects duplicate identities before source admission', () {
    final ref = f.refs['project_item']!;
    expect(
      () => AssistantScope.selectedObjects([ref, ref]),
      throwsArgumentError,
    );
  });

  Map<String, Object?> persistedState() {
    final paths = <String>{
      f.host.foundation.database.raw
              .select('PRAGMA database_list')
              .single['file']
          as String,
      f.host.inquiry!.runtime.state.store.db
              .select('PRAGMA database_list')
              .single['file']
          as String,
    };
    return {
      for (final path in paths)
        path: (() {
          final db = sqlite3.open(path, mode: OpenMode.readOnly);
          try {
            return {
              for (final row in db.select(
                "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
              ))
                row['name'] as String: db
                    .select(
                      'SELECT * FROM "${(row['name'] as String).replaceAll('"', '""')}"',
                    )
                    .map((row) => Map<String, Object?>.from(row))
                    .toList(),
            };
          } finally {
            db.close();
          }
        })(),
    };
  }

  test(
    'real single target keeps masked and lossy field provenance conservative',
    () async {
      final ref = f.refs['project_item']!;
      final task = await taskFor([ref]);
      final before = persistedState();
      final result = (await InquiryUiPlanningSource(f.host).read(task))!;
      expect(
        persistedState(),
        before,
        reason: 'independent read-only connections include records, change logs and host ledgers',
      );
      expect(result.snapshot.facts['saved-source']!.state, FactState.verified);
      expect(result.snapshot.facts['saved-name']!.value, '真实预算行');
      expect(result.snapshot.facts['saved-name']!.state, FactState.unverified);
      expect(
        result.snapshot.facts['saved-requirement']!.state,
        FactState.unverified,
      );
      expect(
        result.snapshot.facts['saved-unit_cost']!.state,
        FactState.notDisclosed,
      );
      expect(result.snapshot.facts['saved-unit_cost']!.value, '已遮盖');
      expect(
        jsonEncode(
          result.snapshot.facts.values.map((fact) => fact.value).toList(),
        ),
        isNot(contains('987654.123')),
      );
      expect(
        result.snapshot.facts.values.every((fact) => fact.object == ref),
        isTrue,
      );
      expect(
        result.snapshot.facts.keys.any((key) => key.contains('suggestion')),
        isFalse,
      );
    },
  );

  test(
    'generic checkpoint raw values never enter the readonly model source',
    () async {
      final task = await taskFor([f.refs['project_item']!]);
      final store = HostUiWorkspaceStore(f.host.foundation, taskId: task.id);
      const raw = 'COMMERCIAL-CHECKPOINT-RAW-987654.123';
      final checkpoint = StoredUiWorkspace(
        taskId: task.id,
        surfaceId: 'task-${task.id}',
        scopeKey: store.scopeKey!,
        revision: 1,
        schemaVersion: 2,
        catalogVersion: 'library-2',
        snapshotRef: const SnapshotRef('checkpoint', 1),
        intentRef: 'readonly',
        planRevision: 7,
        draftRevision: 1,
        extracted: const {'price': raw},
        userOverrides: const {'credential': raw},
        viewValues: const {'view': raw},
        readableDraft: const {'draft': raw},
        nodeIds: const ['price'],
      );
      expect(await store.save(checkpoint, expectedRevision: 0), isTrue);
      final before = persistedState();
      final result = (await InquiryUiPlanningSource(f.host).read(task))!;
      final request = UiPlanningRequest(
        question: 'Read locally saved facts',
        answer: '',
        conversationMessages: const [],
        conversationVersion: '1',
        coverage: 'selected',
        taskId: task.id,
        turnId: task.id,
        snapshot: result.snapshot,
        intent: result.intent,
        currentView: result.currentView,
        catalog: result.catalog,
        allowedActionRefs: result.allowedActionRefs,
        mode: UiPlanningMode.motivation,
      );
      final modelState = jsonEncode(request.toJson());
      expect(modelState, isNot(contains(raw)));
      expect(result.snapshot.initialUiState, isEmpty);
      expect(result.currentView.values, isEmpty);
      expect(result.currentView.revision, 7);
      expect(persistedState(), before);
      expect(
        (await store.load('task-${task.id}'))!.displayValues.values,
        contains(raw),
      );
    },
  );

  for (final change in ['failed', 'internal', 'conversation', 'deleted']) {
    test(
      'late $change task cannot publish a source after an awaited read',
      () async {
        final task = await taskFor([f.refs['project_item']!]);
        final other = await f.host.foundation.createConversation(
          scope: task.scope,
        );
        final reading = InquiryUiPlanningSource(f.host).read(task);
        scheduleMicrotask(() {
          final db = f.host.foundation.database.raw;
          if (change == 'deleted') {
            db.execute('DELETE FROM execution_records WHERE id=?', [task.id]);
          } else {
            final payload = <String, Object?>{...task.payload};
            switch (change) {
              case 'failed':
                payload['state'] = 'failed';
              case 'internal':
                payload['uiPlanningInternal'] = true;
              case 'conversation':
                payload['conversationId'] = other.id;
            }
            db.execute('UPDATE execution_records SET payload=? WHERE id=?', [
              jsonEncode(payload),
              task.id,
            ]);
          }
        });
        expect(await reading, isNull);
      },
    );
  }

  test('model-shaped target payload cannot enlarge host selection', () async {
    final ref = f.refs['project_item']!;
    final task = await taskFor([ref]);
    final supplied = task.copy({
      'target': f.refs['quotation']!.toJson(),
      'scope': AssistantScope.selectedObjects([f.refs['quotation']!]).toJson(),
    });
    final result = (await InquiryUiPlanningSource(f.host).read(supplied))!;
    expect(
      result.snapshot.facts.values.every((fact) => fact.object == ref),
      isTrue,
    );
  });
}
