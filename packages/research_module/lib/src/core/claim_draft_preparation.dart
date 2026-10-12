import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../cards/canonical_json.dart';
import 'models.dart';
import 'research_skill.dart';
import 'store.dart';

/// A trusted caller supplies document bytes for this pinned reference. This
/// callback is an integration seam, not filesystem authority by itself: the
/// caller must resolve identity/scope and perform controlled source reads.
/// No model-supplied paths or output destinations enter the preparer.
typedef ClaimDraftDocumentReader = Future<List<int>> Function(
  ObjectRef document,
);

class ClaimDraftPreparationFailure extends StateError {
  ClaimDraftPreparationFailure(
    this.code, {
    List<LocalExportExclusion> exclusions = const [],
  }) : exclusions = List.unmodifiable([
         for (final e in exclusions) LocalExportExclusion(e.id, e.reason),
       ]),
       super(code);
  final String code;
  final List<LocalExportExclusion> exclusions;
}

/// One frozen proposal. Partial proposals require a new confirmation of this
/// selected/included/excluded manifest; they are never silently expanded.
class ResearchClaimDraftPreparation extends LocalExportPreparation {
  ResearchClaimDraftPreparation._({
    required super.generatedAt,
    required super.bytes,
    required super.sources,
    required super.exclusions,
    required super.warnings,
    required super.manifestDigest,
    required List<String> selectedNoteIds,
    required List<String> includedNoteIds,
    required List<Map<String, Object?>> rows,
  }) : selectedNoteIds = List.unmodifiable(selectedNoteIds),
       includedNoteIds = List.unmodifiable(includedNoteIds),
       rows = List.unmodifiable(rows.map(freezeJsonMap)),
       objectCounts = Map.unmodifiable({'claimDraft': rows.length}),
       super(
         kind: LocalExportKind.claimDrafts,
         formatVersion: 'research-claim-drafts-v2',
         mimeType: 'application/x-ndjson',
         sha256: _bytesDigest(bytes),
         dedupedObjectCount: rows.length,
         preparationVersion: 1,
       );
  final List<String> selectedNoteIds, includedNoteIds;
  final List<Map<String, Object?>> rows;
  final Map<String, int> objectCounts;
}

/// Content-only preparation: SQL SELECTs and trusted document reads, never
/// exports, bindings, business mutations, formal claims, or file writes.
class ResearchClaimDraftPreparer {
  ResearchClaimDraftPreparer(
    this.store, {
    required this.readDocument,
    String Function()? newDraftId,
  }) : _newDraftId = newDraftId ?? (() => 'c-wb-${const Uuid().v4()}');
  final WorkbenchStore store;
  final ClaimDraftDocumentReader readDocument;
  final String Function() _newDraftId;
  static final _id = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$');
  static final _hash = RegExp(r'^[0-9a-f]{64}$');

