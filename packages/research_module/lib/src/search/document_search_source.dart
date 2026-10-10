import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../research_module.dart';

/// Module-owned read source. The host supplies its CURRENT runtime getter;
/// no resources are cached across revocation, replacement or host shutdown.
class ResearchDocumentSearchSource implements SearchSource {
  ResearchDocumentSearchSource({
    required this.currentRuntime,
    Future<List<int>> Function(String path)? readBytes,
  }) : readBytes = readBytes ?? _readBounded;

  final ResearchRuntime? Function() currentRuntime;
  final Future<List<int>> Function(String path) readBytes;
  static const maxFileBytes = 128 * 1024 * 1024;
  static const maxDocuments = 1000;
  @override
  String get id => 'research.documents';
  @override
  Set<String> get objectTypes => const {'document'};

  ResearchRuntime _runtime() => currentRuntime() ??
      (throw StateError('Research search source is not active'));
  void _current(ResearchRuntime runtime) {
    if (!identical(currentRuntime(), runtime)) {
      throw StateError('Research search source authority ended');
    }
  }

  ResearchDocument? _document(ResearchRuntime runtime, String project, String id) {
    if (!runtime.store.projects().any((value) => value.id == project)) return null;
    return currentVersions(runtime.store.documents(project))
        .where((value) => value.id == id).firstOrNull;
  }

  String _path(ResearchRuntime runtime, ResearchDocument document) {
    final root = Directory(runtime.resources.files.rootPath).resolveSymbolicLinksSync();
    final path = File(document.absolutePath).resolveSymbolicLinksSync();
    if (!p.isWithin(root, path) || File(path).lengthSync() > maxFileBytes) {
      throw StateError('Research source outside managed files or over budget');
    }
    return path;
  }

  static Future<List<int>> _readBounded(String path) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in File(path).openRead()) {
      if (bytes.length + chunk.length > maxFileBytes) {
        throw StateError('Research source file budget exceeded');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  Future<(IndexableItem, int)?> _item(ResearchRuntime runtime, ResearchDocument document) async {
    try {
      final path = _path(runtime, document);
      final bytes = await readBytes(path);
      _current(runtime);
      final current = _document(runtime, document.projectId, document.id);
      if (bytes.length > maxFileBytes || current == null ||
          current.absolutePath != document.absolutePath ||
          _path(runtime, current) != path) return null;
      final digest = sha256.convert(bytes).toString();
      // Recheck bytes and ownership after the asynchronous read; a changed
      // source never publishes a digest from an earlier row/file snapshot.
      final verified = await _readBounded(path);
      _current(runtime);
      final latest = _document(runtime, document.projectId, document.id);
      if (latest == null || _path(runtime, latest) != path ||
          sha256.convert(verified).toString() != digest) return null;
      return (IndexableItem(
        ref: ObjectRef(moduleId: 'research', objectType: 'document',
          objectId: document.id, nativeProjectId: document.projectId,
          contentDigest: digest),
        contentDigest: digest, filePath: path,
      ), bytes.length);
    } on FileSystemException {
      _current(runtime);
      return null;
    }
  }

  @override
  Future<List<IndexableItem>> list(IndexScope scope) async {
    final runtime = _runtime();
    final project = scope.nativeProjectId;
    if (project == null || !runtime.store.projects().any((value) => value.id == project)) {
      throw StateError('Research search requires an explicit current project');
    }
    final documents = currentVersions(runtime.store.documents(project));
    if (documents.length > maxDocuments) throw StateError('Research document budget exceeded');
    final items = <IndexableItem>[];
    var totalBytes = 0;
    for (final document in documents) {
      _current(runtime);
      try {
        if (totalBytes + File(_path(runtime, document)).lengthSync() > maxFileBytes) {
          throw StateError('Research project source byte budget exceeded');
        }
      } on FileSystemException {
        continue;
      }
      final item = await _item(runtime, document);
      if (item != null) {
        totalBytes += item.$2;
        if (totalBytes > maxFileBytes) {
          throw StateError('Research project source byte budget exceeded');
        }
        items.add(item.$1);
      }
    }
    _current(runtime);
    return List.unmodifiable(items);
  }

  @override
  Future<ObjectView?> confirm(ObjectRef ref) async {
    final runtime = _runtime();
    final project = ref.nativeProjectId;
    if (ref.moduleId != 'research' || ref.objectType != 'document' ||
        project == null || ref.revisionRef != null ||
        ref.contentDigest == null) return null;
    final document = _document(runtime, project, ref.objectId);
    if (document == null) return null;
    final item = await _item(runtime, document);
    if (item == null || item.$1.ref != ref) return null;
    return ObjectView(ref: item.$1.ref, title: document.relativePath);
  }
}
