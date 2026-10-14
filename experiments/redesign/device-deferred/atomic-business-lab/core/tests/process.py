"""Real CLI processes and independent physical SQLite observations; no mock store."""
import hashlib, json, os, pathlib, select, signal, sqlite3, subprocess, tempfile, time, unittest
CORE = pathlib.Path(__file__).resolve().parents[1]
BIN = pathlib.Path(os.environ.get('RD_P07_BIN', str(CORE/'target/debug/rd-p07-atomic')))
SCHEMA = '''
PRAGMA application_id=1380208695;
PRAGMA user_version=1;
CREATE TABLE meta(domain TEXT PRIMARY KEY, format TEXT NOT NULL);
CREATE TABLE suppliers(id TEXT PRIMARY KEY, scope TEXT NOT NULL, name TEXT NOT NULL, revision TEXT NOT NULL, untouched TEXT NOT NULL);
CREATE TABLE intents(intent TEXT PRIMARY KEY, binding TEXT NOT NULL, status TEXT NOT NULL, rejection TEXT);
CREATE TABLE history(intent TEXT PRIMARY KEY, supplier TEXT NOT NULL, old_name TEXT NOT NULL, new_name TEXT NOT NULL, old_revision TEXT NOT NULL, new_revision TEXT NOT NULL, binding TEXT NOT NULL);
CREATE TABLE receipts(intent TEXT PRIMARY KEY, body TEXT NOT NULL);
INSERT INTO meta VALUES('synthetic-A','rd-p07-local-v1');
INSERT INTO suppliers VALUES('S1','scope-A','Before','1','keep-one');
INSERT INTO suppliers VALUES('S2','scope-A','Before','1','keep-two');
'''
def request(op='commit', **kw):
    r=dict(op=op, domain='synthetic-A', scope='scope-A', supplier='S1', intent='I1', operation='supplier.name', raw_utf16=raw(' After '), expected_revision='1', plan='P1', candidate='C1')
    r.update(kw)
    if op in ('read', 'init'): return {k:r[k] for k in ('op','domain','scope','supplier')}
    return r

