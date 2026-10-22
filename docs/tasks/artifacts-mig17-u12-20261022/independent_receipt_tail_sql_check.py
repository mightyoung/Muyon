"""Real SQLite receipt-trigger fault checks. Does not execute Rust guards."""
import json
import pathlib
import re
import sqlite3
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
CORE = ROOT / 'crates/muyon-core/src'
ARTIFACTS = CORE / 'artifacts'
business = (CORE / 'business.rs').read_text()
documents = (CORE / 'documents/storage.rs').read_text()
blobs = (CORE / 'blobs.rs').read_text()
artifacts = (ARTIFACTS / 'mod.rs').read_text()
project = (ARTIFACTS / 'project_access.rs').read_text()
journal = (ARTIFACTS / 'save_journal.rs').read_text()
tests = (ARTIFACTS / 'workflow_tests.rs').read_text()

def statement(source, prefix):
    match = re.search('"(' + re.escape(prefix) + '[^"\\n]+)"', source)
    assert match, prefix
    return match.group(1)

def rows(db, table):
    return db.execute('SELECT * FROM ' + table + ' ORDER BY 1,2').fetchall()

mutation_section = tests.split('fn receipt_tail_invalidation_rolls_back_all_effects_and_preserves_original_pending()', 1)[1].split('] {', 1)[0]
mutations = re.findall(r'"(UPDATE [^"]+)"', mutation_section)
assert len(mutations) == 10

doc_query = statement(documents, 'SELECT CASE WHEN length(CAST(document_json AS BLOB))<=8192')
history_query = statement(documents, 'SELECT CASE WHEN length(CAST(current_document_json AS BLOB))<=8192')
project_query = statement(project, 'SELECT CASE WHEN length(CAST(permissions AS BLOB))<=256')
receipt_update = statement(journal, "UPDATE artifact_save_intents_v1 SET status='committed'")

