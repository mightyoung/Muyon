"""Execute exact source SQL with synthetic rows. This DOES NOT execute Rust APIs.

Supplemental SQL/schema/round-trip check while the author's Rust toolchain is
absent; it cannot replace the required document_storage Rust integration test.
No third-party document engine or user file is opened.
"""
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import tempfile

ROOT = Path(__file__).resolve().parents[4]
SOURCE = ROOT / "crates/muyon-core/src/documents/storage.rs"
raw = SOURCE.read_text()
business = (ROOT / "crates/muyon-core/src/business.rs").read_text()
base_schema = re.findall(r'^    "(CREATE TABLE .+)",$', business, re.M)
schema = re.findall(r'^    \("[^"]+", "(CREATE TABLE .+)"\),$', raw, re.M)
assert len(base_schema) >= 10 and len(schema) == 6
statements = list(dict.fromkeys(
    json.loads('"' + text + '"')
    for text in re.findall(r'"((?:[^"\\]|\\.)*)"', raw)
    if text.startswith(("SELECT ", "INSERT ", "UPDATE "))
))


def statement(prefix):
    found = [s for s in statements if s.startswith(prefix)]
    assert len(found) == 1, (prefix, found)
    return found[0]


with tempfile.TemporaryDirectory(prefix="muyon-document-source-sql-") as directory:
    path = Path(directory) / "synthetic.sqlite"
    db = sqlite3.connect(path, isolation_level=None)
    db.execute("PRAGMA foreign_keys=ON")
    db.execute("BEGIN IMMEDIATE")
    for ddl in base_schema + schema:
        db.execute(ddl)
    for query in statements:
        # Compile all SQL and verify parameter arity/table/column names. EXPLAIN
        # prepares the statement without executing its data modification.
        db.execute("EXPLAIN " + query, [None] * query.count("?"))
    db.execute("INSERT INTO projects VALUES(?,?,?,'1',0)", ("project", "workspace", "synthetic"))
    db.execute(statement("INSERT INTO document_store_meta VALUES('version'"))
    db.execute(statement("INSERT INTO document_store_meta VALUES('workspace'"), ("workspace",))
    document = {"scope": {"workspace_id": "workspace", "project_id": "project"},
                "document_id": "document", "revision": "1", "format": "pdf"}
    metadata = {"document": document, "title": "Original synthetic metadata",
                "blob": {"digest": "a" * 64, "byte_length": "10"}}
    db.execute(statement("INSERT INTO document_heads VALUES"), ("project", "document", "1"))
    db.execute(statement("INSERT INTO document_revisions VALUES"), ("project", "document", "1", json.dumps(metadata)))
    db.execute(statement("INSERT INTO document_grants VALUES"),
               ("grant", "1", "epoch", json.dumps(document), '["read_text","annotate","export"]', "9999999999999"))
    row = {"id": "annotation", "revision": "1", "body": {"kind": "comment", "text": "Synthetic note"},
           "created_by": {"kind": "human", "actor_id": "author"},
           "modified_by": {"kind": "human", "actor_id": "author"}, "deleted": False,
           "anchor_state": "current", "anchor": {"document": document,
           "location": {"pdf": {"page_index_zero_based": 0,
           "coordinates": "pdf_user_space", "rotation": "degrees0",
           "crop": {"x": 0.0, "y": 0.0, "width": 600.0, "height": 800.0},
           "region": {"x": 1.0, "y": 2.0, "width": 10.0, "height": 20.0}}}}}
    for prefix in ["INSERT INTO document_annotation_history VALUES", "INSERT INTO document_annotations VALUES"]:
        db.execute(statement(prefix), ("project", "document", "annotation", "1", json.dumps(row)))
    db.execute("COMMIT")
    db.close()

    db = sqlite3.connect(path, isolation_level=None)
    db.execute("PRAGMA foreign_keys=ON")
    restored = db.execute(statement("SELECT CASE WHEN length(CAST(h.revision AS BLOB))"), ("project", "document")).fetchone()
    assert restored[:2] == ("1", "1")
    assert json.loads(restored[2]) == metadata
    rows = db.execute(statement("SELECT annotation_id,revision,CASE"), ("project", "document")).fetchall()
    assert json.loads(rows[0][2]) == row
    print("PASS: exact source schema and", len(statements), "SQL statements prepare")
    print("PASS: committed synthetic metadata/annotation rows survive reopen")

    db.execute("BEGIN IMMEDIATE")
    db.execute("UPDATE document_revisions SET payload=?", ("x" * 10000,))
    bounded = db.execute(statement("SELECT CASE WHEN length(CAST(h.revision AS BLOB))"), ("project", "document")).fetchone()
    assert bounded[2] is None
    db.execute("ROLLBACK")
    print("PASS: SQL excludes oversized metadata payload before returning TEXT")

    db.execute("BEGIN IMMEDIATE")
    changed = db.execute(statement("UPDATE document_heads SET revision="), ("2", "project", "document", "0")).rowcount
    assert changed == 0
    db.execute("ROLLBACK")
    assert db.execute("SELECT revision FROM document_heads").fetchone()[0] == "1"
    print("PASS: stale document-head CAS changes zero rows")

    db.execute("BEGIN IMMEDIATE")
    row.update(revision="2", deleted=True, modified_by={"kind": "ai", "agent_id": "agent", "run_id": "run"})
    for prefix in ["INSERT INTO document_annotation_history VALUES", "INSERT INTO document_annotations VALUES"]:
        db.execute(statement(prefix), ("project", "document", "annotation", "2", json.dumps(row)))
    db.execute(statement("UPDATE document_grants SET active=0"), ("grant", "1", "epoch"))
    db.execute("COMMIT")
    assert db.execute(statement("SELECT CASE WHEN length(CAST(document_json AS BLOB))"), ("grant", "1", "epoch")).fetchall() == []
    assert db.execute("SELECT COUNT(*) FROM document_annotation_history").fetchone()[0] == 2
    stored = json.loads(db.execute("SELECT payload FROM document_annotations").fetchone()[0])
    assert stored["deleted"] and stored["created_by"]["kind"] == "human" and stored["modified_by"]["kind"] == "ai"
    print("PASS: source SQL retains history/tombstone/provenance and excludes revoked grant")

    before = db.execute("SELECT COUNT(*) FROM document_heads").fetchone()[0]
    db.execute("BEGIN IMMEDIATE")
    db.execute(statement("INSERT INTO document_heads VALUES"), ("project", "rolled-back", "1"))
    db.execute("ROLLBACK")
    assert db.execute("SELECT COUNT(*) FROM document_heads").fetchone()[0] == before
    assert db.execute("PRAGMA foreign_key_check").fetchall() == []
    print("PASS: rollback preserves previous rows; foreign_key_check empty")
    print("SQLite:", sqlite3.sqlite_version)
    print("Rust SQL source SHA256:", hashlib.sha256(SOURCE.read_bytes()).hexdigest())
    print("LIMIT: Rust compilation, authorization/body/anchor validation and actual blob publication NOT_RUN by this script")
    db.close()
