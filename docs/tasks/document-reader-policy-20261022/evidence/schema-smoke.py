"""SQLite DDL/trigger smoke only; NEVER a Rust policy or grant acceptance test."""
import json,re,sqlite3
from pathlib import Path
repo=Path(__file__).resolve().parents[4]
source=(repo/'crates/muyon-core/src/documents/reading_policy/store.rs').read_text()
def literal(name):
 return json.loads(re.search(r'const '+name+r': &str = ("(?:[^"\\]|\\.)*");',source).group(1))
db=sqlite3.connect(':memory:')
for ddl in [
 "CREATE TABLE projects(id TEXT PRIMARY KEY,workspace TEXT,name TEXT,revision TEXT,deleted INTEGER)",
 "CREATE TABLE document_grants(grant_id TEXT PRIMARY KEY,generation TEXT,owner_epoch TEXT,document_json TEXT,permissions TEXT,expires_at_ms TEXT,active INTEGER)",
 "CREATE TABLE document_heads(project_id TEXT,document_id TEXT,revision TEXT)",
 "CREATE TABLE document_revisions(project_id TEXT,document_id TEXT,revision TEXT,payload TEXT)",
 "CREATE TABLE blobs(digest TEXT PRIMARY KEY,byte_length TEXT,state TEXT)",
 literal('ROOT_DDL'),literal('ATTEMPT_DDL')]:db.execute(ddl)
triggers=re.findall(r'\("document_reading_policy_[^"]+", ("(?:[^"\\]|\\.)*")\)',source)
assert len(triggers)==11
for text in triggers:db.execute(json.loads(text))
db.execute("INSERT INTO document_grants VALUES('parent','1','epoch','{}','[]','0',1)")
db.execute("INSERT INTO document_grants VALUES('child','1','epoch','{}','[]','0',1)")
db.execute("INSERT INTO document_reading_policy_roots_v1 VALUES('r','instance','epoch','scope','p','d','1','digest','parent','1','child','1',0,0,'{}')")
db.execute("UPDATE document_grants SET active=0 WHERE grant_id='parent'")
assert db.execute("SELECT terminal FROM document_reading_policy_roots_v1").fetchone()==(1,)
assert db.execute("SELECT active FROM document_grants WHERE grant_id='child'").fetchone()==(0,)
try:db.execute("UPDATE document_reading_policy_roots_v1 SET terminal=0")
except sqlite3.IntegrityError:pass
else:raise AssertionError('terminal unfence accepted')
print('PASS: actual root/attempt DDL +11 trigger SQL statements execute; parent fence cascades child; unfence denied. SQL-only, no Rust or production admission claim.')