with tempfile.TemporaryDirectory(prefix='receipt-tail-independent-') as directory:
    for number, mutation in enumerate(mutations):
        db = sqlite3.connect(directory + '/' + str(number) + '.sqlite')
        db.execute('PRAGMA foreign_keys=ON')
        for ddl in re.findall(r'"(CREATE TABLE [^"\n]+)"', business):
            db.execute(ddl)
        for source in (documents, artifacts, project):
            for _, ddl in re.findall(r'\("(\w+)", "(CREATE TABLE [^"]+)"\)', source):
                db.execute(ddl)
        db.execute(re.search(r'const HISTORY_SCHEMA: &str = "([^"]+)"', documents).group(1))
        db.execute("INSERT INTO projects VALUES('project','workspace','Synthetic','1',0)")
        db.execute("INSERT INTO blobs VALUES('old-digest','1','ready')")
        db.execute("INSERT INTO blobs VALUES('new-digest','1','ready')")
        db.execute("INSERT INTO blob_uploads VALUES('upload','snapshot','workspace','project','1','epoch','pinned','1','new-digest','pdf')")
        db.execute("INSERT INTO blob_pins VALUES('pin','new-digest','upload','upload','snapshot','epoch')")
        db.execute("INSERT INTO blob_references VALUES('old-ref','project','report','old-digest')")
        db.execute("INSERT INTO document_heads VALUES('project','report','1')")
        db.execute("INSERT INTO document_heads VALUES('project','source','2')")
        for identity, revision in [('report', '1'), ('source', '1'), ('source', '2')]:
            db.execute('INSERT INTO document_revisions VALUES(?,?,?,?)', ('project', identity, revision, '{}'))
        db.execute("INSERT INTO document_grants VALUES('grant-report','1','epoch','output-v1','[\"read_text\",\"structured_edit\"]','9999999999999',1)")
        db.execute("INSERT INTO document_grants VALUES('grant-source','2','epoch','source-v2','[\"read_text\"]','9999999999999',1)")
        db.execute("INSERT INTO document_history_grants_v1 VALUES('grant-source','2','epoch','source-v2','source-v1','[\"read_text\"]','9999999999999',1)")
        db.execute("INSERT INTO artifact_project_grants_v1 VALUES('project-grant','1','epoch','project','1','actor','[\"save\"]','9999999999999',1)")
        db.execute("INSERT INTO artifact_heads VALUES('project','artifact','report','1')")
        db.execute("INSERT INTO artifact_revisions VALUES('project','artifact','1','{}')")
        db.execute("INSERT INTO artifact_save_intents_v1 VALUES('tail-save','project','actor','digest','{}','pending',NULL,NULL)")
        db.commit()  # Durable pending precedes the simulated effect transaction.
        tables = ['document_heads', 'document_revisions', 'blob_uploads', 'blob_pins', 'blob_references', 'artifact_heads', 'artifact_revisions', 'artifact_save_intents_v1', 'document_grants', 'document_history_grants_v1', 'artifact_project_grants_v1']
        before = {table: rows(db, table) for table in tables}
        db.execute("CREATE TRIGGER invalidate_on_receipt AFTER UPDATE ON artifact_save_intents_v1 WHEN NEW.intent_id='tail-save' AND NEW.status='committed' BEGIN " + mutation + '; END')
        db.commit()
        db.execute('BEGIN IMMEDIATE')
        db.execute(statement(blobs, 'INSERT INTO blob_references(reference_id,project_id,target_id,digest)'), ('new-ref', 'project', 'report', 'new-digest'))
        db.execute(statement(blobs, "UPDATE blob_uploads SET state='committed'"), ('upload',))
        db.execute(statement(blobs, "DELETE FROM blob_pins WHERE kind='upload'"), ('upload',))
        db.execute(statement(documents, 'UPDATE document_heads SET revision=?'), ('2', 'project', 'report', '1'))
        db.execute(statement(documents, 'INSERT INTO document_revisions VALUES'), ('project', 'report', '2', '{}'))
        db.execute(statement(artifacts, 'UPDATE artifact_heads SET revision=?'), ('2', 'project', 'artifact', 'report', '1'))
        db.execute(statement(artifacts, 'INSERT INTO artifact_revisions VALUES'), ('project', 'artifact', '2', '{}'))
        assert db.execute(receipt_update, ('{"receipt":true}', 'tail-save', 'digest')).rowcount == 1

        # Execute the exact SQL guards and inspect their raw rows/expiry fields.
        # Rust decoding, canonical snapshot equality and dispatch are NOT run.
        output = db.execute(doc_query, ('grant-report', '1', 'epoch')).fetchall()
        source = db.execute(doc_query, ('grant-source', '2', 'epoch')).fetchall()
        history = db.execute(history_query, ('grant-source', '2', 'epoch', 'source-v1')).fetchall()
        permission = db.execute(project_query, ('project-grant', '1', 'epoch', 'project', '1', 'actor')).fetchall()
        valid_output = bool(output) and output[0][0] == 'output-v1' and int(output[0][2]) > 1
        valid_source = bool(source) and source[0][0] == 'source-v2' and int(source[0][2]) > 1
        valid_history = bool(history) and history[0][0] == 'source-v2' and int(history[0][2]) > 1
        valid_project = bool(permission) and int(permission[0][1]) > 1
        assert not (valid_output and valid_source and valid_history and valid_project), mutation
        db.rollback()  # Models the Rust Transaction Drop on a failed final guard.
        assert {table: rows(db, table) for table in tables} == before, mutation
        db.execute('DROP TRIGGER invalidate_on_receipt')
        db.commit()
        db.close()
        db = sqlite3.connect(directory + '/' + str(number) + '.sqlite')
        assert db.execute("SELECT status,receipt_json,error FROM artifact_save_intents_v1 WHERE intent_id='tail-save'").fetchone() == ('pending', None, None)
        assert db.execute("SELECT revision FROM document_heads WHERE document_id='report'").fetchone()[0] == '1'
        db.close()

print(json.dumps({
    'real_sqlite_after_receipt_mutations': len(mutations),
    'source_sql_guards_detect_each_mutation': 'PASS',
    'document_blob_upload_pin_artifact_receipt_and_grant_rollback': 'PASS',
    'reopen_preserves_original_pending_without_receipt': 'PASS',
    'rust_tail_order_failure_dispatch_unknown_and_no_retry': 'STATIC_REVIEW_ONLY',
    'rust_compilation_and_tests': 'NOT_RUN: cargo/rustc absent',
}, sort_keys=True))
