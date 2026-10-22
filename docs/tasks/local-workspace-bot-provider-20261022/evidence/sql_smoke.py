#!/usr/bin/env python3
"""Execute actual provider DDL/DML on synthetic SQLite; NOT Rust/FFI acceptance."""
import hashlib
import json
import pathlib
import re
import sqlite3
import struct
import tempfile
import uuid

repo = pathlib.Path(__file__).resolve().parents[4]
source = (repo / 'crates/muyon-core/src/bot_drafts.rs').read_text()
sqls = re.findall(r'"((?:SELECT|UPDATE|INSERT|CREATE TABLE)[^"\n]+)"', source)
ddls = [s for s in sqls if s.startswith('CREATE TABLE')]
assert len(ddls) == 3

def sql(prefix):
    found = list(dict.fromkeys(s for s in sqls if s.startswith(prefix)))
    assert len(found) == 1, (prefix, found)
    return found[0]

def run():
    with tempfile.TemporaryDirectory(prefix='muyon-bot-synthetic-') as temp:
        path = str(pathlib.Path(temp) / 'business.sqlite')
        db = sqlite3.connect(path, isolation_level=None)
        db.execute('PRAGMA foreign_keys=ON')
        db.execute('PRAGMA journal_mode=WAL')
        db.execute('PRAGMA synchronous=FULL')
        # Existing BusinessStore transaction host + unrelated original ledgers.
        db.execute('CREATE TABLE projects(id TEXT PRIMARY KEY,deleted INTEGER)')
        db.execute('CREATE TABLE intents(id TEXT PRIMARY KEY,status TEXT)')
        db.executemany('INSERT INTO intents VALUES(?,?)', [('old-a','unknown'),('old-b','unknown'),('reserved','pending')])
        before = db.execute('SELECT * FROM intents ORDER BY id').fetchall()
        db.execute('BEGIN IMMEDIATE')
        for ddl in ddls: db.execute(ddl)
        ns, draft, attempt = (str(uuid.uuid4()) for _ in range(3))
        conversation = str(uuid.uuid4())
        key = json.dumps(['workspace', conversation, None], separators=(',', ':'))
        db.execute(sql('INSERT INTO local_bot_draft_meta'), ('workspace', ns))
        insert_none = next(s for s in sqls if s.startswith('INSERT INTO local_bot_drafts VALUES') and "NULL,'1'" in s)
        db.execute(insert_none, (draft,key,'workspace',conversation))
        db.commit()
        assert db.execute('SELECT stored_revision,archive_hex,lifecycle FROM local_bot_drafts').fetchone() == ('0',None,'editing_only')
        print('PASS actual DDL + initial NULL archive + registry fact')
        # Every production SQL statement parses against actual schema (no duplicated SQL).
        for statement in dict.fromkeys(sqls):
            if statement.startswith('CREATE TABLE'): continue
            db.execute('EXPLAIN ' + statement, tuple('synthetic' for _ in range(statement.count('?')))).fetchall()
        print('PASS all extracted production SQL parses and parameter counts')
        try:
            db.execute(insert_none, (str(uuid.uuid4()),key,'workspace',conversation))
            raise AssertionError('duplicate scope accepted')
        except sqlite3.IntegrityError: pass
        print('PASS unique structured scope')
        payload = b'MYBD' + struct.pack('>iq',1,1) + bytes(19)
        archive = payload + hashlib.sha256(payload).digest()
        assert len(archive)==67
        archive_hex, digest = archive.hex(), hashlib.sha256(archive).hexdigest()
        update = sql('UPDATE local_bot_drafts SET')
        insert_receipt = sql('INSERT INTO local_bot_draft_saves')
        receipt = json.dumps({'attempt_id':attempt,'stored_revision':'1','exported_memory_revision':'17'})
        args = (attempt,ns,draft,key,'1','0','1','17',digest,receipt)
        db.execute("CREATE TRIGGER fail_receipt BEFORE INSERT ON local_bot_draft_saves BEGIN SELECT RAISE(ABORT,'synthetic'); END")
        db.execute('BEGIN IMMEDIATE')
        assert db.execute(update,('1',archive_hex,digest,draft,'1','0')).rowcount==1
        try:
            db.execute(insert_receipt,args)
            raise AssertionError('fault not injected')
        except sqlite3.IntegrityError: db.rollback()
        assert db.execute('SELECT stored_revision,archive_hex FROM local_bot_drafts').fetchone()==('0',None)
        assert db.execute('SELECT COUNT(*) FROM local_bot_draft_saves').fetchone()[0]==0
        print('PASS injected receipt failure rolls back archive/revision/attempt')
        db.execute('DROP TRIGGER fail_receipt')
        db.execute('BEGIN IMMEDIATE')
        assert db.execute(update,('1',archive_hex,digest,draft,'1','0')).rowcount==1
        db.execute(insert_receipt,args)
        db.commit()
        assert db.execute(update,('1',archive_hex,digest,draft,'1','0')).rowcount==0
        print('PASS save commit + stale editor CAS refuses')
        db.close()
        db = sqlite3.connect(path, isolation_level=None)
        assert db.execute(sql('SELECT namespace_id,draft_id,scope_key'),(attempt,)).fetchone()[-1]==receipt
        assert db.execute('SELECT namespace_id FROM local_bot_draft_meta').fetchone()[0]==ns
        assert db.execute('SELECT draft_id FROM local_bot_drafts').fetchone()[0]==draft
        print('PASS restart stable registry and exact original receipt after callback loss')
        db.execute('BEGIN IMMEDIATE')
        assert db.execute(update,('2',archive_hex,digest,draft,'1','1')).rowcount==1
        db.commit()
        assert db.execute(sql('SELECT namespace_id,draft_id,scope_key'),(attempt,)).fetchone()[-1]==receipt
        print('PASS original receipt is not replaced with latest head')
        db.execute("UPDATE local_bot_drafts SET lifecycle='pending'")
        assert db.execute(update,('3',archive_hex,digest,draft,'1','2')).rowcount==0
        print('PASS SQL CAS also checks editing_only lifecycle')
        db.execute("UPDATE local_bot_drafts SET archive_hex=?", ('0'*65538,))
        row = db.execute(sql('SELECT draft_id,workspace,conversation_id'),(key,)).fetchone()
        assert row[7]=='oversize'
        db.execute("UPDATE local_bot_draft_saves SET receipt_json=?", ('x'*4097,))
        assert db.execute(sql('SELECT namespace_id,draft_id,scope_key'),(attempt,)).fetchone()[-1]=='oversize'
        print('PASS bounded archive and receipt SQL projections')
        assert db.execute('SELECT * FROM intents ORDER BY id').fetchall()==before
        print('PASS two original unknowns and reservation untouched')
        db.close()
    print('NOT_RUN Rust behavior, FFI compilation/bindings, canonical Kotlin roundtrip, Android: absent toolchain/export integration')

if __name__ == '__main__': run()
