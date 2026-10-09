import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' hide ZLibDecoder;
import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:uuid/uuid.dart';

import '../cards/card_store.dart';
import '../cards/canonical_json.dart';
import '../source_ref.dart';

class PreparedResearchPackage extends PreparedImport {
  PreparedResearchPackage._(
    this._checkBeforeCommit, {
    required super.target,
    required super.inputDigest,
    required super.stagingToken,
    required this.originProjectKey,
    required Map<String, CardRevision> revisions,
    required Map<String, String> heads,
    required List<RevisionRef> forks,
    required Map<String, _Document> documents,
  }) : revisions = Map.unmodifiable(revisions),
       heads = Map.unmodifiable(heads),
       forks = List.unmodifiable(forks),
       _documents = Map.unmodifiable(documents);
  final String originProjectKey;
  final void Function()? _checkBeforeCommit;
  final Map<String, CardRevision> revisions;
  final Map<String, String> heads;
  final List<RevisionRef> forks;
  final Map<String, _Document> _documents;
}

class _Document {
  _Document(this.key, this.digest, this.name, List<int> bytes, this.current)
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final ObjectKey key;
  final String digest;
  final String name;
  final Uint8List bytes;
  final bool current;
}

/// Independent readable research package. All validation happens before the
/// short database transaction; the commit rechecks local identity and heads.
class ResearchPackageExchange {
  ResearchPackageExchange(this.store, {this.files});
  final CardStore store;
  final ModuleFiles? files;
  static const maxArchiveBytes = 64 * 1024 * 1024;
  static const maxExpandedBytes = 128 * 1024 * 1024;
  static const maxEntries = 4096;
  static const maxJsonEntryBytes = 8 * 1024 * 1024;
  static const maxRevisionAncestryDepth = 512;

