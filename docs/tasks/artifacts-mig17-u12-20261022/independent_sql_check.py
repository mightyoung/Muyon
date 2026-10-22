"""Independent SQL-only checks. This does not compile or execute Rust."""
import json
import pathlib
import re
import sqlite3
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
source = ROOT / 'crates/muyon-core/src/artifacts/mod.rs'
text = source.read_text()
ddls = re.findall(r'\("(artifact_[a-z_]+)", "(CREATE TABLE [^"]+)"\)', text)
assert len(ddls) == 3
with tempfile.TemporaryDirectory(prefix='artifact-independent-') as directory:
    connection = sqlite3.connect(directory + '/synthetic.sqlite')
    connection.execute('PRAGMA foreign_keys=ON')
    connection.execute('CREATE TABLE projects(id TEXT PRIMARY KEY)')
    connection.execute("INSERT INTO projects VALUES('project')")
    for name, ddl in ddls:
        connection.execute(ddl)
        actual = connection.execute('SELECT sql FROM sqlite_master WHERE name=?', (name,)).fetchone()[0]
        assert actual == ddl
    connection.execute("INSERT INTO artifact_heads VALUES('project','artifact','report','1')")
    for revision in ['1', '2', '9', '10', '99', '100', '18446744073709551615']:
        connection.execute('INSERT INTO artifact_revisions VALUES(?,?,?,?)', ('project', 'artifact', revision, '{}'))
    query = re.search(r'query\("(SELECT CASE WHEN length\(CAST\(revision AS BLOB\)\)<=20 THEN revision ELSE NULL END FROM artifact_revisions[^\"]+)', text).group(1)
    cursor = '18446744073709551616'
    actual = [row[0] for row in connection.execute(query, ('project', 'artifact', cursor, cursor, cursor, '32'))]
    assert actual == ['18446744073709551615', '100', '99', '10', '9', '2', '1'], actual
    actual = [row[0] for row in connection.execute(query, ('project', 'artifact', '100', '100', '100', '2'))]
    assert actual == ['99', '10'], actual
    connection.commit()
    connection.execute("CREATE TRIGGER fail_artifact BEFORE INSERT ON artifact_revisions BEGIN SELECT RAISE(ABORT,'synthetic'); END")
    connection.commit()
    try:
        connection.execute('BEGIN IMMEDIATE')
        connection.execute("UPDATE artifact_heads SET revision='3'")
        connection.execute("INSERT INTO artifact_revisions VALUES('project','artifact','3','{}')")
        raise AssertionError('trigger did not reject write')
    except sqlite3.IntegrityError:
        connection.rollback()
    assert connection.execute('SELECT revision FROM artifact_heads').fetchone()[0] == '1'
print(json.dumps({
    'schema_sql_roundtrip': 'PASS',
    'u64_order_and_exclusive_cursor': 'PASS',
    'trigger_rollback_sql': 'PASS',
    'rust_compilation_and_behavior': 'NOT_RUN: cargo/rustc absent',
}, sort_keys=True))
