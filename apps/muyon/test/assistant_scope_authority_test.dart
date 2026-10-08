import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/grants/host_scope_authority.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support/fake_v2_module.dart';

void main() {
  late Directory root, files;
  late StorageManager storage;
  late WorkspaceRepository workspaces;
  late ManagedConnection source;
  late HostScopeAuthority authority;
  late String workspace;
  var available = true, epoch = 1;
  String? stamp() =>
      authority.stamp(AssistantScope.workspace(workspace), {'notes'});

  setUp(() async {
    root = Directory.systemTemp.createTempSync('auth-scope-proof-');
    files = Directory('${root.path}/files')..createSync();
    storage = StorageManager('${root.path}/host');
    workspaces = WorkspaceRepository(
      await storage.open('muyon', WorkspaceRepository.schema),
    );
    workspace = (await workspaces.create('project')).id;
    await workspaces.bind(
      WorkspaceBinding(
        workspaceId: workspace,
        moduleId: 'notes',
        nativeProjectId: 'p',
      ),
    );
    source = ManagedConnection(sqlite3.open('${root.path}/notes.sqlite'));
    source.raw.execute('CREATE TABLE records(id TEXT PRIMARY KEY,value TEXT)');
    source.raw.execute("INSERT INTO records VALUES('n','original')");
    available = true;
    epoch = 1;
    authority = HostScopeAuthority(
      workspaces: workspaces,
      sources: {
        'notes': HostScopeSource(
          database: source,
          authorityRevision: () => available ? 'permission-$epoch' : null,
          managedFilesRoot: () => files.path,
        ),
      },
    );
  });
  tearDown(() async {
    await source.close();
    await storage.close();
    root.deleteSync(recursive: true);
  });

  test(
    'real source SQL changes invalidate without a projection/catalog update',
    () async {
      final before = stamp();
      expect(before, isNotNull);
      final catalog = workspaces.database.raw
          .select('SELECT * FROM object_catalog')
          .map((r) => Map<String, Object?>.from(r))
          .toList();
      await source.write(
        (db) => db.execute("UPDATE records SET value='changed' WHERE id='n'"),
      );
      expect(stamp(), isNot(before));
      expect(
        workspaces.database.raw
            .select('SELECT * FROM object_catalog')
            .map((r) => Map<String, Object?>.from(r))
            .toList(),
        catalog,
      );
    },
  );

  test(
    'foreign SQL connection changes invalidate without local total_changes',
    () {
      final before = stamp();
      expect(before, isNotNull);
      final localChanges = source.raw
          .select('SELECT total_changes() AS n')
          .single['n'];
      final other = sqlite3.open('${root.path}/notes.sqlite');
      try {
        other.execute("UPDATE records SET value='foreign' WHERE id='n'");
      } finally {
        other.close();
      }
      expect(
        source.raw.select('SELECT total_changes() AS n').single['n'],
        localChanges,
      );
      expect(stamp(), isNot(before));
    },
  );

  test('grant/audit host writes do not invalidate unchanged scope', () async {
    final before = stamp();
    expect(before, isNotNull);
    await workspaces.setSetting('unrelated-grant-audit-fixture', {'used': 1});
    expect(stamp(), before);
  });

  test(
    'workspace binding and permission availability have real authority',
    () async {
      final before = stamp();
      expect(before, isNotNull);
      await workspaces.database.write(
        (db) => db.execute(
          "UPDATE workspace_module_bindings SET native_project_id='different' WHERE workspace_id=?",
          [workspace],
        ),
      );
      expect(stamp(), isNot(before));
      available = false;
      expect(stamp(), isNull);
      available = true;
      epoch++;
      expect(stamp(), isNot(before));
    },
  );

  test(
    'same-size file change with restored mtime invalidates by actual bytes',
    () {
      final file = File('${files.path}/content.txt')..writeAsStringSync('abcd');
      final modified = file.lastModifiedSync();
      final before = stamp();
      expect(before, isNotNull);
      file.writeAsStringSync('wxyz');
      file.setLastModifiedSync(modified);
      expect(file.lengthSync(), 4);
      expect(stamp(), isNot(before));
    },
  );

  test(
    'source async exclusive work and queued writes return unknown',
    () async {
      final before = stamp();
      expect(before, isNotNull);
      final entered = Completer<void>(), release = Completer<void>();
      final hold = source.exclusiveAsync((db) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final busyStamp = stamp();
      final write = source.write(
        (db) => db.execute("UPDATE records SET value='queued' WHERE id='n'"),
      );
      final queuedStamp = stamp();
      release.complete();
      await hold;
      await write;
      expect(busyStamp, isNull);
      expect(queuedStamp, isNull);
      expect(stamp(), isNot(before));
    },
  );

  test(
    'unmanaged files, symlinks and unsupported module coverage stay unknown',
    () {
      expect(
        authority.stamp(const AssistantScope.global(), {'missing'}),
        isNull,
      );
      Link('${files.path}/link').createSync('${root.path}/notes.sqlite');
      expect(stamp(), isNull);
      final unknown = HostScopeAuthority(
        workspaces: workspaces,
        sources: {
          'notes': HostScopeSource(
            database: source,
            authorityRevision: () => 'permission',
            managedFilesRoot: () => null,
          ),
        },
      );
      expect(
        unknown.stamp(AssistantScope.workspace(workspace), {'notes'}),
        isNull,
      );
    },
  );
  test('real host source producer follows prototype database/files and module authority', () async {
    final host = await MuyonHost.open('${root.path}/actual-host');
    try {
      String? realStamp() => host.scopeAuthority.stamp(
        const AssistantScope.global(),
        {'prototype'},
      );
      expect(realStamp(), isNull, reason: 'inactive source has no authority');
      await host.activatePrototype();
      final build = Directory('${root.path}/build')..createSync();
      File('${build.path}/index.html').writeAsStringSync('<p>one</p>');
      final version = await host.prototype!.store.importBuild(
        sourceDir: build.path,
        title: 'fixture',
      );
      await host.projections.idle('prototype');
      final before = realStamp();
      expect(before, isNotNull);
      File('${version.directory}/index.html').writeAsStringSync('<p>two</p>');
      expect(realStamp(), isNot(before));
      final filesChanged = realStamp();
      await host.prototype!.store.addFeedback(
        versionId: version.id,
        text: 'new',
      );
      await host.projections.idle('prototype');
      expect(realStamp(), isNot(filesChanged));
      host.modules.stopAdmission();
      expect(realStamp(), isNull, reason: 'host admission/authority closed');
    } finally {
      await host.close();
    }
  });
  test(
    'a source changed while proving another source returns unknown',
    () async {
      final other = ManagedConnection(sqlite3.openInMemory());
      final otherFiles = Directory('${root.path}/other-files')..createSync();
      var changeFirst = true;
      final mixed = HostScopeAuthority(
        workspaces: workspaces,
        sources: authority.sources,
        contextSources: [
          HostScopeSource(
            database: other,
            managedFilesRoot: () => otherFiles.path,
            authorityRevision: () {
              if (changeFirst) {
                changeFirst = false;
                source.raw.execute(
                  "UPDATE records SET value='changed-during-other-proof' WHERE id='n'",
                );
              }
              return 'other-authority';
            },
          ),
        ],
      );
      try {
        expect(
          mixed.stamp(AssistantScope.workspace(workspace), {'notes'}),
          isNull,
        );
        expect(
          mixed.stamp(AssistantScope.workspace(workspace), {'notes'}),
          isNotNull,
        );
      } finally {
        await other.close();
      }
    },
  );

  test('queued source write denies before its callback starts and restores on failure', () async {
    final before = stamp();
    expect(before, isNotNull);
    final fail = source.write<void>((db) => throw StateError('injected'));
    final failure = expectLater(fail, throwsStateError);
    expect(stamp(), isNull);
    await failure;
    expect(stamp(), before);
  });
  test('queued workspace binding denies before commit without treating grant writes as scope writes', () async {
    final second = await workspaces.create('second');
    final before = stamp();
    expect(before, isNotNull);
    final entered = Completer<void>(), release = Completer<void>();
    final host = workspaces.database as ManagedConnection;
    final hold = host.exclusiveAsync((_) async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    final binding = workspaces.bind(
      WorkspaceBinding(
        workspaceId: second.id,
        moduleId: 'notes',
        nativeProjectId: 'p2',
      ),
    );
    final pending = stamp();
    release.complete();
    await hold;
    await binding;
    expect(pending, isNull);
    expect(stamp(), isNot(before));
  });
  test('ancestor namespace swap with identical bytes cannot become managed authority', () {
    final namespace = Directory('${root.path}/namespace')..createSync();
    final managed = Directory('${namespace.path}/files')..createSync();
    File('${managed.path}/data.txt').writeAsStringSync('same');
    final isolated = HostScopeAuthority(
      workspaces: workspaces,
      sources: {
        'notes': HostScopeSource(
          database: source,
          authorityRevision: () => 'source',
          managedFilesRoot: () => managed.path,
        ),
      },
    );
    String? proof() =>
        isolated.stamp(AssistantScope.workspace(workspace), {'notes'});
    expect(proof(), isNotNull);
    namespace.renameSync('${root.path}/original-namespace');
    final replacement = Directory('${root.path}/outside/files')
      ..createSync(recursive: true);
    File('${replacement.path}/data.txt').writeAsStringSync('same');
    Link('${root.path}/namespace').createSync('${root.path}/outside');
    expect(proof(), isNull);
  });

  test('files exceeding synchronous proof budget stay unknown', () {
    File('${files.path}/large.bin')
        .writeAsBytesSync(Uint8List(8 * 1024 * 1024 + 1));
    expect(stamp(), isNull);
  });
  test(
    'real ModuleHost pending and failed revocation deny source authority',
    () async {
      final module = FakeV2Module(
        'scopefixture',
        capabilities: {const CapabilityRequest(id: 'ocr', reason: 'fixture')},
      );
      final host = await MuyonHost.open(
        '${root.path}/permission-host',
        modules: [module],
      );
      try {
        await host.modules.activate('scopefixture');
        final actual = HostScopeAuthority(
          workspaces: host.workspaces,
          sources: {
            'scopefixture': HostScopeSource.deferred(
              connection: () => host.storage.connectionIfOpen('scopefixture'),
              authorityRevision: () =>
                  host.modules.scopeAuthorityRevision('scopefixture'),
              managedFilesRoot: () => module.lastResources!.files.rootPath,
            ),
          },
        );
        String? proof() =>
            actual.stamp(const AssistantScope.global(), {'scopefixture'});
        final before = proof();
        expect(before, isNotNull);
        final owner = host.workspaces.database as ManagedConnection;
        owner.raw.execute(
          "CREATE TEMP TRIGGER deny_capability BEFORE UPDATE ON module_grants BEGIN SELECT RAISE(ABORT,'injected revocation'); END",
        );
        final entered = Completer<void>(), release = Completer<void>();
        final hold = owner.exclusiveAsync((_) async {
          entered.complete();
          await release.future;
        });
        await entered.future;
        final revoke = host.modules.revokeCapability('scopefixture', 'ocr');
        final failure = expectLater(revoke, throwsA(isA<SqliteException>()));
        final pending = proof();
        release.complete();
        await hold;
        await failure;
        expect(pending, isNull);
        expect(proof(), isNull);
        await host.modules.activate('scopefixture');
        expect(
          proof(),
          isNull,
          reason: 'failed revoke cannot be undone by activation',
        );
        owner.raw.execute('DROP TRIGGER deny_capability');
        await host.modules.revokeCapability('scopefixture', 'ocr');
        await host.modules.activate('scopefixture');
        expect(proof(), isNotNull);
        expect(proof(), isNot(before));
      } finally {
        await host.close();
      }
    },
  );
}