  Future<Uint8List> exportBytes(String projectId, List<String> cardIds) async {
    // Snapshot SQL reads on the same queue as writes. ZIP encoding follows it.
    final entries = await store.database.write((_) {
      store.requireProject(projectId);
      final revisions = <String, CardRevision>{};
      final heads = <String, String>{};
      final forks = <RevisionRef>[];
      final pending = <String>[];
      final documents = <String, _Document>{};
      void visitCard(ObjectKey key) {
        store.requireObject(projectId, key);
        if (heads.containsKey(key.token)) return;
        final rows = store.db.select(
          'SELECT head_revision_id FROM rk_cards WHERE object_key=?',
          [key.token],
        );
        if (rows.isEmpty) throw StateError('Missing related card');
        final head = rows.single['head_revision_id'] as String;
        heads[key.token] = head;
        pending.add(head);
        for (final row in store.db.select(
          'SELECT revision_id FROM rk_conflicts WHERE object_key=? AND revision_id<>? ORDER BY revision_id',
          [key.token, head],
        )) {
          final id = row['revision_id'] as String;
          forks.add(RevisionRef(objectKey: key, revisionId: id));
          pending.add(id);
        }
      }

      for (final id in cardIds) {
        final card = store.get(projectId, id);
        if (card == null) throw StateError('Selected card not found');
        visitCard(card.revision.objectKey);
      }
      if (heads.isEmpty) throw StateError('Select at least one card');
      for (var index = 0; index < pending.length; index++) {
        final id = pending[index];
        if (revisions.containsKey(id)) continue;
        final revision = store.revision(id);
        if (revision == null) throw StateError('Missing revision ancestor');
        store.requireObject(projectId, revision.objectKey);
        revisions[id] = revision;
        pending.addAll(revision.parents.map((p) => p.revisionId));
        void document(ObjectKey key, String? digest) {
          store.requireObject(projectId, key);
          final rows = digest == null
              ? store.db.select(
                  'SELECT * FROM rk_documents WHERE object_key=? AND deleted=0',
                  [key.token],
                )
              : store.db.select(
                  'SELECT * FROM rk_documents WHERE object_key=? AND digest=? AND deleted<>1',
                  [key.token, digest],
                );
          if (rows.length != 1) throw StateError('Missing source bytes');
          final row = rows.single;
          final hash = row['digest'] as String;
          documents['${key.token}:$hash'] = _Document(
            key,
            hash,
            _safeName(row['file_name'] as String),
            row['bytes'] as List<int>,
            row['deleted'] == 0,
          );
        }

        for (final citation in revision.citations) {
          document(citation.source.documentRef, citation.source.contentDigest);
        }
        for (final relation in revision.relations) {
          if (relation.target.objectType == 'card') {
            visitCard(relation.target);
          } else if (relation.target.objectType == 'document') {
            document(relation.target, null);
          } else {
            throw StateError('Unsupported related object type');
          }
        }
        if (pending.length > 20000) {
          throw StateError('Package dependency closure is too large');
        }
      }
      // A package we produce must fit the receiver's unchanged ancestry bound.
      final visited = <String>{};
      final visiting = <String>{};
      void checkAncestry(String id, [int depth = 0]) {
        if (depth > maxRevisionAncestryDepth) {
          throw StateError('Revision ancestry exceeds limit');
        }
        if (visiting.contains(id)) throw StateError('Cyclic revision ancestry');
        if (visited.contains(id)) return;
        final revision = revisions[id];
        if (revision == null) throw StateError('Missing revision ancestor');
        visiting.add(id);
        for (final parent in revision.parents) {
          checkAncestry(parent.revisionId, depth + 1);
        }
        visiting.remove(id);
        visited.add(id);
      }

      for (final head in heads.values) {
        checkAncestry(head);
      }
      for (final fork in forks) {
        checkAncestry(fork.revisionId);
      }
      final output = <String, List<int>>{};
      final docManifest = <Map<String, Object?>>[];
      for (final document in documents.values) {
        final path = 'documents/${document.digest}/${document.name}';
        output[path] = document.bytes;
        docManifest.add({
          'ObjectKey': document.key.toJson(),
          'contentDigest': document.digest,
          'path': path,
          'byteLength': document.bytes.length,
          'sha256': document.digest,
          'current': document.current,
        });
      }
      for (final revision in revisions.values) {
        output['cards/${revision.objectKey.objectUuid}/${revision.revisionId}.md'] =
            utf8.encode(revision.bodyMarkdown);
      }
      void json(String path, Object? value) {
        final bytes = utf8.encode(canonicalJson(value));
        if (bytes.length > maxJsonEntryBytes) {
          throw StateError('Package JSON exceeds limit: $path');
        }
        output[path] = bytes;
      }

      final origin = store.origin(projectId);
      json('manifest.json', {
        'packageType': 'muyon-research',
        'schemaVersion': 1,
        'packageId': const Uuid().v4(),
        'sourceProjectId': projectId,
        'originProjectKey': origin,
        'objects': heads.entries
            .map(
              (e) => {
                'ObjectKey': jsonDecode(e.key),
                'headRevisionId': e.value,
              },
            )
            .toList(),
        // Absent in legacy schema-1 packages: no advertised forks.
        if (forks.isNotEmpty) 'forks': forks.map((f) => f.toJson()).toList(),
        'revisions': revisions.values
            .map((r) => {'envelope': r.toJson(), 'digest': r.contentDigest})
            .toList(),
        'documents': docManifest,
        'selectedCardIds': cardIds,
      });
      json('project.json', {
        'originProjectKey': origin,
        'sourceProjectId': projectId,
      });
      json('refs.json', {
        for (final r in revisions.values)
          r.revisionId: r.citations.map((c) => c.toJson()).toList(),
      });
      json('relations.json', {
        for (final r in revisions.values)
          r.revisionId: r.relations.map((r) => r.toJson()).toList(),
      });
      return output;
    });
    if (entries.length > maxEntries ||
        entries.values.fold<int>(0, (n, b) => n + b.length) >
            maxExpandedBytes) {
      throw StateError('Package exceeds limits');
    }
    final archive = Archive();
    entries.forEach(
      (name, bytes) => archive.addFile(ArchiveFile(name, bytes.length, bytes)),
    );
    final bytes = ZipEncoder().encode(archive);
    if (bytes.length > maxArchiveBytes) {
      throw StateError('Package exceeds limits');
    }
    return Uint8List.fromList(bytes);
  }

  Future<PreparedResearchPackage> prepareImport(
    SelectedInput input,
    ImportTarget target,
  ) async {
    if (files == null) throw StateError('Host file gateway is required');
    final frozen = await files!.freeze(input);
    final file = File(frozen.path);
    if (await file.length() > maxArchiveBytes) {
      throw const FormatException('Archive too large');
    }
    return prepareBytes(
      await file.readAsBytes(),
      target,
      stagingToken: frozen.path,
    );
  }

