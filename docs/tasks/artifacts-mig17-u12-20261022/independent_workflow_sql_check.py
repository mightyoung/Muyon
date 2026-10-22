"""Execute source SQL in a synthetic on-disk store. Not Rust execution."""
import json
import pathlib
import re
import sqlite3
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
ARTIFACTS = ROOT / 'crates/muyon-core/src/artifacts'
project_source = (ARTIFACTS / 'project_access.rs').read_text()
journal_source = (ARTIFACTS / 'save_journal.rs').read_text()
catalog_source = (ARTIFACTS / 'catalog.rs').read_text()
base_source = (ARTIFACTS / 'mod.rs').read_text()
document_source = (ROOT / 'crates/muyon-core/src/documents/storage.rs').read_text()

def statement(text, prefix):
    match = re.search('"(' + re.escape(prefix) + '[^"\\n]+)"', text)
    assert match, prefix
    return match.group(1)

def setup(path):
    db = sqlite3.connect(path)
    db.execute('PRAGMA foreign_keys=ON')
    db.execute('CREATE TABLE projects(id TEXT PRIMARY KEY)')
    db.execute("INSERT INTO projects VALUES('project')")
    db.execute("INSERT INTO projects VALUES('other-project')")
    for source in (base_source, project_source):
        for name, ddl in re.findall(r'\("(artifact_[a-z_0-9]+)", "(CREATE TABLE [^"]+)"\)', source):
            db.execute(ddl)
            assert db.execute('SELECT sql FROM sqlite_master WHERE name=?', (name,)).fetchone()[0] == ddl
    db.commit()
    return db

