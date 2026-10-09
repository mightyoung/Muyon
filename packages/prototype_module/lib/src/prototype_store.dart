import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

const prototypeModuleId = 'prototype';

/// Table definitions for migration 1, change log included.
void createPrototypeTables(Database db) {
  db.execute('''
CREATE TABLE prototype_pages(
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE TABLE prototype_versions(
  id TEXT PRIMARY KEY,
  page_id TEXT NOT NULL REFERENCES prototype_pages(id),
  label TEXT NOT NULL,
  digest TEXT NOT NULL,
  rel_dir TEXT NOT NULL,
  file_count INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE(page_id,label)
);
CREATE TABLE prototype_feedback(
  id TEXT PRIMARY KEY,
  page_id TEXT NOT NULL REFERENCES prototype_pages(id),
  version_id TEXT NOT NULL REFERENCES prototype_versions(id),
  body TEXT NOT NULL,
  created_at TEXT NOT NULL
);
''');
  ModuleChangeLog.createTable(db);
}

class PrototypeImportException implements Exception {
  const PrototypeImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Pages, versions and feedback. Builds are copied under [filesRoot] so a
/// version never depends on the original folder.
class PrototypeStore {
  PrototypeStore({
    required this.database,
    required this.filesRoot,
    DateTime Function()? clock,
    String Function()? newId,
  }) : _clock = clock ?? DateTime.now,
       _newId = newId ?? (() => const Uuid().v4());

  final ManagedDatabase database;
  final String filesRoot;
  final DateTime Function() _clock;
  final String Function() _newId;

  static const maxFiles = 5000;
  static const maxBytes = 200 * 1024 * 1024;

  ObjectRef _ref(String type, String id, String pageId) => ObjectRef(
    moduleId: prototypeModuleId,
    objectType: type,
    objectId: id,
    nativeProjectId: pageId,
  );

