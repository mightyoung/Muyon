import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:prototype_module/src/prototype_store.dart';
import 'package:sqlite3/sqlite3.dart';

class _Db implements ManagedDatabase {
  _Db() : raw = sqlite3.openInMemory() {
    createPrototypeTables(raw);
  }
  @override
  final Database raw;
  @override
  Future<T> write<T>(T Function(Database database) body) async {
    raw.execute('BEGIN');
    try {
      final result = body(raw);
      raw.execute('COMMIT');
      return result;
    } catch (_) {
      raw.execute('ROLLBACK');
      rethrow;
    }
  }
}

void main() {
  late Directory tmp;
  late _Db db;
  late PrototypeStore store;
  late Directory build;
  var n = 0;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('proto-store');
    db = _Db();
    n = 0;
    store = PrototypeStore(
      database: db,
      filesRoot: p.join(tmp.path, 'files'),
      newId: () => 'id${++n}',
      clock: () => DateTime.utc(2026, 10, 4, 12, 0, n),
    );
    build = Directory(p.join(tmp.path, 'dist'))..createSync();
    File(p.join(build.path, 'index.html')).writeAsStringSync('<h1>hi</h1>');
    Directory(p.join(build.path, 'assets')).createSync();
    File(p.join(build.path, 'assets', 'app.js')).writeAsStringSync('1');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  int changes() => ModuleChangeLog.since(db.raw, prototypeModuleId, 0).length;

  test('import copies the build and records page, version and log', () async {
    final version = await store.importBuild(
      sourceDir: build.path,
      title: 'MES 原型',
    );
    expect(version.label, 'v1');
    expect(version.fileCount, 2);
    expect(
      File(p.join(version.directory, 'assets/app.js')).existsSync(),
      isTrue,
    );
    expect(store.pages().single.title, 'MES 原型');
    expect(store.pages().single.latestVersionId, version.id);
    final log = ModuleChangeLog.since(db.raw, prototypeModuleId, 0);
    expect(log.map((c) => c.ref.objectType), ['page', 'version']);
    expect(log.first.summary, 'MES 原型');
    expect(log.last.summary, 'MES 原型 v1');
  });

  test(
    'importing again with the page id adds a version, same digest ok',
    () async {
      final first = await store.importBuild(sourceDir: build.path, title: 'A');
      final second = await store.importBuild(
        sourceDir: build.path,
        pageId: first.pageId,
      );
      expect(second.label, 'v2');
      expect(second.digest, first.digest);
      expect(store.versions(first.pageId).map((v) => v.label), ['v2', 'v1']);
      expect(store.pages(), hasLength(1));
      expect(store.pages().single.latestVersionId, second.id);
    },
  );

  test('digest changes when content changes', () async {
    final first = await store.importBuild(sourceDir: build.path, title: 'A');
    File(p.join(build.path, 'assets', 'app.js')).writeAsStringSync('2');
    final second = await store.importBuild(
      sourceDir: build.path,
      pageId: first.pageId,
    );
    expect(second.digest, isNot(first.digest));
  });

  test(
    'missing index, unknown page and symlinks are refused cleanly',
    () async {
      File(p.join(build.path, 'index.html')).deleteSync();
      await expectLater(
        store.importBuild(sourceDir: build.path, title: 'x'),
        throwsA(isA<PrototypeImportException>()),
      );
      File(p.join(build.path, 'index.html')).writeAsStringSync('x');
      await expectLater(
        store.importBuild(sourceDir: build.path, pageId: 'nope'),
        throwsA(isA<PrototypeImportException>()),
      );
      Link(p.join(build.path, 'link')).createSync('/etc');
      await expectLater(
        store.importBuild(sourceDir: build.path, title: 'x'),
        throwsA(isA<PrototypeImportException>()),
      );
      expect(store.pages(), isEmpty);
      expect(changes(), 0);
      final root = Directory(p.join(tmp.path, 'files', 'prototypes'));
      expect(
        !root.existsSync() ||
            root.listSync(recursive: true).whereType<File>().isEmpty,
        isTrue,
        reason: 'failed imports leave no copied files',
      );
    },
  );

  test('feedback is stored against a version and logged', () async {
    final version = await store.importBuild(sourceDir: build.path, title: 'A');
    final before = changes();
    final item = await store.addFeedback(
      versionId: version.id,
      text: '  按钮太小  ',
    );
    expect(item.text, '按钮太小');
    expect(store.feedback(version.pageId).single.versionId, version.id);
    expect(changes(), before + 1);
    await expectLater(
      store.addFeedback(versionId: version.id, text: '   '),
      throwsFormatException,
    );
    await expectLater(
      store.addFeedback(versionId: 'ghost', text: 'x'),
      throwsStateError,
    );
    expect(changes(), before + 1, reason: 'rejected feedback logs nothing');
  });

  test('spec confines navigation to one version directory', () async {
    final v1 = await store.importBuild(sourceDir: build.path, title: 'A');
    final v2 = await store.importBuild(
      sourceDir: build.path,
      pageId: v1.pageId,
    );
    final spec = store.specFor(v1, bridgeChannels: {'muyon.feedback'});
    expect(
      spec.allowsNavigation(Uri.file(p.join(v1.directory, 'index.html'))),
      isTrue,
    );
    expect(
      spec.allowsNavigation(Uri.file(p.join(v2.directory, 'index.html'))),
      isFalse,
    );
    expect(spec.allowsBridge('muyon.feedback'), isTrue);
    expect(spec.allowsBridge('other'), isFalse);
  });
}