  PreparedResearchPackage prepareBytes(
    List<int> bytes,
    ImportTarget target, {
    String? stagingToken,
    void Function()? checkBeforeCommit,
  }) {
    if (target.binding.moduleId != 'research' ||
        bytes.length > maxArchiveBytes) {
      throw const FormatException('Invalid module or archive size');
    }
    final digest = sha256.convert(bytes).toString();
    final directory = ZipDirectory()..read(InputMemoryStream(bytes));
    if (directory.fileHeaders.length > maxEntries) {
      throw const FormatException('Too many entries');
    }
    final entries = <String, List<int>>{};
    var total = 0;
    for (final header in directory.fileHeaders) {
      final entry = header.file!;
      if ((header.externalFileAttributes >> 16 & 0xf000) == 0xa000 ||
          !_safePath(header.filename) ||
          entries.containsKey(header.filename) ||
          header.filename != entry.filename ||
          header.uncompressedSize != entry.uncompressedSize ||
          header.compressedSize != entry.compressedSize ||
          header.generalPurposeBitFlag & 1 != 0 ||
          ![0, 8].contains(header.compressionMethod) ||
          header.uncompressedSize < 0) {
        throw const FormatException('Unsafe archive entry');
      }
      total += header.uncompressedSize;
      if (total > maxExpandedBytes) {
        throw const FormatException('Expanded archive too large');
      }
      final compressed = entry.getRawContent();
      final output = _BoundedBytes(header.uncompressedSize);
      if (header.compressionMethod == 8) {
        final decoder = ZLibDecoder(raw: true).startChunkedConversion(output);
        for (var offset = 0; offset < compressed.length; offset += 8192) {
          decoder.add(
            compressed.sublist(
              offset,
              offset + 8192 < compressed.length
                  ? offset + 8192
                  : compressed.length,
            ),
          );
        }
        decoder.close();
      } else {
        output.add(compressed);
        output.close();
      }
      final data = output.bytes.takeBytes();
      if (data.length != header.uncompressedSize ||
          getCrc32(data) != header.crc32) {
        throw const FormatException('Entry length mismatch');
      }
      entries[header.filename] = data;
    }
    Object? readJson(String name) {
      final data = entries[name];
      if (data == null || data.length > maxJsonEntryBytes) {
        throw const FormatException('Missing or oversized JSON');
      }
      return strictJsonDecode(utf8.decode(data));
    }

    final manifest = Map<String, Object?>.from(
      readJson('manifest.json') as Map,
    );
    if (manifest['packageType'] != 'muyon-research' ||
        manifest['schemaVersion'] != 1) {
      throw const FormatException('Unsupported research package');
    }
    final origin = manifest['originProjectKey'] as String;
    final revisions = <String, CardRevision>{};
    final heads = <String, String>{};
    final documents = <String, _Document>{};
    final expectedPaths = {
      'manifest.json',
      'project.json',
      'refs.json',
      'relations.json',
    };
    for (final raw in manifest['revisions'] as List) {
      final row = Map<String, Object?>.from(raw as Map);
      final revision = CardRevision.fromJson(
        Map<String, Object?>.from(row['envelope'] as Map),
      );
      if (revision.objectKey.originProjectKey != origin ||
          revisions.containsKey(revision.revisionId) ||
          revision.contentDigest != row['digest']) {
        throw const FormatException('Invalid revision digest or identity');
      }
      // Reject noncanonical parent ordering or unrecognized nested fields.
      if (canonicalJson(row['envelope']) != revision.canonical) {
        throw const FormatException('Revision envelope changed on parse');
      }
      revisions[revision.revisionId] = revision;
      final path =
          'cards/${revision.objectKey.objectUuid}/${revision.revisionId}.md';
      expectedPaths.add(path);
      if (!entries.containsKey(path) ||
          utf8.decode(entries[path]!) != revision.bodyMarkdown) {
        throw const FormatException('Readable card snapshot mismatch');
      }
    }
    for (final raw in manifest['objects'] as List) {
      final row = Map<String, Object?>.from(raw as Map);
      final key = ObjectKey.fromJson(
        Map<String, Object?>.from(row['ObjectKey'] as Map),
      );
      final head = row['headRevisionId'] as String;
      if (heads.containsKey(key.token) || revisions[head]?.objectKey != key) {
        throw const FormatException('Invalid object head');
      }
      heads[key.token] = head;
    }
    final rawForks = manifest.containsKey('forks')
        ? manifest['forks']
        : const [];
    if (rawForks is! List) {
      throw const FormatException('Invalid fork list');
    }
    final forks = <RevisionRef>[];
    final forkIds = <String>{};
    for (final raw in rawForks) {
      if (raw is! Map ||
          raw.length != 2 ||
          raw['ObjectKey'] is! Map ||
          raw['revisionId'] is! String) {
        throw const FormatException('Invalid fork reference');
      }
      final rawKey = raw['ObjectKey'] as Map;
      if (rawKey.length != 3 ||
          [
            'originProjectKey',
            'objectType',
            'objectUuid',
          ].any((field) => rawKey[field] is! String)) {
        throw const FormatException('Invalid fork object key');
      }
      final fork = RevisionRef.fromJson(Map<String, Object?>.from(raw));
      if (!heads.containsKey(fork.objectKey.token) ||
          revisions[fork.revisionId]?.objectKey != fork.objectKey ||
          heads[fork.objectKey.token] == fork.revisionId ||
          !forkIds.add(fork.revisionId)) {
        throw const FormatException('Invalid fork identity');
      }
      forks.add(fork);
    }
    for (final raw in manifest['documents'] as List) {
      final row = Map<String, Object?>.from(raw as Map);
      final key = ObjectKey.fromJson(
        Map<String, Object?>.from(row['ObjectKey'] as Map),
      );
      final path = row['path'] as String;
      final hash = row['sha256'] as String;
      final data = entries[path];
      final identity = '${key.token}:$hash';
      if (key.originProjectKey != origin ||
          key.objectType != 'document' ||
          row['byteLength'] is! int ||
          row['byteLength'] != data?.length ||
          row['contentDigest'] != hash ||
          data == null ||
          sha256.convert(data).toString() != hash ||
          !path.startsWith('documents/$hash/') ||
          path.split('/').length != 3 ||
          documents.containsKey(identity)) {
        throw const FormatException('Invalid document bytes or identity');
      }
      expectedPaths.add(path);
      if (row['current'] is! bool) {
        throw const FormatException('Missing document status');
      }
      documents[identity] = _Document(
        key,
        hash,
        path.split('/').last,
        data,
        row['current'] as bool,
      );
    }
    if (heads.isEmpty ||
        entries.keys.toSet().difference(expectedPaths).isNotEmpty ||
        expectedPaths.difference(entries.keys.toSet()).isNotEmpty) {
      throw const FormatException('Unexpected or missing files');
    }
    final colors = <String, int>{};
    void visit(String id, [int depth = 0]) {
      if (depth > maxRevisionAncestryDepth) {
        throw const FormatException('Revision ancestry exceeds limit');
      }
      if (colors[id] == 1) {
        throw const FormatException('Cyclic revision ancestry');
      }
      if (colors[id] == 2) return;
      final revision = revisions[id];
      if (revision == null) throw const FormatException('Missing ancestor');
      colors[id] = 1;
      for (final parent in revision.parents) {
        if (revisions[parent.revisionId]?.objectKey != parent.objectKey) {
          throw const FormatException('Missing parent object');
        }
        visit(parent.revisionId, depth + 1);
      }
      for (final citation in revision.citations) {
        if (!documents.containsKey(
          '${citation.source.documentRef.token}:${citation.source.contentDigest}',
        )) {
          throw const FormatException('Missing citation source closure');
        }
      }
      for (final relation in revision.relations) {
        if (!heads.containsKey(relation.target.token) &&
            !documents.values.any(
              (d) => d.key == relation.target && d.current,
            )) {
          throw const FormatException('Dangling relation');
        }
      }
      colors[id] = 2;
    }

    for (final head in heads.values) {
      visit(head);
    }
    for (final fork in forks) {
      visit(fork.revisionId);
    }
    if (colors.length != revisions.length) {
      throw const FormatException('Unreachable revision');
    }
    if (canonicalJson(readJson('refs.json')) !=
            canonicalJson({
              for (final r in revisions.values)
                r.revisionId: r.citations.map((c) => c.toJson()).toList(),
            }) ||
        canonicalJson(readJson('relations.json')) !=
            canonicalJson({
              for (final r in revisions.values)
                r.revisionId: r.relations.map((r) => r.toJson()).toList(),
            })) {
      throw const FormatException('Readable references mismatch');
    }
    final project = readJson('project.json') as Map;
    if (project['originProjectKey'] != origin ||
        project['sourceProjectId'] != manifest['sourceProjectId']) {
      throw const FormatException('Project manifest mismatch');
    }
    return PreparedResearchPackage._(
      checkBeforeCommit,
      target: target,
      inputDigest: digest,
      stagingToken: stagingToken ?? digest,
      originProjectKey: origin,
      revisions: revisions,
      heads: heads,
      forks: forks,
      documents: documents,
    );
  }

