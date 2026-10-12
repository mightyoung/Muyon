import 'models.dart';
import 'store.dart';

/// Expected refusal to produce a complete authorized bounded preview.
class SectionDeletePreviewRefused extends StateError {
  SectionDeletePreviewRefused(super.message);
}

/// A frozen, read-only description, never a deletion authorization.
class SectionDeletePreview {
  SectionDeletePreview._({
    required this.section,
    required List<SectionDeletePreviewLink> links,
    required this.deleteDigest,
    required this.maxLinks,
    required this.maxBytes,
    required this.canReadEvidence,
  }) : links = List.unmodifiable(links);

  final OutlineSection section;
  final List<SectionDeletePreviewLink> links;
  final String deleteDigest;
  final int maxLinks, maxBytes;
  final bool Function(String type, String id)? canReadEvidence;
  bool get complete => true;
  bool get evidencePreserved => true;
  int get totalLinks => links.length;

  /// Native read access does not authorize disclosure to a model. Keep the
  /// local cascade digest and association identities out of this projection;
  /// the digest also depends on hidden section and association metadata.
  Map<String, Object?> toModel() => {
    'sectionId': section.id,
    'projectId': section.projectId,
    'complete': complete,
    'totalLinks': totalLinks,
    'evidencePreserved': evidencePreserved,
    'status': 'readOnly',
    'links': [for (final link in links) link.toModel()],
  };
}

class SectionDeletePreviewLink {
  const SectionDeletePreviewLink._({
    this.linkId,
    this.evidenceId,
    required this.status,
  });
  final String? linkId, evidenceId;
  // Bare legacy IDs cannot prove a historical evidence type.
  String? get type => null;
  final String status;

  /// A native permission callback is not a model disclosure grant. Identical
  /// restricted rows disclose neither identities nor their sorted positions.
  Map<String, Object?> toModel() => {'status': 'restricted'};
}

/// Snapshot the complete cascade before any projection or redaction.
/// A caller transaction already supplies its snapshot; otherwise BEGIN pins
/// the connection's read view, including the existing deletion digest query.
/// Never enters ManagedDatabase.write or persists a preview/receipt.
SectionDeletePreview captureSectionDeletePreview(
  WorkbenchStore store,
  String projectId,
  String sectionId, {
  int maxLinks = 500,
  int maxBytes = 1024 * 1024,
  bool Function(String type, String id)? canReadEvidence,
}) {
  if (maxLinks < 0 ||
      maxLinks > 5000 ||
      maxBytes < 1 ||
      maxBytes > 16 * 1024 * 1024) {
    throw SectionDeletePreviewRefused('Invalid preview budget');
  }
  final db = store.db;
  final ownTransaction = db.autocommit;
  if (ownTransaction) db.execute('BEGIN DEFERRED');
  try {
    try {
      store.checkedProject(projectId);
    } on StateError {
      throw SectionDeletePreviewRefused('Section preview outside scope');
    }
    // Count bytes in SQL before materializing text or calling the unbounded
    // existing digest. Six bytes per input byte bounds JSON escaping; fixed
    // allowances include keys, punctuation and numeric section metadata.
    final sectionSizes = db.select(
      'SELECT 1024 + 6 * (${_byteLengths(['id', 'project_id', 'heading', 'argument', 'support'])}) AS bytes '
      'FROM sections WHERE id=? AND project_id=?',
      [sectionId, projectId],
    );
    if (sectionSizes.length != 1) {
      throw SectionDeletePreviewRefused('Section preview unavailable');
    }
    final sizes = db.select(
      'SELECT COUNT(*) AS count, COALESCE(SUM(256 + 6 * '
      '(${_byteLengths(['id', 'project_id', 'heading', 'evidence_id', 'section_id'])})), 0) AS bytes '
      'FROM outline WHERE section_id=?',
      [sectionId],
    ).single;
    if ((sizes['count'] as int) > maxLinks ||
        (sectionSizes.single['bytes'] as int) + (sizes['bytes'] as int) >
            maxBytes) {
      throw SectionDeletePreviewRefused('Section preview exceeds budget');
    }
    final row = db.select(
      'SELECT * FROM sections WHERE id=? AND project_id=?',
      [sectionId, projectId],
    ).single;
    final section = OutlineSection(
      id: row['id'] as String,
      projectId: row['project_id'] as String,
      heading: row['heading'] as String,
      level: row['level'] as int,
      position: row['position'] as int,
      argument: row['argument'] as String,
      support: row['support'] as String,
    );
    // Do not filter by project: deleteSection also removes malformed links.
    final links = <SectionDeletePreviewLink>[];
    for (final link in db.select(
      'SELECT * FROM outline WHERE section_id=? ORDER BY id',
      [sectionId],
    )) {
      final evidenceId = link['evidence_id'] as String?;
      final types = evidenceId == null || link['project_id'] != projectId
          ? <String>[]
          : _localEvidenceTypes(store, projectId, evidenceId);
      final readable =
          types.isNotEmpty &&
          types.every(
            (type) => canReadEvidence?.call(type, evidenceId!) ?? true,
          );
      links.add(
        readable
            // The legacy association has no persisted type. Current entity
            // matches establish visibility, not its historical identity.
            ? SectionDeletePreviewLink._(
                linkId: link['id'] as String,
                evidenceId: evidenceId,
                status: 'unknown',
              )
            : const SectionDeletePreviewLink._(status: 'restricted'),
      );
    }
    return SectionDeletePreview._(
      section: section,
      links: links,
      deleteDigest: sectionDeleteDigest(store, projectId, sectionId)!,
      maxLinks: maxLinks,
      maxBytes: maxBytes,
      canReadEvidence: canReadEvidence,
    );
  } finally {
    // This transaction contains SELECTs only. Rollback releases its snapshot
    // without accidentally committing a caller-owned transaction.
    if (ownTransaction) db.execute('ROLLBACK');
  }
}

String _byteLengths(List<String> columns) => columns
    .map((column) => 'COALESCE(length(CAST($column AS BLOB)),0)')
    .join(' + ');

List<String> _localEvidenceTypes(
  WorkbenchStore store,
  String projectId,
  String id,
) {
  final db = store.db;
  return [
    if (db.select('SELECT id FROM entries WHERE id=? AND project_id=?', [
      id,
      projectId,
    ]).isNotEmpty)
      'entry',
    if (db.select(
      'SELECT n.id FROM notes n JOIN documents d ON d.id=n.document_id WHERE n.id=? AND d.project_id=?',
      [id, projectId],
    ).isNotEmpty)
      'note',
    if (db.select(
      'SELECT r.id FROM runs r JOIN tasks t ON t.id=r.task_id AND t.revision=r.task_revision WHERE r.id=? AND t.project_id=?',
      [id, projectId],
    ).isNotEmpty)
      'run',
  ];
}

/// Freshness is advisory display state, not a write CAS or approval.
bool sectionDeletePreviewIsCurrent(
  WorkbenchStore store,
  SectionDeletePreview preview,
) {
  try {
    final current = captureSectionDeletePreview(
      store,
      preview.section.projectId,
      preview.section.id,
      maxLinks: preview.maxLinks,
      maxBytes: preview.maxBytes,
      canReadEvidence: preview.canReadEvidence,
    );
    if (current.deleteDigest != preview.deleteDigest) return false;
    // A permission or entity-visibility change can invalidate the display even
    // if the deletion-specific digest remains unchanged.
    for (var i = 0; i < current.links.length; i++) {
      if (current.links[i].status != preview.links[i].status) return false;
    }
    return true;
  } on SectionDeletePreviewRefused {
    return false;
  }
}
