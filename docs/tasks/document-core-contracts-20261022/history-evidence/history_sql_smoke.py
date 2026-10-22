"""Actual source historical-policy DDL/SQL smoke; does not run Rust authorization."""
import json
from pathlib import Path
import re
import sqlite3
import tempfile

root = Path(__file__).resolve().parents[4]
source = (root / "crates/muyon-core/src/documents/storage.rs").read_text()
parent = re.search(r'"(CREATE TABLE document_grants\([^"\n]+)"', source).group(1)
history = re.search(r'const HISTORY_SCHEMA: &str = "([^"\n]+)";', source).group(1)
strings = [json.loads('"' + value + '"') for value in re.findall(r'"((?:[^"\\]|\\.)*)"', source)]
queries = list(dict.fromkeys(value for value in strings if "document_history_grants_v1" in value and value.startswith(("SELECT ", "INSERT ", "UPDATE "))))
insert = next(value for value in queries if value.startswith("INSERT "))
select = next(value for value in queries if "FROM document_history_grants_v1 WHERE" in value)
revoke = next(value for value in queries if value.startswith("UPDATE "))
current = '{"scope":{"workspace_id":"workspace","project_id":"project"},"document_id":"d","revision":"2","format":"pdf"}'
historical = current.replace('"revision":"2"', '"revision":"1"')
with tempfile.TemporaryDirectory(prefix="muyon-history-policy-sql-") as directory:
    path = Path(directory) / "original-synthetic.sqlite"
    db = sqlite3.connect(path)
    db.execute("PRAGMA foreign_keys=ON")
    db.execute(parent)
    db.execute(history)
    for query in queries:
        db.execute("EXPLAIN " + query, [None] * query.count("?"))
    db.execute("INSERT INTO document_grants VALUES(?,?,?,?,?,?,1)", ("g", "2", "epoch", current, '["read_text"]', "9999999999999"))
    db.execute(insert, ("g", "2", "epoch", current, historical, '["read_text"]', "9999999999999"))
    db.commit()
    db.close()
    db = sqlite3.connect(path)
    assert db.execute(select, ("g", "2", "epoch", historical)).fetchone()[0] == current
    assert not db.execute(select, ("g", "3", "epoch", historical)).fetchall()
    assert not db.execute(select, ("g", "2", "epoch", current)).fetchall()
    db.execute("UPDATE document_history_grants_v1 SET current_document_json=?", ("x" * 9000,))
    assert db.execute(select, ("g", "2", "epoch", historical)).fetchone()[0] is None
    db.rollback()
    db.execute(revoke, ("g", "2", "epoch", current, historical))
    assert not db.execute(select, ("g", "2", "epoch", historical)).fetchall()
    assert not db.execute("PRAGMA foreign_key_check").fetchall()
    print("PASS: exact source DDL and", len(queries), "historical-policy SQL statements prepare")
    print("PASS: explicit synthetic policy survives reopen and exact target/generation select")
    print("PASS: oversized projected JSON returns NULL; revoked policy excluded; FK check empty")
    print("LIMIT: Rust authority/head/expiry/metadata logic and byte delivery NOT_RUN here")
    print("SQLite:", sqlite3.sqlite_version)
    db.close()
