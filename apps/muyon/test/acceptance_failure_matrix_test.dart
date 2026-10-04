import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon/app/bootstrap.dart';
import 'package:muyon/platform/backup_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Host-level failure cases from requirement §12 that unit tests cannot show
/// on their own: they start the real host. See
/// docs/implementation/failure-matrix.md for the full mapping.
void main() {
  late Directory tmp;
  late String root;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('muyon-matrix-');
    root = p.join(tmp.path, 'data');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<String> note(String name, String text) async {
    final file = File(p.join(tmp.path, name))..writeAsStringSync(text);
    return file.path;
  }

  test(
    'offline: local import and search work and nothing leaves the device',
    () async {
      final host = await MuyonHost.open(root);
      try {
        final doc = await host.services.knowledge.importFile(
          await note('offline.txt', '离线检索 供应商报价 offline quote'),
        );
        await host.services.knowledge.index(doc.id);
        final hits = await host.services.knowledge.search('报价');
        expect(hits, isNotEmpty);
        expect(host.outbound.recent(), isEmpty);
      } finally {
        await host.close();
      }
    },
  );

  test(
    'a drifted research database disables only research and is not repaired',
    () async {
      var host = await MuyonHost.open(root);
      await host.activateResearch();
      expect(host.research, isNotNull);
      await host.close();

      final path = p.join(root, 'modules', 'research', 'research.sqlite');
      final tamper = sqlite3.open(path);
      tamper.execute('CREATE TABLE intruder(x)');
      tamper.close();

      host = await MuyonHost.open(root);
      try {
        await host.activateResearch();
        expect(host.research, isNull);
        expect(host.researchError, contains('drift'));
        final registry = host.workspaces.database.raw.select(
          "SELECT status FROM module_registry WHERE module_id='research'",
        );
        expect(registry.single['status'], 'failed');
        final catalog = host.workspaces.database.raw.select(
          "SELECT migration_status FROM schema_catalog WHERE module_id='research'",
        );
        expect(catalog.single['migration_status'], 'blocked');

        // The rest of the platform keeps working.
        final doc = await host.services.knowledge.importFile(
          await note('still.txt', 'still usable'),
        );
        expect(host.services.knowledge.require(doc.id).title, isNotEmpty);
        await host.workspaces.create('Other project');
      } finally {
        await host.close();
      }
      final inspect = sqlite3.open(path, mode: OpenMode.readOnly);
      expect(
        inspect.select("SELECT name FROM sqlite_master WHERE name='intruder'"),
        isNotEmpty,
      );
      inspect.close();
    },
  );

  test(
    'backup, later changes, restore, reopen: state is the backup state',
    () async {
      var host = await MuyonHost.open(root);
      final backupDir = p.join(tmp.path, 'backup');
      try {
        await host.workspaces.create('Before backup');
        final doc = await host.services.knowledge.importFile(
          await note('kept.txt', '备份前的资料 kept before backup'),
        );
        await host.services.knowledge.index(doc.id);
        await BackupService.create(host.storage, backupDir);
        await host.workspaces.create('After backup');
      } finally {
        await host.close();
      }

      final previous = await BackupService.restore(backupDir, root);
      expect(Directory(previous).existsSync(), isTrue);

      host = await MuyonHost.open(root);
      try {
        expect(host.workspaces.all().map((w) => w.title), ['Before backup']);
        expect(await host.services.knowledge.search('备份'), isNotEmpty);
      } finally {
        await host.close();
      }
    },
  );
}
