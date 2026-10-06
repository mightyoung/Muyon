import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/platform/backup_service.dart';
import 'package:muyon/platform/storage_manager.dart';
import 'package:muyon/workspace/workspace_repository.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

final _notes = ModuleSchema(
  version: 1,
  definitionDigest: 'notes-1',
  migrations: [
    ModuleMigration(
      version: 1,
      id: 'notes-1',
      definitionDigest: 'notes-1',
      migrate: (db) => db.execute('CREATE TABLE notes(n INTEGER)'),
    ),
  ],
);

void main() {
  late Directory tmp;
  late String root;
  late StorageManager storage;
  late ManagedConnection host;
  late ManagedConnection notes;

  void file(String rel, String text) => (File(
    p.join(root, rel),
  )..createSync(recursive: true)).writeAsStringSync(text);

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('muyon-backup-');
    root = p.join(tmp.path, 'data');
    storage = StorageManager(root);
    host = await storage.open('muyon', WorkspaceRepository.schema);
    await WorkspaceRepository(host).create('Project A');
    notes = await storage.open('notes', _notes);
    await notes.write((db) => db.execute('INSERT INTO notes VALUES(1)'));
    file('modules/notes/files/paper.pdf', 'pdf bytes');
    file('modules/notes/files/staging/half.tmp', 'partial');
    file('ocr_models/det.onnx', 'model');
    file('public_files/doc/a.txt', 'shared');
  });
  tearDown(() async {
    await storage.close();
    tmp.deleteSync(recursive: true);
  });

  test(
    'snapshot holds writes, includes data and files, excludes transient',
    () async {
      final target = p.join(tmp.path, 'backup');
      final writes = <Future<void>>[];
      final created = BackupService.create(storage, target);
      for (var i = 2; i <= 50; i++) {
        writes.add(
          notes.write((db) => db.execute('INSERT INTO notes VALUES(?)', [i])),
        );
      }
      final manifest = await created;
      await Future.wait(writes);

      final paths = {
        for (final e in manifest['entries'] as List)
          (e as Map)['path'] as String,
      };
      expect(
        paths,
        containsAll([
          'muyon.sqlite',
          'modules/notes/notes.sqlite',
          'modules/notes/files/paper.pdf',
          'public_files/doc/a.txt',
        ]),
      );
      expect(paths.where((x) => x.contains('staging')), isEmpty);
      expect(paths.where((x) => x.startsWith('ocr_models')), isEmpty);
      expect(paths.where((x) => x.endsWith('.lock')), isEmpty);
      expect(manifest['excluded'], contains('ocr_models/'));

      // The copy is a committed prefix: 1..k with no gaps, never torn.
      final copy = sqlite3.open(p.join(target, 'modules/notes/notes.sqlite'));
      final values = [
        for (final r in copy.select('SELECT n FROM notes ORDER BY n'))
          r['n'] as int,
      ];
      copy.close();
      expect(values, List.generate(values.length, (i) => i + 1));
      expect(await BackupService.verify(target), isEmpty);
      expect(Directory('$target.partial').existsSync(), isFalse);
    },
  );

  test('verify reports missing, altered and escaping entries', () async {
    final target = p.join(tmp.path, 'backup');
    await BackupService.create(storage, target);
    File(p.join(target, 'public_files/doc/a.txt'))
        .writeAsStringSync('tampered');
    File(p.join(target, 'modules/notes/files/paper.pdf')).deleteSync();
    final problems = await BackupService.verify(target);
    expect(problems.join('\n'), contains('public_files/doc/a.txt'));
    expect(problems.join('\n'), contains('paper.pdf'));

    final manifestFile = File(p.join(target, 'manifest.json'));
    final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map;
    (manifest['entries'] as List).add({
      'path': '../../etc/passwd',
      'kind': 'file',
      'size': 1,
      'sha256': 'x',
    });
    manifestFile.writeAsStringSync(jsonEncode(manifest));
    expect(
      (await BackupService.verify(target)).join(),
      contains('Unsafe path'),
    );
  });

  test(
    'restore refuses while open, then swaps in and keeps old data',
    () async {
      final target = p.join(tmp.path, 'backup');
      await BackupService.create(storage, target);
      await notes.write((db) => db.execute('INSERT INTO notes VALUES(999)'));
      await expectLater(BackupService.restore(target, root), throwsStateError);

      await storage.close();
      final previous = await BackupService.restore(target, root);
      expect(Directory(previous).existsSync(), isTrue);

      storage = StorageManager(root);
      host = await storage.open('muyon', WorkspaceRepository.schema);
      notes = await storage.open('notes', _notes);
      expect(WorkspaceRepository(host).all().single.title, 'Project A');
      expect(notes.raw.select('SELECT n FROM notes WHERE n=999'), isEmpty);
      expect(
        File(p.join(root, 'modules/notes/files/paper.pdf')).readAsStringSync(),
        'pdf bytes',
      );
      final old = sqlite3.open(p.join(previous, 'modules/notes/notes.sqlite'));
      expect(old.select('SELECT n FROM notes WHERE n=999'), isNotEmpty);
      old.close();
    },
  );

  test(
    'restore rejects an unverifiable backup and leaves data alone',
    () async {
      final target = p.join(tmp.path, 'backup');
      await BackupService.create(storage, target);
      await storage.close();
      File(p.join(target, 'muyon.sqlite')).writeAsStringSync('garbage');
      await expectLater(BackupService.restore(target, root), throwsStateError);
      storage = StorageManager(root);
      host = await storage.open('muyon', WorkspaceRepository.schema);
      expect(WorkspaceRepository(host).all().single.title, 'Project A');
    },
  );
}