def raw(s): return [int.from_bytes(s.encode('utf-16-le')[i:i+2],'little') for i in range(0,len(s.encode('utf-16-le')),2)]
class Process(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='rd-p07-private-'); self.db=pathlib.Path(self.temp.name)/'fixture.sqlite'
        with sqlite3.connect(self.db) as c: c.executescript(SCHEMA)
    def tearDown(self): self.temp.cleanup()
    def invoke(self, r=None, fault=None, db=None):
        args=[str(BIN),'--db',str(db or self.db),'--request',json.dumps(r or request())]
        if fault: args += ['--fault', fault]
        p=subprocess.run(args,capture_output=True,text=True,timeout=15)
        evidence=os.environ.get('RD_P07_SQL_EVIDENCE')
        if evidence:
            with open(evidence+'.process.jsonl','a') as f: f.write(json.dumps(dict(test=self.id(),args=args,returncode=p.returncode,stdout=p.stdout,stderr=p.stderr),ensure_ascii=True)+'\n')
        return p
    def call(self, r=None, **kw):
        p=self.invoke(r,**kw); self.assertEqual(p.returncode,0,p.stderr); return json.loads(p.stdout)
    def rows(self, sql, args=()):
        with sqlite3.connect(self.db) as c: rows=c.execute(sql,args).fetchall()
        evidence=os.environ.get('RD_P07_SQL_EVIDENCE')
        if evidence:
            with open(evidence,'a') as f: f.write(json.dumps(dict(test=self.id(),db=str(self.db),sql=sql,args=args,rows=rows),ensure_ascii=True)+'\n')
        return rows
    def state(self):
        return {t:self.rows('SELECT * FROM '+t+' ORDER BY 1') for t in ('meta','suppliers','intents','history','receipts')}
    def assert_effects(self, count, revision, name):
        self.assertEqual(self.rows('SELECT name,revision,untouched FROM suppliers WHERE id="S1"'),[(name,revision,'keep-one')])
        self.assertEqual(self.rows('SELECT * FROM suppliers WHERE id="S2"'),[('S2','scope-A','Before','1','keep-two')])
        self.assertEqual(self.rows('SELECT count(*) FROM history'),[(count,)])
        self.assertEqual(self.rows('SELECT count(*) FROM receipts'),[(count,)])
        self.assertEqual(self.rows('SELECT count(*) FROM intents WHERE status="committed"'),[(count,)])
    def test_atomic_commit(self):
        out=self.call(); self.assert_effects(1,'2','After'); self.assertEqual(out['status'],'committed')
        binding=json.loads(self.rows('SELECT binding FROM intents')[0][0]); self.assertEqual(binding, {k:v for k,v in request().items() if k!='op'})
        receipt=json.loads(self.rows('SELECT body FROM receipts')[0][0]); self.assertEqual(out['receipt'],receipt)
        h=self.rows('SELECT supplier,old_name,new_name,old_revision,new_revision,binding FROM history')[0]
        self.assertEqual(h[:5],('S1','Before','After','1','2')); self.assertEqual(receipt['binding'],binding); self.assertEqual(receipt['source'],'synthetic-A')
        canonical=json.dumps(binding,ensure_ascii=False,separators=(',',':')); self.assertEqual(receipt['binding_sha256'],hashlib.sha256(canonical.encode()).hexdigest())
    def test_replay_before_stale_cas_and_current_separate(self):
        first=self.call(); self.call(request(intent='I2',expected_revision='2',raw_utf16=raw('Later')))
        state=self.state(); self.assertEqual(self.call()['receipt'],first['receipt']); self.assertEqual(self.state(),state)
        self.assertEqual(self.call(request('lookup'))['receipt'],first['receipt']); self.assert_effects(2,'3','Later')
        self.assertEqual(self.call(request('read'))['supplier']['revision'],'3')
    def test_full_binding_conflicts(self):
        self.call(); state=self.state()
        changes=dict(domain='synthetic-B',scope='scope-B',supplier='S2',operation='other',raw_utf16=raw('After'),expected_revision='2',plan='P2',candidate='C2')
        for field,value in changes.items():
            with self.subTest(field=field):
                self.assertEqual(self.call(request(**{field:value}))['status'],'conflict'); self.assertEqual(self.state(),state)
                self.assertEqual(self.call(request('lookup',**{field:value}))['status'],'conflict'); self.assertEqual(self.state(),state)
    def test_same_name_new_intent(self):
        self.call(); r=request(intent='I2',expected_revision='2',raw_utf16=raw(' After ')); second=self.call(r)
        self.assert_effects(2,'3','After'); self.assertNotEqual(second['receipt']['intent'],'I1'); state=self.state(); self.call(r); self.assertEqual(self.state(),state)
    def test_cas_rejection(self):
        out=self.call(request(expected_revision='2')); self.assertEqual(out['status'],'rejected'); self.assert_effects(0,'1','Before')
        self.assertEqual(self.rows('SELECT status,rejection FROM intents'),[('rejected','Revision')]); state=self.state(); self.call(request(expected_revision='2')); self.assertEqual(self.state(),state)
    def test_normalization_and_validation(self):
        vectors=[(raw(' e\u0301 '),'é'),(raw('😀'*200),'😀'*200),([0xd800],None),(raw('\vAfter'),None),(raw('\fAfter'),None),(raw(' '*2001+'A'),None),(raw('😀'*201),None),([],None)]
        for i,(value,expected) in enumerate(vectors):
            with self.subTest(i=i):
                out=self.call(request('preview',raw_utf16=value)); self.assertEqual(out['status'],'preview' if expected else 'rejected')
                if expected: self.assertEqual(out['normalized_name'],expected)
        self.assert_effects(0,'1','Before'); self.assertEqual(self.rows('SELECT * FROM intents'),[])
        self.call(request(raw_utf16=raw(' e\u0301 '))); self.assert_effects(1,'2','é')
    def test_revision_text_boundaries(self):
        for value in ('9007199254740993','18446744073709551614'):
            with self.subTest(value=value):
                with sqlite3.connect(self.db) as c: c.execute('UPDATE suppliers SET revision=? WHERE id="S1"',(value,))
                self.call(request(intent=value,expected_revision=value)); self.assertEqual(self.rows('SELECT revision,typeof(revision) FROM suppliers WHERE id="S1"'),[(str(int(value)+1),'text')])
        self.assertEqual(self.call(request(intent='max',expected_revision='18446744073709551615'))['status'],'rejected')
        for value in ('01','0','18446744073709551616','1.0','-1'):
            self.assertNotEqual(self.invoke(request(expected_revision=value)).returncode,0)
    def test_readonly_and_missing_incompatible(self):
        before=self.state()
        for op in ('read','preview','lookup'): self.call(request(op))
        self.assertEqual(self.state(),before)
        missing=pathlib.Path(self.temp.name)/'missing.sqlite'
        for op in ('read','preview','lookup','commit'):
            self.assertNotEqual(self.invoke(request(op),db=missing).returncode,0); self.assertFalse(missing.exists())
        for mode in ('corrupt','foreign','malformed'):
            bad=pathlib.Path(self.temp.name)/(mode+'.sqlite')
            if mode=='corrupt': bad.write_bytes(b'not sqlite')
            else:
                with sqlite3.connect(bad) as c:
                    if mode=='foreign': c.execute('CREATE TABLE unrelated(x)')
                    else: c.executescript(SCHEMA); c.execute('UPDATE suppliers SET revision="01"')
            before=bad.read_bytes()
            for op in ('read','preview','lookup','commit'): self.assertNotEqual(self.invoke(request(op),db=bad).returncode,0)
            self.assertEqual(bad.read_bytes(),before)
    def test_strict_requests(self):
        state=self.state()
        for changed in (dict(extra=True),dict(expected_revision=1),dict(raw_utf16='After'),dict(raw_utf16=[65536]),dict(op='unknown')):
            self.assertNotEqual(self.invoke(request(**changed)).returncode,0)
        self.assertEqual(self.state(),state)
    def test_pending_binding_and_absent_receipt(self):
        p=self.invoke(fault='exit:pending'); self.assertEqual(p.returncode,86)
        state=self.state()
        for field,value in dict(domain='B',scope='B',supplier='S2',operation='other',raw_utf16=raw('After'),expected_revision='2',plan='P2',candidate='C2').items():
            with self.subTest(field=field):
                self.assertEqual(self.call(request(**{field:value}))['status'],'conflict'); self.assertEqual(self.state(),state)
        self.assertEqual(self.call(request('lookup',intent='absent'))['status'],'unknown'); self.assertEqual(self.state(),state)
    def test_guarded_affected_rows(self):
        with sqlite3.connect(self.db) as c: c.execute("CREATE TRIGGER skip_update BEFORE UPDATE ON suppliers BEGIN SELECT RAISE(IGNORE); END")
        p=self.invoke(); self.assertNotEqual(p.returncode,0); self.assertIn('affected row mismatch',p.stderr)
        self.assert_effects(0,'1','Before'); self.assertEqual(self.rows('SELECT status FROM intents'),[('pending',)])
    def test_schema_constraints_fail_closed(self):
        with sqlite3.connect(self.db) as c:
            c.execute('DROP TABLE receipts'); c.execute('CREATE TABLE receipts(intent TEXT, body TEXT NOT NULL)')
        state=self.state()
        for op in ('read','preview','lookup','commit'):
            p=self.invoke(request(op)); self.assertNotEqual(p.returncode,0); self.assertIn('incompatible',p.stderr); self.assertEqual(self.state(),state)
    def test_actual_effect_verification(self):
        with sqlite3.connect(self.db) as c: c.execute("CREATE TRIGGER alter_name AFTER UPDATE ON suppliers BEGIN UPDATE suppliers SET name='unexpected' WHERE id=NEW.id; END")
        p=self.invoke(); self.assertNotEqual(p.returncode,0); self.assertIn('actual effect mismatch',p.stderr)
        self.assert_effects(0,'1','Before'); self.assertEqual(self.rows('SELECT status FROM intents'),[('pending',)])
    def test_tail_trigger_consistency(self):
        triggers=[
            "CREATE TRIGGER tail AFTER INSERT ON history BEGIN UPDATE suppliers SET name='late' WHERE id='S1'; END",
            "CREATE TRIGGER tail AFTER INSERT ON receipts BEGIN UPDATE suppliers SET revision='3' WHERE id='S1'; END",
            "CREATE TRIGGER tail AFTER INSERT ON receipts BEGIN UPDATE receipts SET body='{}' WHERE intent=NEW.intent; END",
            "CREATE TRIGGER tail AFTER INSERT ON receipts BEGIN UPDATE intents SET status='pending' WHERE intent=NEW.intent; END",
        ]
        for i,trigger in enumerate(triggers):
            with self.subTest(i=i):
                db=pathlib.Path(self.temp.name)/('tail-'+str(i)+'.sqlite')
                with sqlite3.connect(db) as c: c.executescript(SCHEMA); c.execute(trigger)
                previous=self.db; self.db=db
                try:
                    p=self.invoke(); self.assertNotEqual(p.returncode,0); self.assertIn('final consistency',p.stderr)
                    self.assert_effects(0,'1','Before'); self.assertEqual(self.rows('SELECT status FROM intents'),[('pending',)])
                    state=self.state(); self.assertEqual(self.call()['status'],'unknown'); self.assertEqual(self.state(),state)
                finally: self.db=previous
    def test_receipt_tampering(self):
        self.call()
        with sqlite3.connect(self.db) as c: c.execute("UPDATE receipts SET body='{}'")
        state=self.state()
        for op in ('lookup','commit'):
            p=self.invoke(request(op)); self.assertNotEqual(p.returncode,0); self.assertIn('receipt mismatch',p.stderr); self.assertEqual(self.state(),state)
    def test_committed_missing_receipt_unknown(self):
        self.call()
        with sqlite3.connect(self.db) as c: c.execute('DELETE FROM receipts')
        state=self.state()
        for op in ('lookup','commit'): self.assertEqual(self.call(request(op))['status'],'unknown'); self.assertEqual(self.state(),state)
    def test_readonly_hot_journal_unavailable(self):
        p=subprocess.Popen([str(BIN),'--db',str(self.db),'--request',json.dumps(request()),'--fault','barrier:update'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        self.wait_barrier(p)
        p.kill(); p.communicate(timeout=5)
        # Make a genuine hot rollback journal deterministically: many dirty pages force
        # cache spill before kill. SQLite must recover it, which READONLY cannot do.
        writer="""import sqlite3,sys,time
c=sqlite3.connect(sys.argv[1]);c.execute('PRAGMA cache_size=1');c.execute('BEGIN IMMEDIATE')
for i in range(500): c.execute('INSERT INTO suppliers VALUES(?,?,?,?,?)',(str(i),'scope-A','x'*1000,'1','untouched'))
print('dirty',flush=True);time.sleep(30)
"""
        q=subprocess.Popen(['python3','-c',writer,str(self.db)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        self.assertEqual(q.stdout.readline().strip(),'dirty'); q.kill(); q.communicate(timeout=5)
        journal=pathlib.Path(str(self.db)+'-journal'); self.assertTrue(journal.exists()); before=journal.read_bytes(); database=self.db.read_bytes()
        for op in ('read','preview','lookup'):
            p=self.invoke(request(op)); self.assertNotEqual(p.returncode,0); self.assertIn('readonly',p.stderr.lower())
        self.assertEqual(journal.read_bytes(),before); self.assertEqual(self.db.read_bytes(),database)
    def test_duplicate_json_keys(self):
        text=json.dumps(request()); text=text.replace('"op": "commit"','"op": "read", "op": "commit"')
        p=subprocess.run([str(BIN),'--db',str(self.db),'--request',text],capture_output=True,text=True,timeout=5)
        self.assertNotEqual(p.returncode,0); self.assertIn('duplicate key',p.stderr); self.assert_effects(0,'1','Before')
    def test_explicit_init(self):
        path=pathlib.Path(self.temp.name)/'init.sqlite'; self.assertEqual(self.call(request('init'),db=path)['status'],'initialized')
        with sqlite3.connect(path) as c: self.assertEqual(c.execute('SELECT count(*) FROM suppliers').fetchone(),(2,))
        before=path.read_bytes(); self.assertNotEqual(self.invoke(request('init'),db=path).returncode,0); self.assertEqual(path.read_bytes(),before)
    def test_sql_exit_faults(self):
        for i,stage in enumerate(('pending','update','history','intent','receipt','commit')):
            with self.subTest(stage=stage):
                r=request(intent='exit-'+stage); p=self.invoke(r,fault='exit:'+stage); self.assertEqual(p.returncode,86)
                if stage=='commit':
                    self.assert_effects(1,'2','After'); self.assertEqual(self.call(r)['status'],'committed')
                else:
                    self.assert_effects(0,'1','Before'); self.assertEqual(self.rows('SELECT status FROM intents WHERE intent=?',(r['intent'],)),[('pending',)])
                    state=self.state(); self.assertEqual(self.call(r)['status'],'unknown'); self.assertEqual(self.call(dict(r,op='lookup'))['status'],'unknown'); self.assertEqual(self.state(),state)
    def test_receipt_insert_failure(self):
        with sqlite3.connect(self.db) as c: c.execute("CREATE TRIGGER fail_receipt BEFORE INSERT ON receipts BEGIN SELECT RAISE(ABORT,'real receipt failure'); END")
        p=self.invoke(); self.assertNotEqual(p.returncode,0); self.assertIn('real receipt failure',p.stderr); self.assert_effects(0,'1','Before')
        self.assertEqual(self.rows('SELECT status FROM intents'),[('pending',)]); state=self.state(); self.assertEqual(self.call()['status'],'unknown'); self.assertEqual(self.state(),state)
    def wait_barrier(self,p):
        end=time.monotonic()+10
        while time.monotonic()<end:
            if not select.select([p.stdout],[],[],max(0,end-time.monotonic()))[0]: self.fail('barrier timeout')
            line=p.stdout.readline()
            if line.startswith('BARRIER '): return
            if p.poll() is not None: self.fail('process exited before barrier '+p.stderr.read())
        self.fail('barrier timeout')
    def test_sigkill_barriers(self):
        for stage in ('pending','update','history','intent','receipt','commit'):
            with self.subTest(stage=stage):
                # Each SIGKILL case gets an independent database, avoiding prior outcomes.
                db=pathlib.Path(self.temp.name)/('kill-'+stage+'.sqlite')
                with sqlite3.connect(db) as c: c.executescript(SCHEMA)
                original=self.db; self.db=db
                try:
                    p=subprocess.Popen([str(BIN),'--db',str(db),'--request',json.dumps(request()),'--fault','barrier:'+stage],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
                    self.wait_barrier(p); p.kill(); p.communicate(timeout=5); self.assertEqual(p.returncode,-signal.SIGKILL)
                    self.assert_effects(1 if stage=='commit' else 0,'2' if stage=='commit' else '1','After' if stage=='commit' else 'Before')
                    state=self.state(); self.assertEqual(self.call()['status'],'committed' if stage=='commit' else 'unknown'); self.assertEqual(self.state(),state)
                finally: self.db=original
    def test_concurrent_duplicate(self):
        p=subprocess.Popen([str(BIN),'--db',str(self.db),'--request',json.dumps(request()),'--fault','barrier:pending'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        self.wait_barrier(p)
        try:
            self.assertEqual(self.call()['status'],'unknown'); self.assert_effects(0,'1','Before')
        finally: p.kill(); p.communicate(timeout=5)
        self.assertEqual(self.call()['status'],'unknown'); self.assert_effects(0,'1','Before')
        fresh=request(intent='fresh'); args=[str(BIN),'--db',str(self.db),'--request',json.dumps(fresh)]
        ps=[subprocess.Popen(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True) for _ in range(8)]
        statuses=[]
        for q in ps:
            out,err=q.communicate(timeout=15); self.assertEqual(q.returncode,0,err); statuses.append(json.loads(out)['status'])
        self.assertIn('committed',statuses); self.assertTrue(set(statuses)<={'committed','unknown'}); self.assert_effects(1,'2','After')
    def test_concurrent_cas(self):
        ps=[subprocess.Popen([str(BIN),'--db',str(self.db),'--request',json.dumps(request(intent='race-'+str(i),raw_utf16=raw('name-'+str(i))))],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True) for i in range(8)]
        statuses=[]
        for p in ps:
            out,err=p.communicate(timeout=15); self.assertEqual(p.returncode,0,err); statuses.append(json.loads(out)['status'])
        self.assertEqual(statuses.count('committed'),1); self.assertEqual(statuses.count('rejected'),7)
        self.assertEqual(self.rows('SELECT count(*) FROM history'),[(1,)]); self.assertEqual(self.rows('SELECT count(*) FROM receipts'),[(1,)])
        self.assertEqual(self.rows('SELECT revision FROM suppliers WHERE id="S1"'),[('2',)])
if __name__=='__main__': unittest.main(verbosity=2)
