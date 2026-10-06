import 'package:muyon_module_api/muyon_module_api.dart';
import 'package:sqlite3/sqlite3.dart';

/// Host schema v9. Row triggers cover both domain writes and package imports,
/// and SQLite commits/rolls them back with the changed business row. Each
/// trigger reads only the changed object and its indexed parent/head rows.
void installResearchChangeLog(Database db) {
  ModuleChangeLog.createTable(db);
  void track(
    String table,
    String type, {
    String id = 'r.id',
    String project = 'r.project_id',
    required String summary,
    String revision = 'NULL',
    String digest = 'NULL',
    String filter = '1',
  }) {
    String values(String row, String op) =>
        "'$type', ${id.replaceAll('r.', '$row.')}, "
        '${project.replaceAll('r.', '$row.')}, '
        '${revision.replaceAll('r.', '$row.')}, '
        '${digest.replaceAll('r.', '$row.')}, '
        "'$op', COALESCE(${summary.replaceAll('r.', '$row.')}, ''), "
        "strftime('%Y-%m-%dT%H:%M:%fZ','now')";
    const columns =
        'object_type,object_id,native_project_id,revision_ref,'
        'content_digest,op,summary,recorded_at';
    for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
      final row = event == 'DELETE' ? 'OLD' : 'NEW';
      db.execute('''
CREATE TRIGGER research_log_${table}_${event.toLowerCase()}
${event == 'DELETE' ? 'BEFORE' : 'AFTER'} $event ON $table
WHEN ${filter.replaceAll('r.', '$row.')}
BEGIN
  INSERT INTO ${ModuleChangeLog.table}($columns)
  SELECT ${values(row, event == 'DELETE' ? 'delete' : 'upsert')};
END;
''');
    }
    // Only migration-time seeding scans existing objects; normal writes never
    // poll/snapshot tables. This lets a v8 database populate host projections.
    db.execute(
      'INSERT INTO ${ModuleChangeLog.table}($columns) '
      "SELECT ${values('r', 'upsert')} FROM $table r WHERE $filter",
    );
  }

  track(
    'documents',
    'document',
    summary: 'r.relative_path',
    digest: 'r.sha256',
  );
  track('entries', 'entry', summary: 'r.title');
  track('sections', 'section', summary: 'r.heading');
  track('outline', 'outline', summary: 'r.heading');
  track(
    'runs',
    'run',
    project:
        '(SELECT t.project_id FROM tasks t '
        'WHERE t.id=r.task_id AND t.revision=r.task_revision)',
    summary:
        "(SELECT t.title FROM tasks t WHERE t.id=r.task_id "
        "AND t.revision=r.task_revision) || ' — ' || r.status",
    revision: 'CAST(r.task_revision AS TEXT)',
  );
  track(
    'rk_cards',
    'card',
    id: '(SELECT m.local_object_id FROM canonical_object_map m WHERE m.object_key=r.object_key)',
    project: '(SELECT m.local_project_id FROM canonical_object_map m WHERE m.object_key=r.object_key)',
    summary: "(SELECT substr(json_extract(v.envelope, '\$.bodyMarkdown'),1,240) FROM rk_revisions v WHERE v.revision_id=r.head_revision_id)",
    revision: 'r.head_revision_id',
    digest: '(SELECT v.digest FROM rk_revisions v WHERE v.revision_id=r.head_revision_id)',
  );

  // Canonical package documents retain immutable historical bytes. Only a
  // transition involving the current version changes the host directory.
  for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
    final row = event == 'DELETE' ? 'OLD' : 'NEW';
    final relevant = event == 'UPDATE'
        ? 'OLD.deleted=0 OR NEW.deleted=0'
        : '$row.deleted=0';
    db.execute('''
CREATE TRIGGER research_log_rk_documents_${event.toLowerCase()}
AFTER $event ON rk_documents WHEN $relevant BEGIN
  INSERT INTO ${ModuleChangeLog.table}(object_type,object_id,native_project_id,content_digest,op,summary,recorded_at)
  SELECT 'document',m.local_object_id,m.local_project_id,
    COALESCE(d.digest,$row.digest),CASE WHEN d.digest IS NULL THEN 'delete' ELSE 'upsert' END,
    COALESCE(d.file_name,$row.file_name),strftime('%Y-%m-%dT%H:%M:%fZ','now')
  FROM canonical_object_map m LEFT JOIN rk_documents d ON d.object_key=m.object_key AND d.deleted=0
  WHERE m.object_key=$row.object_key;
END;
''');
  }
  db.execute('''
INSERT INTO ${ModuleChangeLog.table}(object_type,object_id,native_project_id,content_digest,op,summary,recorded_at)
SELECT 'document',m.local_object_id,m.local_project_id,d.digest,'upsert',d.file_name,strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM rk_documents d JOIN canonical_object_map m ON m.object_key=d.object_key WHERE d.deleted=0;
''');

  // Task IDs have multiple revisions but the host directory has one row per
  // object. Removing an old revision must not remove a still-existing task.
  for (final event in ['INSERT', 'UPDATE', 'DELETE']) {
    final row = event == 'DELETE' ? 'OLD' : 'NEW';
    db.execute('''
CREATE TRIGGER research_log_tasks_${event.toLowerCase()}
AFTER $event ON tasks BEGIN
  INSERT INTO ${ModuleChangeLog.table}(object_type,object_id,native_project_id,revision_ref,op,summary,recorded_at)
  SELECT 'task',$row.id,$row.project_id,CAST(t.revision AS TEXT),'upsert',COALESCE(t.title,''),strftime('%Y-%m-%dT%H:%M:%fZ','now')
  FROM tasks t WHERE t.id=$row.id AND t.project_id=$row.project_id
  ORDER BY t.revision DESC LIMIT 1;
  INSERT INTO ${ModuleChangeLog.table}(object_type,object_id,native_project_id,revision_ref,op,summary,recorded_at)
  SELECT 'task',$row.id,$row.project_id,CAST($row.revision AS TEXT),'delete',COALESCE($row.title,''),strftime('%Y-%m-%dT%H:%M:%fZ','now')
  WHERE NOT EXISTS(SELECT 1 FROM tasks t WHERE t.id=$row.id AND t.project_id=$row.project_id);
END;
''');
  }
  db.execute('''
INSERT INTO ${ModuleChangeLog.table}(object_type,object_id,native_project_id,revision_ref,op,summary,recorded_at)
SELECT 'task',t.id,t.project_id,CAST(t.revision AS TEXT),'upsert',COALESCE(t.title,''),strftime('%Y-%m-%dT%H:%M:%fZ','now')
FROM tasks t WHERE t.revision=(SELECT MAX(v.revision) FROM tasks v WHERE v.id=t.id);
''');
}