  Future<ResearchClaimDraftPreparation> prepareClaimDrafts({
    required String projectId,
    required List<String> noteIds,
    required ResolvedAssistantScope scope,
    required DateTime generatedAt,
  }) async {
    // Freeze caller selections before the first await.
    final selected = List<String>.unmodifiable(noteIds);
    if (projectId.trim().isEmpty ||
        selected.isEmpty ||
        selected.any((id) => id.trim().isEmpty) ||
        selected.toSet().length != selected.length) {
      throw ClaimDraftPreparationFailure('invalid_selection');
    }
    final scoped = store.scoped(projectId);
    final projects = scoped.projects();
    if (projects.length != 1) {
      throw ClaimDraftPreparationFailure('missing_project');
    }
    final project = projects.single;
    final entries = scoped.entries(projectId);
    if (project.layout != 'research-skill-v2' ||
        revisionGroups(
          entries.where((e) => skillKinds.contains(e.kind)).toList(),
        ).any(
          (g) => g.current.data['active'] != false && !_v2(g.current.data),
        )) {
      throw ClaimDraftPreparationFailure('requires_schema_v2');
    }
    ObjectRef? selectedRef(String type, String id) => scope.objects
        .where(
          (ref) =>
              ref.moduleId == 'research' &&
              ref.objectType == type &&
              ref.nativeProjectId == projectId &&
              ref.objectId == id,
        )
        .firstOrNull;
    final projectRef = selectedRef('project', projectId);
    if (projectRef == null ||
        projectRef.revisionRef != null ||
        projectRef.contentDigest !=
            _digest([project.title, project.question, project.nextStep])) {
      throw ClaimDraftPreparationFailure('project_outside_current_scope');
    }
    final docs = scoped.documents(projectId);
    final notes = <String, (ResearchDocument, ReadingNote)>{
      for (final doc in docs)
        for (final note in scoped.notes(doc.id)) note.id: (doc, note),
    };
    // A single missing/foreign/stale note refuses the whole selection before
    // reading any source bytes, rather than silently skipping unauthorized IDs.
    for (final id in selected) {
      final noteRef = selectedRef('note', id);
      final pair = notes[id];
      if (pair == null ||
          noteRef == null ||
          noteRef.revisionRef != null ||
          noteRef.contentDigest != _scopeDigest(_row('notes', id))) {
        throw ClaimDraftPreparationFailure('note_outside_current_scope');
      }
    }
    final before = _sourceState(projectId);
    final bindings = scoped.bindings(projectId);
    final papers = entries.where((e) => e.kind == 'papers').toList();
    final sourceEntries = entries.where((e) => e.kind == 'sources').toList();
    final sources = <(String, String), ObjectRef>{};
    void pin(String type, String id, Object? value, {String? revision}) {
      sources[(type, id)] = ObjectRef(
        moduleId: 'research',
        nativeProjectId: projectId,
        objectType: type,
        objectId: id,
        revisionRef: revision,
        contentDigest: _digest(value),
      );
    }

    sources[('project', projectId)] = projectRef;
    final exclusions = <LocalExportExclusion>[];
    final warnings = <String>[];
    final rows = <Map<String, Object?>>[];
    final included = <String>[];
    final draftIds = <String>{};
    final material = <String, List<int>?>{};
    final materialErrors = <String, String>{};
    for (final id in selected) {
      final (doc, note) = notes[id]!;
      sources[('note', id)] = selectedRef('note', id)!;
      final digest = doc.sha256;
      sources[('document', doc.id)] = ObjectRef(
        moduleId: 'research',
        nativeProjectId: projectId,
        objectType: 'document',
        objectId: doc.id,
        revisionRef: null,
        contentDigest: digest,
      );
      void exclude(String reason) =>
          exclusions.add(LocalExportExclusion(id, reason));
      final candidates = bindings.where((b) => b.documentId == doc.id).toList();
      pin('paper_binding', doc.id, [
        for (final b in candidates)
          [
            b.documentId,
            b.paperId,
            b.paperRev,
            b.method,
            b.hashOk,
            b.ambiguous,
          ],
      ]);
      if (candidates.length != 1 || candidates.single.ambiguous) {
        exclude(candidates.isEmpty ? 'missing_binding' : 'ambiguous_binding');
        continue;
      }
      final binding = candidates.single;
      final matches = papers
          .where(
            (e) =>
                e.data['id'] == binding.paperId &&
                e.data['rev'] is int &&
                e.data['rev'] == binding.paperRev,
          )
          .toList();
      if (matches.length != 1) {
        exclude('paper_revision_not_unique');
        continue;
      }
      final paper = matches.single;
      final paperData = paper.data;
      final upstream = sourceEntries
          .where(
            (e) =>
                e.data['id'] == paperData['source_id'] &&
                e.data['rev'] is int &&
                e.data['rev'] == paperData['source_rev'],
          )
          .toList();
      pin(
        'entry',
        paper.id,
        _row('entries', paper.id),
        revision: '${binding.paperRev}',
      );
      if (!_v2(paperData) ||
          binding.paperRev < 1 ||
          paperData['source_id'] is! String ||
          paperData['source_rev'] is! int ||
          upstream.length != 1 ||
          !_v2(upstream.single.data)) {
        exclude('invalid_pinned_source');
        continue;
      }
      final source = upstream.single;
      pin(
        'entry',
        source.id,
        _row('entries', source.id),
        revision: '${source.data['rev']}',
      );
      final relative = doc.relativePath;
      final root = project.skillRoot;
      if (RegExp(r'^[A-Za-z]:').hasMatch(relative) ||
          relative.contains('\\') ||
          relative.contains('\u0000') ||
          p.posix.isAbsolute(relative) ||
          relative.split('/').contains('..') ||
          (root.isNotEmpty &&
              (!root.endsWith('/') || !relative.startsWith(root))) ||
          digest == null ||
          !_hash.hasMatch(digest)) {
        exclude('invalid_document_pin');
        continue;
      }
      final projectPath = relative.substring(root.length);
      if (projectPath.isEmpty ||
          p.posix.normalize(projectPath) != projectPath) {
        exclude('invalid_document_path');
        continue;
      }
      if (!material.containsKey(doc.id)) {
        try {
          final bytes = List<int>.unmodifiable(
            await readDocument(sources[('document', doc.id)]!),
          );
          if (bytes.length > 30 * 1024 * 1024 ||
              (!doc.isPdf && bytes.length > 16 * 1024 * 1024)) {
            materialErrors[doc.id] = 'source_too_large';
          } else if (_bytesDigest(bytes) != digest) {
            materialErrors[doc.id] = 'source_digest_mismatch';
          } else {
            material[doc.id] = bytes;
          }
        } on Object {
          materialErrors[doc.id] = 'source_unavailable';
        }
        material.putIfAbsent(doc.id, () => null);
      }
      if (materialErrors[doc.id] case final reason?) {
        exclude(reason);
        continue;
      }
      String? text;
      if (!doc.isPdf) {
        try {
          text = stripBom(utf8.decode(material[doc.id]!));
        } on FormatException {
          warnings.add('text_extraction_failed:$id');
        }
      }
      final draftId = _newDraftId();
      if (!_id.hasMatch(draftId) ||
          !draftIds.add(draftId) ||
          entries.any((e) => e.kind == 'claims' && e.data['id'] == draftId)) {
        throw ClaimDraftPreparationFailure('invalid_draft_identity');
      }
      final row = claimDraft(
        DraftSource(
          note: note,
          document: doc,
          projectPath: projectPath,
          binding: binding,
          paper: paper,
          text: text,
        ),
        id: draftId,
        now: generatedAt,
      );
      if (utf8.encode(jsonEncode(row)).length > 1024 * 1024) {
        exclude('draft_line_too_large');
        continue;
      }
      if (!binding.hashOk) warnings.add('binding_hash_mismatch:$id');
      rows.add(freezeJsonMap(row));
      included.add(id);
    }
    // Revalidate all relevant source rows after every awaited reader has
    // finished: deletes, new candidate bindings and schema/pin edits all refuse.
    if (_sourceState(projectId) != before) {
      throw ClaimDraftPreparationFailure('source_changed_during_preparation');
    }
    if (rows.isEmpty) {
      throw ClaimDraftPreparationFailure(
        'no_exportable_notes',
        exclusions: exclusions,
      );
    }
    if (exclusions.isNotEmpty) {
      warnings.add('partial_export_requires_new_confirmation');
    }
    final bytes = utf8.encode(encodeJsonl(rows));
    return ResearchClaimDraftPreparation._(
      generatedAt: generatedAt,
      bytes: bytes,
      sources: sources.values.toList(),
      exclusions: exclusions,
      warnings: warnings,
      selectedNoteIds: selected,
      includedNoteIds: included,
      rows: rows,
      manifestDigest: _digest({
        'kind': 'claimDrafts',
        'formatVersion': 'research-claim-drafts-v2',
        'preparationVersion': 1,
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'projectId': projectId,
        'scope': scope.toJson(),
        'sourceStateDigest': before,
        'selectedNoteIds': selected,
        'includedNoteIds': included,
        'draftIds': rows.map((r) => r['id']).toList(),
        'sha256': _bytesDigest(bytes),
        'objectCounts': {'claimDraft': rows.length},
        'sources': sources.values.map((s) => s.toJson()).toList(),
        'exclusions': [
          for (final e in exclusions) {'id': e.id, 'reason': e.reason},
        ],
        'warnings': warnings,
      }),
    );
  }