  List<PrototypePage> pages() => [
    for (final row in database.raw.select(
      'SELECT p.id,p.title,p.created_at,'
      '(SELECT v.id FROM prototype_versions v WHERE v.page_id=p.id '
      'ORDER BY v.created_at DESC, v.rowid DESC LIMIT 1) AS latest '
      'FROM prototype_pages p ORDER BY p.created_at DESC, p.rowid DESC',
    ))
      PrototypePage(
        id: row['id'] as String,
        title: row['title'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
        latestVersionId: row['latest'] as String?,
      ),
  ];

  List<PrototypeVersion> versions(String pageId) => [
    for (final row in database.raw.select(
      'SELECT * FROM prototype_versions WHERE page_id=? '
      'ORDER BY created_at DESC, rowid DESC',
      [pageId],
    ))
      _version(row),
  ];

  PrototypeVersion? version(String versionId) {
    final rows = database.raw.select(
      'SELECT * FROM prototype_versions WHERE id=?',
      [versionId],
    );
    return rows.isEmpty ? null : _version(rows.first);
  }

  PrototypeVersion _version(Row row) => PrototypeVersion(
    id: row['id'] as String,
    pageId: row['page_id'] as String,
    label: row['label'] as String,
    digest: row['digest'] as String,
    directory: p.join(filesRoot, row['rel_dir'] as String),
    fileCount: row['file_count'] as int,
    createdAt: DateTime.parse(row['created_at'] as String),
  );

  List<PrototypeFeedback> feedback(String pageId) => [
    for (final row in database.raw.select(
      'SELECT * FROM prototype_feedback WHERE page_id=? '
      'ORDER BY created_at DESC, rowid DESC',
      [pageId],
    ))
      PrototypeFeedback(
        id: row['id'] as String,
        pageId: row['page_id'] as String,
        versionId: row['version_id'] as String,
        text: row['body'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
      ),
  ];

  PrototypeFeedback? feedbackById(String id) {
    final rows = database.raw.select(
      'SELECT * FROM prototype_feedback WHERE id=?',
      [id],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return PrototypeFeedback(
      id: row['id'] as String,
      pageId: row['page_id'] as String,
      versionId: row['version_id'] as String,
      text: row['body'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  /// Copies a built single-page prototype into the module and records it as a
  /// new page, or as a new version of [pageId]. The folder must contain
  /// `index.html`; symbolic links are refused so a build cannot point outside
  /// itself. Nothing is recorded if the copy fails.
  Future<PrototypeVersion> importBuild({
    required String sourceDir,
    String? title,
    String? pageId,
  }) async {
    final source = Directory(sourceDir);
    if (!source.existsSync()) {
      throw PrototypeImportException('目录不存在：$sourceDir');
    }
    if (!File(p.join(sourceDir, 'index.html')).existsSync()) {
      throw const PrototypeImportException('构建目录缺少 index.html');
    }
    final name = (title ?? p.basename(p.normalize(sourceDir))).trim();
    if (pageId == null && name.isEmpty) {
      throw const PrototypeImportException('请填写页面标题');
    }
    if (pageId != null &&
        database.raw.select('SELECT 1 FROM prototype_pages WHERE id=?', [
          pageId,
        ]).isEmpty) {
      throw PrototypeImportException('页面不存在：$pageId');
    }

    final page = pageId ?? _newId();
    final versionId = _newId();
    final relDir = p.join('prototypes', page, versionId);
    final target = Directory(p.join(filesRoot, relDir));
    final partial = Directory('${target.path}.partial');
    if (partial.existsSync()) partial.deleteSync(recursive: true);
    try {
      final copied = await _copyTree(source, partial);
      partial.renameSync(target.path);
      final now = _clock().toUtc().toIso8601String();
      return await database.write((db) {
        if (pageId == null) {
          db.execute(
            'INSERT INTO prototype_pages(id,title,created_at) VALUES(?,?,?)',
            [page, name, now],
          );
          ModuleChangeLog.record(
            db,
            _ref('page', page, page),
            ChangeOp.upsert,
            summary: name,
          );
        }
        final count =
            db.select(
                  'SELECT COUNT(*) c FROM prototype_versions WHERE page_id=?',
                  [page],
                ).first['c']
                as int;
        final label = 'v${count + 1}';
        db.execute(
          'INSERT INTO prototype_versions(id,page_id,label,digest,rel_dir,'
          'file_count,created_at) VALUES(?,?,?,?,?,?,?)',
          [versionId, page, label, copied.digest, relDir, copied.files, now],
        );
        final pageTitle =
            db.select('SELECT title FROM prototype_pages WHERE id=?', [
                  page,
                ]).first['title']
                as String;
        ModuleChangeLog.record(
          db,
          ObjectRef(
            moduleId: prototypeModuleId,
            objectType: 'version',
            objectId: versionId,
            nativeProjectId: page,
            contentDigest: copied.digest,
          ),
          ChangeOp.upsert,
          summary: '$pageTitle $label',
        );
        return PrototypeVersion(
          id: versionId,
          pageId: page,
          label: label,
          digest: copied.digest,
          directory: target.path,
          fileCount: copied.files,
          createdAt: DateTime.parse(now),
        );
      });
    } catch (_) {
      for (final dir in [partial, target]) {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
      rethrow;
    }
  }

  Future<PrototypeFeedback> addFeedback({
    required String versionId,
    required String text,
    void Function()? beforeWrite,
  }) async {
    final body = text.trim();
    if (body.isEmpty) throw const FormatException('反馈内容不能为空');
    if (body.length > 4000) throw const FormatException('反馈内容过长');
    final id = _newId();
    final now = _clock().toUtc().toIso8601String();
    return database.write((db) {
      beforeWrite?.call();
      final rows = db.select(
        'SELECT v.page_id,v.label,p.title FROM prototype_versions v '
        'JOIN prototype_pages p ON p.id=v.page_id WHERE v.id=?',
        [versionId],
      );
      if (rows.isEmpty) throw StateError('版本不存在：$versionId');
      final pageId = rows.first['page_id'] as String;
      db.execute(
        'INSERT INTO prototype_feedback(id,page_id,version_id,body,created_at) '
        'VALUES(?,?,?,?,?)',
        [id, pageId, versionId, body, now],
      );
      ModuleChangeLog.record(
        db,
        _ref('feedback', id, pageId),
        ChangeOp.upsert,
        summary: '${rows.first['title']} ${rows.first['label']} 反馈',
      );
      return PrototypeFeedback(
        id: id,
        pageId: pageId,
        versionId: versionId,
        text: body,
        createdAt: DateTime.parse(now),
      );
    });
  }

  Future<({String digest, int files})> _copyTree(
    Directory source,
    Directory target,
  ) async {
    target.createSync(recursive: true);
    final entries = <File>[];
    final root = p.normalize(source.absolute.path);
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is Link) {
        throw PrototypeImportException(
          '构建目录含符号链接：${p.relative(entity.path, from: root)}',
        );
      }
      if (entity is File) entries.add(entity);
    }
    if (entries.length > maxFiles) {
      throw const PrototypeImportException('构建目录文件过多');
    }
    entries.sort((a, b) => a.path.compareTo(b.path));
    final lines = StringBuffer();
    var total = 0;
    for (final file in entries) {
      final rel = p.relative(file.path, from: root);
      final bytes = await file.readAsBytes();
      total += bytes.length;
      if (total > maxBytes) {
        throw const PrototypeImportException('构建目录过大');
      }
      final dest = File(p.join(target.path, rel));
      dest.parent.createSync(recursive: true);
      await dest.writeAsBytes(bytes, flush: true);
      lines.writeln(
        '${p.posix.joinAll(p.split(rel))}\u0000${sha256.convert(bytes)}',
      );
    }
    return (
      digest: sha256.convert(utf8.encode(lines.toString())).toString(),
      files: entries.length,
    );
  }

  /// Navigation and bridge boundary for one imported version.
  RestrictedWebViewSpec specFor(
    PrototypeVersion version, {
    Set<String> bridgeChannels = const {},
  }) {
    final root = Uri.directory(version.directory);
    return RestrictedWebViewSpec(
      entry: root.resolve('index.html'),
      allowedRoots: {root},
      bridgeChannels: bridgeChannels,
    );
  }
}
