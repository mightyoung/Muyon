#!/usr/bin/env python3
"""Source SQL transactional checks only; does NOT execute Rust branch logic/FFI."""
import hashlib
import json
import pathlib
import re
import sqlite3
import tempfile
import uuid

root = pathlib.Path(__file__).resolve().parents[4]
source = (root / 'crates/muyon-core/src/bot_drafts.rs').read_text()
sqls = list(dict.fromkeys(re.findall(r'"((?:SELECT|UPDATE|INSERT|CREATE TABLE)[^"\n]+)"', source)))

def sql(prefix):
    found = [s for s in sqls if s.startswith(prefix)]
    assert len(found) == 1, (prefix, found)
    return found[0]

def run():
    with tempfile.TemporaryDirectory(prefix='muyon-prepare-synthetic-') as temporary:
        path = str(pathlib.Path(temporary) / 'business.sqlite')
        def connect():
            db = sqlite3.connect(path, isolation_level=None)
            db.execute('PRAGMA foreign_keys=ON')
            db.execute('PRAGMA journal_mode=WAL')
            db.execute('PRAGMA synchronous=FULL')
            return db
        db = connect()
        for ddl in (s for s in sqls if s.startswith('CREATE TABLE')):
            db.execute(ddl)
        for statement in sqls:
            if not statement.startswith('CREATE TABLE'):
                db.execute('EXPLAIN ' + statement, tuple('synthetic' for _ in range(statement.count('?')))).fetchall()
        print('PASS every original+journal source SQL statement parses/binds in actual SQLite')
        namespace, draft, conversation, first, second = (str(uuid.uuid4()) for _ in range(5))
        key = json.dumps(['workspace', conversation, None], separators=(',', ':'))
        db.execute(sql('INSERT INTO local_bot_draft_meta'), ('workspace', namespace))
        insert_draft = next(s for s in sqls if s.startswith('INSERT INTO local_bot_drafts VALUES') and "NULL,'1'" in s)
        db.execute(insert_draft, (draft,key,'workspace',conversation))
        def preparation(attempt, state='prepared'):
            return dict(schema=1,owner_kind='local_workspace',namespace_id=namespace,
                workspace_id='workspace',conversation_id=conversation,project_id=None,
                draft_id=draft,registry_generation='1',attempt_id=attempt,
                expected_stored_revision='0',next_stored_revision='1',
                exported_memory_revision='17',host_editor_revision='42',
                archive_digest=hashlib.sha256(b'synthetic-archive').hexdigest(),state=state)
        def encoded(p): return json.dumps(p,separators=(',', ':'))
        def prepare(attempt):
            p = preparation(attempt)
            db.execute('BEGIN IMMEDIATE')
            db.execute(sql('INSERT INTO local_bot_save_attempts_v1'), (attempt,draft,key,'prepared',encoded(p)))
            db.execute(sql('INSERT INTO local_bot_save_pointer_v1'), (draft,attempt))
            db.commit()
            return p
        def transition(p, state):
            next_p = dict(p,state=state)
            changed = db.execute(sql('UPDATE local_bot_save_attempts_v1 SET'),
                (state,encoded(next_p),p['attempt_id'],draft,key)).rowcount
            return changed
        p = prepare(first)
        db.close()
        db = connect()
        pointer_sql = sql('SELECT CASE WHEN typeof(attempt_id)')
        attempt_sql = sql('SELECT CASE WHEN typeof(draft_id)')
        assert db.execute(pointer_sql,(draft,)).fetchone() == (first,)
        assert json.loads(db.execute(attempt_sql,(first,)).fetchone()[-1]) == p
        assert db.execute('SELECT stored_revision,archive_hex FROM local_bot_drafts').fetchone() == ('0',None)
        print('PASS request-before-dispatch preparation pointer and export/editor binding survive actual DB restart; no saved archive')
        db.execute('BEGIN IMMEDIATE')
        assert transition(p,'not_committed') == 1
        db.commit()
        assert transition(p,'committed') == 0
        print('PASS lookup fence is durable: conditional late transition from prepared now changes zero rows')
        p2 = prepare(second)
        update_archive = sql('UPDATE local_bot_drafts SET')
        insert_receipt = sql('INSERT INTO local_bot_draft_saves')
        receipt = encoded(dict(preparation=p2,status='synthetic-test-receipt'))
        receipt_args = (second,namespace,draft,key,'1','0','1','17',p2['archive_digest'],receipt)
        db.execute("CREATE TRIGGER fail_journal_transition BEFORE UPDATE ON local_bot_save_attempts_v1 WHEN NEW.state='committed' BEGIN SELECT RAISE(ABORT,'synthetic'); END")
        db.execute('BEGIN IMMEDIATE')
        assert db.execute(update_archive,('1','00',p2['archive_digest'],draft,'1','0')).rowcount == 1
        db.execute(insert_receipt,receipt_args)
        try:
            transition(p2,'committed')
            raise AssertionError('journal fault not injected')
        except sqlite3.IntegrityError:
            db.rollback()
        assert db.execute('SELECT stored_revision,archive_hex FROM local_bot_drafts').fetchone() == ('0',None)
        assert db.execute('SELECT COUNT(*) FROM local_bot_draft_saves').fetchone() == (0,)
        assert db.execute('SELECT state FROM local_bot_save_attempts_v1 WHERE attempt_id=?',(second,)).fetchone() == ('prepared',)
        print('PASS injected terminal journal failure rolls back archive/CAS/original receipt together, prepared pointer retained')
        db.execute('DROP TRIGGER fail_journal_transition')
        db.execute('BEGIN IMMEDIATE')
        assert db.execute(update_archive,('1','00',p2['archive_digest'],draft,'1','0')).rowcount == 1
        db.execute(insert_receipt,receipt_args)
        assert transition(p2,'committed') == 1
        db.commit()
        db.close()
        db = connect()
        assert db.execute(pointer_sql,(draft,)).fetchone() == (second,)
        assert json.loads(db.execute(attempt_sql,(second,)).fetchone()[-1])['state'] == 'committed'
        assert db.execute('SELECT receipt_json FROM local_bot_draft_saves WHERE attempt_id=?',(second,)).fetchone() == (receipt,)
        assert json.loads(db.execute(attempt_sql,(first,)).fetchone()[-1])['state'] == 'not_committed'
        print('PASS committed exact original/export/editor and prior terminal history survive restart without timestamp search')
        for corrupt in ['x'*4097, b'{}', '中'*1366]:
            db.execute('UPDATE local_bot_save_attempts_v1 SET payload=? WHERE attempt_id=?',(corrupt,second))
            assert db.execute(attempt_sql,(second,)).fetchone()[-1] is None
        print('PASS journal payload SQL type and byte budget guards reject oversized/BLOB/multibyte corrupt storage')
        db.close()
    print('NOT_RUN Rust state-machine/serialization/FFI/Kotlin/Android: SQL-only diagnostics are not provider acceptance')

if __name__ == '__main__': run()
