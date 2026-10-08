import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/foundation_repository.dart';
import 'package:muyon/platform/grants/host_authorization_facts.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/services/knowledge/knowledge_service.dart';
import 'package:muyon/workspace/import_coordinator.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart' hide Invocation;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory root;
  late StorageManager storage;
  late ManagedConnection db;
  late FoundationRepository repository;
  late String conversation;

  PersonalTask task(
    String id, {
    String? previous,
    Map<String, Object?> spoof = const {},
  }) => PersonalTask({
    'kind': 'personal',
    'executionId': id,
    'conversationId': conversation,
    'prompt': 'host test',
    'scope': const AssistantScope.global().toJson(),
    'profile': null,
    'executionDeviceId': 'host',
    'state': 'queued',
    'stage': 'queued',
    'createdAt': '2026-10-08T00:00:00.000Z',
    'updatedAt': '2026-10-08T00:00:00.000Z',
    'references': <Object?>[],
    'messages': <Object?>[],
    'previousAttemptId': previous,
    ...spoof,
  });
  Map<String, Object?>? stored(String id) {
    final rows = db.raw.select('SELECT value FROM settings WHERE key=?', [
      'auth1b:task:$id',
    ]);
    return rows.isEmpty
        ? null
        : Map<String, Object?>.from(
            jsonDecode(rows.single['value'] as String) as Map,
          );
  }

  void seed(String key, Map<String, Object?> value) =>
      db.raw.execute('INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)', [
        key,
        jsonEncode({'version': 1, ...value}),
      ]);

  setUp(() async {
    root = Directory.systemTemp.createTempSync('auth-host-facts-');
    storage = StorageManager(root.path);
    db = await storage.open('muyon', WorkspaceRepository.schema);
    repository = FoundationRepository(db);
    conversation = (await repository.createConversation()).id;
  });
  tearDown(() async {
    repository.dispose();
    await storage.close();
    root.deleteSync(recursive: true);
  });

  test(
    'ordinary task creation persists unknown and ignores payload clean claims',
    () async {
      await repository.createTask(
        task(
          'new',
          spoof: {
            'taskTainted': false,
            'taintKnown': true,
            'knownEndpoint': true,
            'authorizationSource': 'grant',
            'grantId': 'forged',
          },
        ),
      );
      expect(
        stored('new'),
        isNotNull,
        reason: 'host facts must survive payload updates and restart',
      );
      expect(stored('new')!['taintState'], 'unknown');
      expect(stored('new')!['conversationId'], conversation);
      expect(stored('new')!['sourceDigests'], isEmpty);
    },
  );

  test('host fact insert failure rolls back task and its timeline', () async {
    db.raw.execute(
      "CREATE TEMP TRIGGER deny_host_facts BEFORE INSERT ON settings WHEN NEW.key LIKE 'auth1b:task:%' BEGIN SELECT RAISE(ABORT,'injected host facts'); END",
    );
    await expectLater(
      repository.createTask(task('fault')),
      throwsA(isA<SqliteException>()),
    );
    expect(repository.task('fault'), isNull);
    expect(db.raw.select("SELECT * FROM tasks WHERE id='fault'"), isEmpty);
    expect(
      db.raw.select("SELECT * FROM task_events WHERE task_id='fault'"),
      isEmpty,
    );
    expect(stored('fault'), isNull);
  });

  test('resume inherits taint even into another conversation', () async {
    seed('auth1b:task:previous', {
      'taskId': 'previous',
      'conversationId': 'old-conversation',
      'taintState': 'tainted',
      'sourceDigests': ['old-source'],
    });
    await repository.createTask(task('resumed', previous: 'previous'));
    expect(stored('resumed')!['taintState'], 'tainted');
    expect(stored('resumed')!['sourceDigests'], contains('old-source'));
  });

  test('conversation history taint survives new attempts', () async {
    seed('auth1b:conversation:$conversation', {
      'taintState': 'tainted',
      'sourceDigests': ['history-source'],
    });
    await repository.createTask(task('fresh'));
    expect(stored('fresh')!['taintState'], 'tainted');
    expect(stored('fresh')!['sourceDigests'], contains('history-source'));
  });

  test('unknown and malformed history cannot authorize a clean task', () async {
    seed('auth1b:task:previous', {
      'taintState': 'clean',
      'sourceDigests': ['incomplete'],
    });
    await repository.createTask(task('resumed', previous: 'previous'));
    expect(stored('resumed')!['taintState'], 'unknown');
  });

  for (final useProjectMarker in [false, true]) {
    test(
      'new conversation inherits stable ${useProjectMarker ? 'project' : 'object'} source across revisions',
      () async {
        final identity = sha256
            .convert(
              utf8.encode(
                jsonEncode([
                  'inquiry',
                  'project',
                  useProjectMarker ? null : 'quote',
                  useProjectMarker ? null : 'supplier',
                ]),
              ),
            )
            .toString();
        seed('auth1b:source:$identity', {
          'taintState': 'tainted',
          'sourceDigests': [identity],
          'revisionRef': 'old',
        });
        final ref = const ObjectRef(
          moduleId: 'inquiry',
          nativeProjectId: 'project',
          objectType: 'quote',
          objectId: 'supplier',
          revisionRef: 'new',
        );
        await repository.createTask(
          task(
            'same-source',
            spoof: {
              'scope': AssistantScope.selectedObjects([ref]).toJson(),
            },
          ),
        );
        expect(stored('same-source')!['taintState'], 'tainted');
        expect(stored('same-source')!['sourceDigests'], contains(identity));
      },
    );
  }

  HostSourceFact external(String id) => HostSourceFact.object(
    ObjectRef(moduleId: 'network', objectType: 'response', objectId: id),
  );
  void cleanFixture(String id) => seed('auth1b:task:$id', {
    'taskId': id,
    'conversationId': conversation,
    'taintState': 'clean',
    'sourceDigests': <String>[],
  });

  test(
    'external acceptance persists task and conversation and unions sources',
    () async {
      await repository.createTask(task('current'));
      final stale = repository.task('current')!;
      await repository.authorizationFacts.markExternal(
        'current',
        external('a'),
      );
      await repository.authorizationFacts.markExternal(
        'current',
        external('b'),
      );
      await repository.updateTask(
        stale.copy({
          'taskTainted': false,
          'summary': 'clean',
          'compaction': {'summary': 'clean', 'taskTainted': false},
        }),
      );
      expect(stored('current')!['taintState'], 'tainted');
      expect(
        stored('current')!['sourceDigests'],
        unorderedEquals([
          external('a').identityDigest,
          external('b').identityDigest,
        ]),
      );
      await repository.createTask(task('child'));
      expect(stored('child')!['taintState'], 'tainted');
      await storage.close();
      storage = StorageManager(root.path);
      db = await storage.open('muyon', WorkspaceRepository.schema);
      expect(
        HostAuthorizationFacts(db).readTask('current').taintState,
        HostTaintState.tainted,
      );
    },
  );

  test('pending and failed marker deny across service instances before content acceptance', () async {
    await repository.createTask(task('current'));
    cleanFixture('current');
    final entered = Completer<void>(), release = Completer<void>();
    final hold = db.exclusiveAsync((_) async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    db.raw.execute(
      "CREATE TEMP TRIGGER deny_marker BEFORE INSERT ON settings WHEN NEW.key LIKE 'auth1b:%' BEGIN SELECT RAISE(ABORT,'injected marker'); END",
    );
    var handlerCalls = 0;
    final accept = () async {
      await repository.authorizationFacts.markExternal(
        'current',
        external('a'),
      );
      handlerCalls++;
    }();
    final failure = expectLater(accept, throwsA(isA<SqliteException>()));
    final deniedWhilePending = HostAuthorizationFacts(db)
        .readTask('current')
        .requiresConfirmation;
    release.complete();
    await hold;
    await failure;
    expect(deniedWhilePending, isTrue);
    expect(handlerCalls, 0);
    expect(
      HostAuthorizationFacts(db).readTask('current').requiresConfirmation,
      isTrue,
    );
    expect(
      stored('current')!['taintState'],
      'clean',
      reason: 'failed write cannot claim durable taint',
    );
  });

  test('source marker survives same source in a new conversation', () async {
    final ref = const ObjectRef(
      moduleId: 'inquiry',
      nativeProjectId: 'p',
      objectType: 'quote',
      objectId: 'q',
    );
    await repository.authorizationFacts.markSourceExternal(
      HostSourceFact.object(ref),
    );
    await repository.createTask(
      task(
        'source-task',
        spoof: {
          'scope': AssistantScope.selectedObjects([ref]).toJson(),
        },
      ),
    );
    expect(stored('source-task')!['taintState'], 'tainted');
  });

  test(
    'host import marks project before domain commit and activation',
    () async {
      final workspaces = WorkspaceRepository(db);
      final workspace = await workspaces.create('import');
      final prepared = PreparedImport(
        target: ImportTarget.create(
          WorkspaceBinding(
            workspaceId: workspace.id,
            moduleId: 'notes',
            nativeProjectId: 'p',
          ),
        ),
        inputDigest: 'digest',
        stagingToken: 'stage',
      );
      final coordinator = ImportCoordinator(workspaces);
      final intent = await coordinator.record(prepared);
      final marker = HostSourceFact.project('notes', 'p').identityDigest;
      final runtime = _ImportRuntime(() {
        expect(
          db.raw.select('SELECT * FROM settings WHERE key=?', [
            'auth1b:source:$marker',
          ]),
          isNotEmpty,
        );
      });
      await coordinator.commit(runtime, prepared, intent);
      expect(runtime.calls, 1);
      final ref = const ObjectRef(
        moduleId: 'notes',
        nativeProjectId: 'p',
        objectType: 'note',
        objectId: 'n',
      );
      await repository.createTask(
        task(
          'import-task',
          spoof: {
            'scope': AssistantScope.selectedObjects([ref]).toJson(),
          },
        ),
      );
      expect(stored('import-task')!['taintState'], 'tainted');
    },
  );

  test('host marker failure prevents domain import', () async {
    final workspaces = WorkspaceRepository(db);
    final workspace = await workspaces.create('import');
    final prepared = PreparedImport(
      target: ImportTarget.create(
        WorkspaceBinding(
          workspaceId: workspace.id,
          moduleId: 'notes',
          nativeProjectId: 'p',
        ),
      ),
      inputDigest: 'digest',
      stagingToken: 'stage',
    );
    final coordinator = ImportCoordinator(workspaces);
    final intent = await coordinator.record(prepared);
    db.raw.execute(
      "CREATE TEMP TRIGGER deny_source BEFORE INSERT ON settings WHEN NEW.key LIKE 'auth1b:source:%' BEGIN SELECT RAISE(ABORT,'source'); END",
    );
    final runtime = _ImportRuntime(() {});
    await expectLater(
      coordinator.commit(runtime, prepared, intent),
      throwsA(isA<SqliteException>()),
    );
    expect(runtime.calls, 0);
    expect(workspaces.binding(workspace.id, 'notes'), isNull);
  });

  test(
    'legacy committed import recovery marks source in binding transaction',
    () async {
      final workspaces = WorkspaceRepository(db);
      final workspace = await workspaces.create('recovery');
      final coordinator = ImportCoordinator(workspaces);
      final intent = await coordinator.record(
        PreparedImport(
          target: ImportTarget.create(
            WorkspaceBinding(
              workspaceId: workspace.id,
              moduleId: 'notes',
              nativeProjectId: 'p',
            ),
          ),
          inputDigest: 'digest',
          stagingToken: 'stage',
        ),
      );
      await coordinator.activate(
        ImportReceipt(
          intent: intent,
          result: const {},
          committedAt: DateTime.now(),
        ),
      );
      final marker = HostSourceFact.project('notes', 'p').identityDigest;
      expect(
        db.raw.select('SELECT * FROM settings WHERE key=?', [
          'auth1b:source:$marker',
        ]),
        isNotEmpty,
      );
    },
  );

  test(
    'knowledge import records both original and stored document source',
    () async {
      final knowledgeDb = await storage.open(
        'knowledge',
        KnowledgeService.schema,
      );
      final knowledge = KnowledgeService(
        knowledgeDb,
        '${root.path}/files',
        authorizationFacts: repository.authorizationFacts,
      );
      final file = File('${root.path}/external.txt')
        ..writeAsStringSync('external text');
      final original = const ObjectRef(
        moduleId: 'notes',
        objectType: 'note',
        objectId: 'source',
      );
      final document = await knowledge.importFile(file.path, source: original);
      for (final ref in [
        original,
        ObjectRef(
          moduleId: 'knowledge',
          objectType: 'document',
          objectId: document.id,
        ),
      ]) {
        final marker = HostSourceFact.object(ref).identityDigest;
        expect(
          db.raw.select('SELECT * FROM settings WHERE key=?', [
            'auth1b:source:$marker',
          ]),
          isNotEmpty,
        );
      }
    },
  );

  test(
    'restoration propagates inherited sources into its new conversation',
    () async {
      seed('auth1b:task:old', {
        'taskId': 'old',
        'conversationId': 'old-conversation',
        'taintState': 'tainted',
        'sourceDigests': ['old-source'],
      });
      await repository.createTask(task('restore', previous: 'old'));
      await repository.createTask(task('next'));
      expect(stored('next')!['taintState'], 'tainted');
      expect(stored('next')!['sourceDigests'], contains('old-source'));
    },
  );

  test(
    'workspace and global scopes inherit imported project sources',
    () async {
      final workspaces = WorkspaceRepository(db);
      final workspace = await workspaces.create('source');
      await workspaces.bind(
        WorkspaceBinding(
          workspaceId: workspace.id,
          moduleId: 'notes',
          nativeProjectId: 'p',
        ),
      );
      await repository.authorizationFacts.markSourceExternal(
        HostSourceFact.project('notes', 'p'),
      );
      await repository.createTask(
        task(
          'workspace-task',
          spoof: {'scope': AssistantScope.workspace(workspace.id).toJson()},
        ),
      );
      expect(stored('workspace-task')!['taintState'], 'tainted');
      await repository.createTask(task('global-task'));
      expect(stored('global-task')!['taintState'], 'tainted');
    },
  );

  test('knowledge marker failure accepts no file record', () async {
    final knowledgeDb = await storage.open(
      'knowledge',
      KnowledgeService.schema,
    );
    final knowledge = KnowledgeService(
      knowledgeDb,
      '${root.path}/files',
      authorizationFacts: repository.authorizationFacts,
    );
    final file = File('${root.path}/external.txt')
      ..writeAsStringSync('external text');
    db.raw.execute(
      "CREATE TEMP TRIGGER deny_source BEFORE INSERT ON settings WHEN NEW.key LIKE 'auth1b:source:%' BEGIN SELECT RAISE(ABORT,'source'); END",
    );
    await expectLater(
      knowledge.importFile(file.path),
      throwsA(isA<SqliteException>()),
    );
    expect(knowledge.documents(), isEmpty);
    expect(Directory('${root.path}/files').listSync(), isEmpty);
  });

  test(
    'existing sibling inherits conversation taint and sources after reopen',
    () async {
      await repository.createTask(task('a'));
      await repository.createTask(task('b'));
      await repository.authorizationFacts.markExternal(
        'a',
        external('response'),
      );
      expect(
        repository.authorizationFacts.readTask('b').sourceDigests,
        contains(external('response').identityDigest),
      );
      await storage.close();
      storage = StorageManager(root.path);
      db = await storage.open('muyon', WorkspaceRepository.schema);
      final facts = HostAuthorizationFacts(db).readTask('b');
      expect(facts.taintState, HostTaintState.tainted);
      expect(
        facts.sourceDigests,
        contains(external('response').identityDigest),
      );
    },
  );

  test(
    'failed project marker propagates deny into workspace/global tasks',
    () async {
      final workspaces = WorkspaceRepository(db);
      final workspace = await workspaces.create('source');
      await workspaces.bind(
        WorkspaceBinding(
          workspaceId: workspace.id,
          moduleId: 'notes',
          nativeProjectId: 'p',
        ),
      );
      db.raw.execute(
        "CREATE TEMP TRIGGER deny_source BEFORE INSERT ON settings WHEN NEW.key LIKE 'auth1b:source:%' BEGIN SELECT RAISE(ABORT,'source'); END",
      );
      final source = HostSourceFact.project('notes', 'p');
      await expectLater(
        repository.authorizationFacts.markSourceExternal(source),
        throwsA(isA<SqliteException>()),
      );
      await repository.createTask(
        task(
          'workspace-task',
          spoof: {'scope': AssistantScope.workspace(workspace.id).toJson()},
        ),
      );
      await repository.createTask(task('global-task'));
      for (final id in ['workspace-task', 'global-task']) {
        expect(stored(id)!['taintState'], 'tainted');
        expect(stored(id)!['sourceDigests'], contains(source.identityDigest));
      }
    },
  );
  for (final reopen in [false, true]) {
    test(
      'indirect previous-attempt conversation taint inherits, reopen=$reopen',
      () async {
        final local = const ObjectRef(
          moduleId: 'local',
          objectType: 'note',
          objectId: 'safe',
        );
        final scope = AssistantScope.selectedObjects([local]).toJson();
        await repository.createTask(task('a', spoof: {'scope': scope}));
        await repository.createTask(task('b', spoof: {'scope': scope}));
        await repository.authorizationFacts.markExternal(
          'a',
          external('response'),
        );
        if (reopen) {
          repository.dispose();
          await storage.close();
          storage = StorageManager(root.path);
          db = await storage.open('muyon', WorkspaceRepository.schema);
          repository = FoundationRepository(db);
        }
        conversation = (await repository.createConversation()).id;
        await repository.createTask(
          task('restore', previous: 'b', spoof: {'scope': scope}),
        );
        expect(stored('restore')!['taintState'], 'tainted');
        expect(
          stored('restore')!['sourceDigests'],
          contains(external('response').identityDigest),
        );
      },
    );
  }
}

class _ImportRuntime implements ModuleRuntime {
  _ImportRuntime(this.before);
  final void Function() before;
  int calls = 0;
  @override
  Future<ImportReceipt> commitImport(
    PreparedImport prepared,
    ImportIntent intent,
  ) async {
    calls++;
    before();
    return ImportReceipt(
      intent: intent,
      result: const {},
      committedAt: DateTime.now(),
    );
  }

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