  Future<ImportReceipt> commitImport(
    PreparedResearchPackage prepared,
    ImportIntent intent,
  ) => store.database.write((db) {
    // The host may revoke acceptance while this transaction is queued.
    prepared._checkBeforeCommit?.call();
    if (!prepared.matches(intent)) throw StateError('Import identity mismatch');
    final identity = canonicalJson({
      'operationId': intent.operationId,
      'workspaceId': intent.workspaceId,
      'moduleId': intent.moduleId,
      'targetProjectId': intent.targetProjectId,
      'kind': intent.kind.name,
      'inputDigest': intent.inputDigest,
      'stagingToken': intent.stagingToken,
    });
    final receipts = db.select(
      'SELECT * FROM rk_import_receipts WHERE operation_id=?',
      [intent.operationId],
    );
    if (receipts.isNotEmpty) {
      if (receipts.single['identity'] != identity) {
        throw StateError('Operation identity conflict');
      }
      return ImportReceipt(
        intent: intent,
        result: Map<String, Object?>.from(
          jsonDecode(receipts.single['result'] as String) as Map,
        ),
        committedAt: DateTime.parse(receipts.single['committed_at'] as String),
      );
    }
    final projectId = intent.targetProjectId;
    final existing = db.select('SELECT 1 FROM projects WHERE id=?', [
      projectId,
    ]);
    if (intent.kind == ImportKind.create) {
      if (existing.isNotEmpty) throw StateError('Create target already exists');
      db.execute(
        'INSERT INTO projects(id,title,question,next_step) VALUES(?,?,?,?)',
        [projectId, 'Imported research', '', ''],
      );
    } else {
      store.requireProject(projectId);
    }
    final origins = db.select(
      'SELECT * FROM rk_projects WHERE origin_key=? OR local_project_id=?',
      [prepared.originProjectKey, projectId],
    );
    if (origins.any(
      (r) =>
          r['origin_key'] != prepared.originProjectKey ||
          r['local_project_id'] != projectId,
    )) {
      throw StateError('Canonical project belongs to another local project');
    }
    db.execute('INSERT OR IGNORE INTO rk_projects VALUES(?,?)', [
      projectId,
      prepared.originProjectKey,
    ]);
    void map(ObjectKey key) {
      final rows = db.select(
        'SELECT local_project_id FROM canonical_object_map WHERE object_key=?',
        [key.token],
      );
      if (rows.isNotEmpty && rows.single['local_project_id'] != projectId) {
        throw StateError('Canonical object scope mismatch');
      }
      db.execute('INSERT OR IGNORE INTO canonical_object_map VALUES(?,?,?,?)', [
        key.token,
        const Uuid().v4(),
        projectId,
        key.objectType,
      ]);
    }

    for (final revision in prepared.revisions.values) {
      map(revision.objectKey);
    }
    for (final document in prepared._documents.values) {
      map(document.key);
      final hasCurrent = db.select(
        'SELECT 1 FROM rk_documents WHERE object_key=? AND deleted=0',
        [document.key.token],
      ).isNotEmpty;
      db.execute('INSERT OR IGNORE INTO rk_documents VALUES(?,?,?,?,?)', [
        document.key.token,
        document.digest,
        document.name,
        document.bytes,
        document.current && !hasCurrent ? 0 : 2,
      ]);
      // A citation-only import may already have this digest as historical.
      // Restore it only when no local current version wins; explicit deletion
      // remains unavailable and must fail required closure below.
      if (document.current && !hasCurrent) {
        db.execute(
          'UPDATE rk_documents SET deleted=0 WHERE object_key=? AND digest=? AND deleted=2',
          [document.key.token, document.digest],
        );
      }
    }
    for (final revision in prepared.revisions.values) {
      store.insertRevision(revision);
    }
    bool ancestor(String ancestor, String descendant) {
      final seen = <String>{};
      final queue = [descendant];
      while (queue.isNotEmpty) {
        final id = queue.removeLast();
        if (id == ancestor) return true;
        if (!seen.add(id)) continue;
        queue.addAll(store.revision(id)!.parents.map((p) => p.revisionId));
      }
      return false;
    }

    // Count newly retained forks for this operation; receipt replay returns the
    // original count, while a fresh duplicate operation contributes zero.
    var conflicts = 0;
    void retainFork(String key, String revisionId) {
      if (db.select(
        'SELECT 1 FROM rk_conflicts WHERE object_key=? AND revision_id=?',
        [key, revisionId],
      ).isEmpty) {
        db.execute('INSERT INTO rk_conflicts VALUES(?,?)', [key, revisionId]);
        conflicts++;
      }
    }

    for (final head in prepared.heads.entries) {
      final rows = db.select(
        'SELECT head_revision_id FROM rk_cards WHERE object_key=?',
        [head.key],
      );
      if (rows.isEmpty) {
        db.execute('INSERT INTO rk_cards VALUES(?,?)', [head.key, head.value]);
      } else {
        final current = rows.single['head_revision_id'] as String;
        if (ancestor(current, head.value)) {
          db.execute(
            'UPDATE rk_cards SET head_revision_id=? WHERE object_key=?',
            [head.value, head.key],
          );
        } else if (!ancestor(head.value, current)) {
          retainFork(head.key, head.value);
        }
      }
    }
    // An advertised fork is retained, even if it descends from our active head.
    // It never participates in choosing that head. A returned fork may already
    // be our active branch, in which case no self-conflict is created.
    for (final fork in prepared.forks) {
      final current = db.select(
        'SELECT head_revision_id FROM rk_cards WHERE object_key=?',
        [fork.objectKey.token],
      ).single['head_revision_id'];
      if (current != fork.revisionId) {
        retainFork(fork.objectKey.token, fork.revisionId);
      }
    }
    for (final key in prepared.heads.keys) {
      db.execute(
        'DELETE FROM rk_conflicts WHERE object_key=? AND revision_id=(SELECT head_revision_id FROM rk_cards WHERE object_key=?)',
        [key, key],
      );
    }
    // Preparation validates package closure; local current/deletion policy may
    // still prevent a referenced version from being usable after reconciliation.
    // Check heads, forks and ancestors before the receipt makes this durable.
    for (final revision in prepared.revisions.values) {
      for (final citation in revision.citations) {
        if (store.citationDocument(projectId, citation.source) == null) {
          throw StateError('Citation source closure unavailable after import');
        }
      }
      for (final relation in revision.relations) {
        if (relation.target.objectType == 'document' &&
            db.select(
                  'SELECT 1 FROM rk_documents WHERE object_key=? AND deleted=0',
                  [relation.target.token],
                ).length !=
                1) {
          throw StateError(
            'Document relation closure unavailable after import',
          );
        }
      }
    }
    final result = {
      'cards': prepared.heads.length,
      'conflicts': conflicts,
      'originProjectKey': prepared.originProjectKey,
    };
    final now = DateTime.now().toUtc();
    db.execute('INSERT INTO rk_import_receipts VALUES(?,?,?,?)', [
      intent.operationId,
      identity,
      jsonEncode(result),
      now.toIso8601String(),
    ]);
    return ImportReceipt(intent: intent, result: result, committedAt: now);
  });

  static bool _safePath(String name) =>
      name.isNotEmpty &&
      !name.contains('\\') &&
      !name.contains(':') &&
      !name.contains('\u0000') &&
      name
          .split('/')
          .every((part) => part.isNotEmpty && part != '.' && part != '..');
  static String _safeName(String name) {
    final clean = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return clean.isEmpty || clean == '.' || clean == '..'
        ? 'source.bin'
        : clean;
  }
}

class _BoundedBytes extends ByteConversionSinkBase {
  _BoundedBytes(this.limit);
  final int limit;
  final BytesBuilder bytes = BytesBuilder(copy: false);
  int length = 0;
  @override
  void add(List<int> chunk) {
    length += chunk.length;
    if (length > limit) {
      throw const FormatException('Expanded bytes exceed declared bound');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}
