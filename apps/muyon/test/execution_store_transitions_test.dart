import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/assistant/execution_store.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

/// Execution records are the durable state of assistant runs: only queued
/// records can be created, transitions validate the current state, and object
/// and artifact references must survive the encode/decode round-trip.
void main() {
  ManagedConnection database() {
    final db = ManagedConnection(sqlite3.openInMemory());
    for (final migration in WorkspaceRepository.schema.migrations) {
      migration.migrate(db.raw);
    }
    return db;
  }

  const current = ObjectRef(
    moduleId: 'test',
    objectType: 'item',
    objectId: 'current',
    nativeProjectId: 'project',
  );
  const selected = ObjectRef(
    moduleId: 'test',
    objectType: 'item',
    objectId: 'selected',
    nativeProjectId: 'project',
  );
  final artifact = ArtifactRef(
    moduleId: 'test',
    artifactId: 'artifact-1',
    contentDigest: 'digest-1',
  );

  AgentExecutionRecord record(
    String id, {
    ExecutionState state = ExecutionState.queued,
    List<ObjectRef> resultRefs = const [],
    List<ArtifactRef> artifactRefs = const [],
  }) => AgentExecutionRecord(
    executionId: id,
    toolId: 'test.tool',
    contextSnapshot: ContextRef(
      workspaceId: 'workspace',
      moduleId: 'test',
      nativeProjectId: 'project',
      currentObjectRef: current,
      selectedObjectRefs: const [selected],
    ),
    executionDeviceId: 'device',
    state: state,
    stage: state.name,
    createdAt: DateTime.utc(2026, 10, 5),
    updatedAt: DateTime.utc(2026, 10, 5),
    resultRefs: resultRefs,
    artifactRefs: artifactRefs,
  );

  test('create requires queued; unknown and invalid transitions fail', () async {
    final db = database();
    addTearDown(db.close);
    final store = ExecutionStore(db);

    await expectLater(
      store.create(record('a', state: ExecutionState.running)),
      throwsStateError,
    );
    await store.create(record('a'));

    await expectLater(
      store.transition('missing', ExecutionState.running),
      throwsStateError,
    );
    expect(await store.transition('a', ExecutionState.running), isTrue);
    // Running is final for new transitions, and never goes back to queued.
    await expectLater(
      store.transition('a', ExecutionState.running),
      throwsStateError,
    );
    await expectLater(
      store.transition('a', ExecutionState.queued),
      throwsStateError,
    );
    expect(store.get('a')!.state, ExecutionState.running);
  });

  test('object and artifact references survive the round-trip', () async {
    final db = database();
    addTearDown(db.close);
    final store = ExecutionStore(db);

    await store.create(
      record('a', resultRefs: const [selected], artifactRefs: [artifact]),
    );
    final loaded = store.get('a')!;
    expect(loaded.contextSnapshot.currentObjectRef!.objectId, 'current');
    expect(loaded.contextSnapshot.selectedObjectRefs.single.objectId, 'selected');
    expect(loaded.resultRefs.single.objectId, 'selected');
    expect(loaded.artifactRefs.single.artifactId, 'artifact-1');
    expect(loaded.artifactRefs.single.contentDigest, 'digest-1');

    expect(await store.transition('a', ExecutionState.running), isTrue);
    expect(
      await store.transition('a', ExecutionState.succeeded, answer: '答案'),
      isTrue,
    );
    expect(store.answer('a'), '答案');
    expect(store.answer('missing'), isNull);
    expect(store.all().single.executionId, 'a');
    expect(store.get('missing'), isNull);
  });

  test('a refused commit leaves the record untouched', () async {
    final db = database();
    addTearDown(db.close);
    final store = ExecutionStore(db);
    await store.create(record('a'));

    expect(
      await store.transition(
        'a',
        ExecutionState.succeeded,
        canCommit: () => false,
      ),
      isFalse,
    );
    expect(store.get('a')!.state, ExecutionState.queued);
  });
}
