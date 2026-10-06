import 'package:uuid/uuid.dart';

import 'models.dart';
import 'store.dart';

/// Ordered outline sections, each citing any number of evidence IDs (research
/// records, accepted runs or reading notes).
extension OutlineStore on WorkbenchStore {
  List<OutlineSection> sections(String projectId) => db
      .select('SELECT * FROM sections WHERE project_id=? ORDER BY position', [
        checkedProject(projectId),
      ])
      .map(
        (r) => OutlineSection(
          id: r['id'],
          projectId: r['project_id'],
          heading: r['heading'],
          level: r['level'],
          position: r['position'],
          argument: r['argument'],
          support: r['support'],
        ),
      )
      .toList();

  OutlineSection addSection(String projectId, String heading, {int level = 1}) {
    checkedProject(projectId);
    _check(heading, level, 'unassessed');
    final position =
        (db.select(
                  'SELECT MAX(position) AS m FROM sections WHERE project_id=?',
                  [projectId],
                ).first['m']
                as int? ??
            0) +
        1;
    final id = const Uuid().v4();
    db.execute(
      'INSERT INTO sections(id,project_id,heading,level,position) VALUES(?,?,?,?,?)',
      [id, projectId, heading.trim(), level, position],
    );
    return sections(projectId).firstWhere((s) => s.id == id);
  }

  void updateSection(
    String id, {
    required String heading,
    required int level,
    required String argument,
    required String support,
  }) {
    checkedObject('sections', id);
    _check(heading, level, support);
    db.execute(
      'UPDATE sections SET heading=?,level=?,argument=?,support=? WHERE id=?',
      [heading.trim(), level, argument.trim(), support, id],
    );
    // Keep the denormalised heading on evidence links in step.
    db.execute('UPDATE outline SET heading=? WHERE section_id=?', [
      heading.trim(),
      id,
    ]);
  }

  /// Swaps a section with its neighbour; [delta] is -1 (up) or 1 (down).
  void moveSection(String id, int delta) {
    checkedObject('sections', id);
    final row = db.select('SELECT project_id FROM sections WHERE id=?', [id]);
    if (row.isEmpty) throw StateError('Unknown section');
    final all = sections(row.first['project_id'] as String);
    final i = all.indexWhere((s) => s.id == id);
    final j = i + delta.sign;
    if (j < 0 || j >= all.length) return;
    db.execute('UPDATE sections SET position=? WHERE id=?', [
      all[j].position,
      all[i].id,
    ]);
    db.execute('UPDATE sections SET position=? WHERE id=?', [
      all[i].position,
      all[j].id,
    ]);
  }

  /// Removes a section and its evidence links; the evidence itself stays.
  void deleteSection(String id) {
    checkedObject('sections', id);
    db.execute('DELETE FROM outline WHERE section_id=?', [id]);
    db.execute('DELETE FROM sections WHERE id=?', [id]);
  }

  /// Cites [evidenceId] under the section titled [heading], creating the
  /// section at the end when none matches.
  void addOutline(String projectId, String heading, String evidenceId) {
    final section =
        sections(projectId)
            .where((s) => s.heading == heading.trim())
            .firstOrNull ??
        addSection(projectId, heading);
    cite(section.id, evidenceId);
  }

  /// Cites [evidenceId] in a section; citing it there again is a no-op.
  void cite(String sectionId, String evidenceId) {
    checkedObject('sections', sectionId);
    if (projectScope != null) {
      final evidence = db.select(
        '''SELECT project_id FROM entries WHERE id=?
UNION ALL SELECT d.project_id FROM notes n JOIN documents d ON d.id=n.document_id WHERE n.id=?
UNION ALL SELECT t.project_id FROM runs r JOIN tasks t ON t.id=r.task_id AND t.revision=r.task_revision WHERE r.id=? AND r.accepted=1''',
        [evidenceId, evidenceId, evidenceId],
      );
      if (evidence.isEmpty ||
          evidence.any((row) => row['project_id'] != projectScope)) {
        throw StateError('Evidence outside workspace scope or not accepted');
      }
    }
    final rows = db.select('SELECT * FROM sections WHERE id=?', [sectionId]);
    if (rows.isEmpty) throw StateError('Unknown section');
    final s = rows.single;
    db.execute(
      'INSERT INTO outline(id,project_id,heading,evidence_id,section_id) '
      'SELECT ?,?,?,?,? WHERE NOT EXISTS '
      '(SELECT 1 FROM outline WHERE section_id=? AND evidence_id=?)',
      [
        const Uuid().v4(),
        s['project_id'],
        s['heading'],
        evidenceId,
        sectionId,
        sectionId,
        evidenceId,
      ],
    );
  }

  void removeOutline(String id) => db.execute(
    'DELETE FROM outline WHERE id=?',
    [checkedObject('outline', id)],
  );

  static void _check(String heading, int level, String support) {
    if (heading.trim().isEmpty) throw const FormatException('段落标题不能为空');
    if (level < 1 || level > 3) throw const FormatException('层级须为 1–3');
    if (!sectionSupport.containsKey(support)) {
      throw FormatException('未知支持程度：$support');
    }
  }
}