with tempfile.TemporaryDirectory(prefix='artifact-workflow-independent-') as directory:
    path = directory + '/synthetic.sqlite'
    db = setup(path)
    issue = statement(project_source, 'INSERT INTO artifact_project_grants_v1 VALUES')
    authorize = statement(project_source, 'SELECT CASE WHEN length(CAST(permissions AS BLOB))<=256')
    db.execute(issue, ('grant', '1', 'epoch', 'project', '1', 'actor', '["discover","save","lookup_own_saves"]', '9999999999999'))
    binding = ('grant', '1', 'epoch', 'project', '1', 'actor')
    assert len(db.execute(authorize, binding).fetchall()) == 1
    for position, bad in [(0, 'document-grant'), (1, '2'), (2, 'old-epoch'), (3, 'other-project'), (4, '2'), (5, 'another-actor')]:
        changed = list(binding)
        changed[position] = bad
        assert db.execute(authorize, changed).fetchall() == []
    db.execute("UPDATE artifact_project_grants_v1 SET active=0")
    assert db.execute(authorize, binding).fetchall() == []
    db.execute(issue, ('grant', '2', 'epoch', 'project', '1', 'actor', '["discover"]', '9999999999999'))
    assert db.execute(authorize, binding).fetchall() == []
    assert len(db.execute(authorize, ('grant', '2', 'epoch', 'project', '1', 'actor')).fetchall()) == 1
    pending = statement(journal_source, 'INSERT INTO artifact_save_intents_v1 VALUES')
    committed = statement(journal_source, "UPDATE artifact_save_intents_v1 SET status='committed'")
    rejected = statement(journal_source, "UPDATE artifact_save_intents_v1 SET status='rejected'")
    db.execute(pending, ('intent', 'project', 'actor', 'digest', '{"synthetic":true}'))
    db.commit()
    db.close()
    db = sqlite3.connect(path)
    assert db.execute("SELECT status,receipt_json FROM artifact_save_intents_v1 WHERE intent_id='intent'").fetchone() == ('pending', None)
    db.execute("CREATE TRIGGER fail_artifact BEFORE INSERT ON artifact_revisions BEGIN SELECT RAISE(ABORT,'synthetic'); END")
    db.commit()
    try:
        db.execute('BEGIN IMMEDIATE')
        db.execute("INSERT INTO artifact_heads VALUES('project','artifact','document','1')")
        db.execute("INSERT INTO artifact_revisions VALUES('project','artifact','1','{}')")
        db.execute(committed, ('{"receipt":true}', 'intent', 'digest'))
        db.commit()
        raise AssertionError('fault did not abort effect')
    except sqlite3.IntegrityError:
        db.rollback()
    assert db.execute('SELECT COUNT(*) FROM artifact_heads').fetchone()[0] == 0
    assert db.execute("SELECT status FROM artifact_save_intents_v1 WHERE intent_id='intent'").fetchone()[0] == 'pending'
    db.execute('DROP TRIGGER fail_artifact')
    db.commit()
    db.execute('BEGIN IMMEDIATE')
    db.execute("INSERT INTO artifact_heads VALUES('project','artifact','document','1')")
    db.execute("INSERT INTO artifact_revisions VALUES('project','artifact','1','{}')")
    assert db.execute(committed, ('{"receipt":true}', 'intent', 'digest')).rowcount == 1
    db.commit()
    # The journal terminal transition itself is conditional and cannot overwrite
    # a terminal receipt; Rust must still check the returned changed-row count.
    assert db.execute(committed, ('{"wrong":true}', 'intent', 'digest')).rowcount == 0
    assert db.execute(rejected, ('"InvalidAuthority"', 'intent', 'digest')).rowcount == 0
    db.commit()
    db.close()
    db = sqlite3.connect(path)
    assert db.execute("SELECT status,receipt_json FROM artifact_save_intents_v1 WHERE intent_id='intent'").fetchone() == ('committed', '{"receipt":true}')
    assert db.execute('SELECT COUNT(*) FROM artifact_heads').fetchone()[0] == 1
    assert db.execute('SELECT COUNT(*) FROM artifact_revisions').fetchone()[0] == 1
    own_lookup = re.search(r'"(SELECT CASE[^\n"]+WHERE intent_id=\? AND project_id=\? AND actor_id=\?)"', journal_source).group(1)
    assert len(db.execute(own_lookup, ('intent', 'project', 'actor')).fetchall()) == 1
    assert db.execute(own_lookup, ('intent', 'project', 'another-actor')).fetchall() == []
    assert db.execute(own_lookup, ('absent', 'project', 'another-actor')).fetchall() == []
    assert db.execute(own_lookup, ('intent', 'other-project', 'actor')).fetchall() == []
    catalog = statement(catalog_source, 'SELECT CASE WHEN length(CAST(artifact_id AS BLOB))<=128')
    assert len(db.execute(catalog, ('project', '', '32')).fetchall()) == 1
    assert db.execute(catalog, ('other-project', '', '32')).fetchall() == []
    assert db.execute(catalog, ('project', 'artifact', '32')).fetchall() == []
    history_schema = re.search(r'const HISTORY_SCHEMA: &str = "([^"]+)"', document_source).group(1)
    db.execute('CREATE TABLE document_grants(grant_id TEXT PRIMARY KEY)')
    db.execute("INSERT INTO document_grants VALUES('history-grant')")
    db.execute(history_schema)
    history_issue = statement(document_source, 'INSERT INTO document_history_grants_v1 VALUES')
    history_read = statement(document_source, 'SELECT CASE WHEN length(CAST(current_document_json AS BLOB))<=8192')
    db.execute(history_issue, ('history-grant', '2', 'epoch', 'exact-current-v2', 'exact-history-v1', '["read_text"]', '9999999999999'))
    history_binding = ('history-grant', '2', 'epoch', 'exact-history-v1')
    assert db.execute(history_read, history_binding).fetchone()[0] == 'exact-current-v2'
    for position, bad in [(0, 'other-grant'), (1, '1'), (2, 'old-epoch'), (3, 'other-history')]:
        changed = list(history_binding)
        changed[position] = bad
        assert db.execute(history_read, changed).fetchall() == []
    db.execute('UPDATE document_history_grants_v1 SET active=0')
    assert db.execute(history_read, history_binding).fetchall() == []
    db.close()

print(json.dumps({
    'ddl_exact_roundtrip': 'PASS',
    'project_grant_exact_sql_bindings_and_revocation': 'PASS',
    'durable_pending_before_failed_effect_and_restart': 'PASS',
    'effect_plus_original_receipt_sql_atomicity': 'PASS',
    'conditional_terminal_sql_transitions': 'PASS',
    'catalog_project_and_exclusive_cursor_sql': 'PASS',
    'own_lookup_actor_project_filter_and_absent_equivalence': 'PASS',
    'core_explicit_history_grant_sql_binding_and_revocation': 'PASS',
    'rust_compilation_and_rust_behavior': 'NOT_RUN: cargo/rustc absent',
    'policy_expiry_digest_validation_and_no_retry_dispatch': 'STATIC_REVIEW_ONLY',
}, sort_keys=True))