  Map<String, Object?> _row(String table, String id) =>
      Map<String, Object?>.from(
        store.db.select('SELECT * FROM $table WHERE id=?', [id]).single,
      );

  String _sourceState(String project) => _digest({
    'project': store.db
        .select('SELECT * FROM projects WHERE id=?', [project])
        .map((r) => Map<String, Object?>.from(r))
        .toList(),
    'documents': store.db
        .select('SELECT * FROM documents WHERE project_id=? ORDER BY rowid', [
          project,
        ])
        .map((r) => Map<String, Object?>.from(r))
        .toList(),
    'entries': store.db
        .select('SELECT * FROM entries WHERE project_id=? ORDER BY rowid', [
          project,
        ])
        .map((r) => Map<String, Object?>.from(r))
        .toList(),
    'notes': store.db
        .select(
          'SELECT n.* FROM notes n JOIN documents d ON n.document_id=d.id WHERE d.project_id=? ORDER BY n.rowid',
          [project],
        )
        .map((r) => Map<String, Object?>.from(r))
        .toList(),
    'bindings': store.db
        .select(
          'SELECT b.* FROM paper_bindings b JOIN documents d ON b.document_id=d.id WHERE d.project_id=? ORDER BY b.rowid',
          [project],
        )
        .map((r) => Map<String, Object?>.from(r))
        .toList(),
  });
}

String _bytesDigest(List<int> bytes) => sha256.convert(bytes).toString();
String _digest(Object? value) =>
    _bytesDigest(utf8.encode(canonicalJson(value)));

String _scopeDigest(Object? value) =>
    _bytesDigest(utf8.encode(jsonEncode(value)));

bool _v2(Map<String, dynamic> data) =>
    data['schema_version'] is int && data['schema_version'] == 2;
