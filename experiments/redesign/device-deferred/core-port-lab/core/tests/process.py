#!/usr/bin/env python3
"""Actual Rust process tests: synthetic facts, no scripted replies or oracle tables."""
import json, os, pathlib, subprocess, sys, unittest
CORE=pathlib.Path(__file__).resolve().parents[1]
BINARY=pathlib.Path(os.environ.get('RD_P05_CORE_BINARY','/tmp/rd-p05-core-target/debug/rd-p05-core'))
SEED=CORE.parent/'fixtures/seed.json'
EVIDENCE=pathlib.Path(os.environ.get('RD_P05_EVIDENCE_DIR','/workspace/reports/rd-p05a-core-20261014')).resolve()
if EVIDENCE.is_relative_to(CORE.parents[4]):raise ValueError('test evidence must stay outside repository')
EVIDENCE.mkdir(parents=True,exist_ok=True)
DOMAIN={'store':'lab-store-1','scope':'lab-scope-1','stream':'lab-stream-1'}
class Process:
 def __init__(self,seed=SEED):
  self.p=subprocess.Popen([str(BINARY),'--seed',str(seed)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
  self.n=0
 def call(self,operation,**fields):
  self.n+=1; req=dict(protocol=0,request_id=str(self.n),op=operation,domain=DOMAIN,display_epoch='epoch-0');req.update(fields)
  self.p.stdin.write(json.dumps(req).encode()+b'\n');self.p.stdin.flush();return json.loads(self.p.stdout.readline(32770))
 def business(self,intent='intent-1',raw=None,revision='1',epoch='epoch-0'):
  return dict(object_id='supplier-a',intent=intent,expected_revision=revision,raw_utf16=raw if raw is not None else [ord(c) for c in ' 合成乙 '],display_epoch=epoch)
 def close(self):
  
  if not self.p.stdin.closed:self.p.stdin.close()
  self.p.wait(timeout=3); self.p.stdout.close();self.p.stderr.close()
class CoreTests(unittest.TestCase):
 def setUp(self): self.c=Process()
 def tearDown(self): self.c.close()
 def prepare(self,**fields):
  b=self.c.business(**fields);p=self.c.call('preview',**b);self.assertEqual(p['kind'],'prepared');b['plan_id']=p['plan']['id'];return b,p
 def test_hello_snapshot_actual(self):
  r=self.c.call('hello');self.assertEqual(r['kind'],'hello');self.assertEqual(r['snapshot']['suppliers'][0]['name'],'合成供应商');self.assertEqual(r['snapshot']['cursor']['seq'],'0')
 def test_preview_raw_nfc_noeffect(self):
  b,p=self.prepare(raw=[0xfeff,0x20,0x65,0x301,0x20]);self.assertEqual(p['plan']['normalized_name'],'é');s=self.c.call('snapshot');self.assertEqual(s['snapshot']['suppliers'][0]['revision'],'1')
 def test_domain_xml_beforetrim(self):
  for raw in [[11,0x7532],[0xd800],[32]*2001,[0x7532]*201,[]]: self.assertEqual(self.c.call('preview',**self.c.business(raw=raw))['kind'],'rejected')
 def test_commit_cas_and_onlyselected_row(self):
  b,p=self.prepare();r=self.c.call('commit',**b);self.assertEqual(r['kind'],'committed');self.assertEqual(r['receipt']['result_revision'],'2');self.assertEqual(r['snapshot']['suppliers'][1]['revision'],'1');self.assertEqual(r['receipt']['commit_cursor']['seq'],'1')
 def test_duplicate_original_command_is_oneeffect(self):
  b,p=self.prepare();r=self.c.call('commit',**b);again=self.c.call('commit',**b);self.assertEqual(again['kind'],'committed');self.assertEqual(again['receipt'],r['receipt']);self.assertEqual(again['snapshot']['suppliers'][0]['revision'],'2');self.assertEqual(again['snapshot']['cursor']['seq'],'1')
 def test_sameintent_changedraw_conflicts(self):
  b,p=self.prepare();self.c.call('commit',**b);b['raw_utf16']=[0x7532];r=self.c.call('commit',**b);self.assertEqual(r['kind'],'conflict');self.assertIsNone(r['receipt'])
 def test_stale_cas_plan_cannot_write(self):
  a,_=self.prepare();b,_=self.prepare(intent='intent-2');self.c.call('commit',**a);r=self.c.call('commit',**b);self.assertEqual(r['kind'],'conflict');self.assertEqual(self.c.call('snapshot')['snapshot']['suppliers'][0]['revision'],'2')
 def test_newintent_same_normalized_name_increments(self):
  b,p=self.prepare();self.c.call('commit',**b);b2,_=self.prepare(intent='explicit-new-intent',revision='2');r=self.c.call('commit',**b2);self.assertEqual(r['receipt']['result_revision'],'3');self.assertEqual(r['snapshot']['cursor']['seq'],'2')
 def test_lookup_absent_is_unknown_noeffect(self):
  b,p=self.prepare();r=self.c.call('lookup',**b);self.assertEqual(r['kind'],'unknown');self.assertIsNone(r['receipt']);self.assertEqual(self.c.call('snapshot')['snapshot']['cursor']['seq'],'0')
 def test_lostreply_recovered_by_readonly_lookup(self):
  self.c.close();self.c=Process(CORE.parent/'fixtures/seed-lost-reply.json');b,p=self.prepare();r=self.c.call('commit',**b);self.assertEqual(r['kind'],'unknown');self.assertIsNone(r['snapshot']);self.assertIsNone(r['receipt']);r=self.c.call('lookup',**b);self.assertEqual(r['kind'],'committed');self.assertEqual(r['receipt']['result_revision'],'2');self.assertEqual(r['snapshot']['cursor']['seq'],'1');self.assertEqual(self.c.call('lookup',**b)['receipt'],r['receipt'])
 def test_oldreceipt_independent_ofepoch_no_projection_regression(self):
  b,_=self.prepare();original=self.c.call('commit',**b)['receipt'];self.c.call('reconnect',new_display_epoch='epoch-1');n,_=self.prepare(intent='new',revision='2',raw=[0x7532],epoch='epoch-1');self.c.call('commit',**n);r=self.c.call('lookup',**b);self.assertEqual(r['display_admission'],'stale');self.assertEqual(r['receipt'],original);self.assertEqual(r['snapshot']['suppliers'][0]['revision'],'3');self.assertEqual(r['snapshot']['suppliers'][0]['name'],'甲')
 def test_strict_wire_types_fields_version(self):
  for delta in [dict(protocol=1),dict(protocol=False),dict(unexpected=True),dict(op='reseed'),dict(expected_revision='1'),dict(plan_id='fake'),dict(raw_utf16=[]),dict(new_display_epoch='x')]: self.assertEqual(self.c.call('hello',**delta)['kind'],'rejected')
 def test_decimalcanonical_not_float_loss(self):
  for rev in ['01','0','-1','1.0','18446744073709551616',1,True]: self.assertEqual(self.c.call('preview',**self.c.business(revision=rev))['kind'],'rejected')
 def test_foreigndomain_no_effect(self):
  domain=dict(DOMAIN,store='different');self.assertEqual(self.c.call('snapshot',domain=domain)['kind'],'rejected')
 def test_receipt_cannot_be_inserted(self):
  b,p=self.prepare();self.assertEqual(self.c.call('commit',receipt={'kind':'synthetic'},**b)['kind'],'rejected');self.assertEqual(self.c.call('lookup',**b)['kind'],'unknown')
 def test_precommitfault_rollsback_allstate(self):
  self.c.close();seed=json.loads(SEED.read_text());seed['trusted_faults']={'precommit_fail_once':True};path=(EVIDENCE/'seed-precommit.json');path.write_text(json.dumps(seed));self.c=Process(path);b,p=self.prepare();r=self.c.call('commit',**b);self.assertEqual(r['kind'],'rejected');self.assertEqual(self.c.call('snapshot')['snapshot']['cursor']['seq'],'0');self.assertEqual(self.c.call('lookup',**b)['kind'],'unknown');r=self.c.call('commit',**b);self.assertEqual(r['kind'],'committed');self.assertEqual(r['receipt']['result_revision'],'2')
 def test_explicitnull_optional_is_invalid(self):
  for key in ['object_id','intent','expected_revision','raw_utf16','plan_id','new_display_epoch']:
   r=self.c.call('hello',**{key:None});self.assertEqual(r['kind'],'rejected');self.assertEqual(r['reason'],'invalid_request');self.assertIsNone(r['snapshot']);self.assertEqual(r['request_id'],'');self.assertEqual(r['display_epoch'],'')
 def test_multibyte_identity_limit_exact_no_trim(self):
  self.assertEqual(self.c.call('hello',request_id='甲'*42)['kind'],'hello')
  self.assertEqual(self.c.call('hello',request_id='a'*128)['kind'],'hello')
  for bad in ['甲'*43,'a'*129,'']:
   r=self.c.call('hello',request_id=bad);self.assertEqual(r['kind'],'rejected');self.assertEqual(r['request_id'],'');self.assertEqual(r['display_epoch'],'');self.assertIsNone(r['snapshot'])
  r=self.c.call('hello',display_epoch=' epoch-0 ');self.assertEqual(r['display_epoch'],' epoch-0 ');self.assertEqual(r['display_admission'],'stale')
 def test_malformed_or_duplicateframe_noeffect(self):
  for frame in [b'{"protocol":0,"protocol":0}',b'\xff',b'null',b'{bad']:
   self.c.p.stdin.write(frame+b'\n');self.c.p.stdin.flush();r=json.loads(self.c.p.stdout.readline(32770));self.assertEqual(r['kind'],'rejected');self.assertEqual(r['reason'],'invalid_request');self.assertEqual(r['request_id'],'');self.assertIsNone(r['snapshot'])
  self.assertEqual(self.c.call('snapshot')['snapshot']['cursor']['seq'],'0')
 def test_oversizedframe_bounded_recovery(self):
  self.c.p.stdin.write(b'x'*32769+b'\n');self.c.p.stdin.flush();r=json.loads(self.c.p.stdout.readline(32770));self.assertEqual(r['kind'],'rejected');self.assertEqual(r['reason'],'frame_limit');self.assertEqual(r['request_id'],'');self.assertIsNone(r['snapshot']);self.assertEqual(self.c.call('hello')['kind'],'hello')
 def test_unterminated_eof_never_executes(self):
  self.c.p.stdin.write(json.dumps(dict(protocol=0,request_id='eof',op='hello',domain=DOMAIN,display_epoch='epoch-0')).encode());self.c.p.stdin.close();self.c.p.wait(timeout=3);self.assertEqual(self.c.p.stdout.read(),b'')
 def test_revision_above_js_exact_integer_is_string(self):
  self.c.close();seed=json.loads(SEED.read_text());seed['suppliers'][0]['revision']='9007199254740993';path=(EVIDENCE/'seed-high-revision.json');path.write_text(json.dumps(seed));self.c=Process(path);b,p=self.prepare(revision='9007199254740993');r=self.c.call('commit',**b);self.assertEqual(r['receipt']['result_revision'],'9007199254740994');self.assertEqual(r['receipt']['expected_revision'],'9007199254740993')
 def test_reply_budget_for_large_trusted_seed(self):
  self.c.close();seed=json.loads(SEED.read_text());rows=[]
  while True:
   candidate=rows+[dict(id='row-'+str(len(rows)),name='a'*200,revision='1')];seed['suppliers']=candidate
   if len(json.dumps(seed,separators=(',',':')).encode())>32650:break
   rows=candidate
  seed['suppliers']=rows;path=(EVIDENCE/'seed-reply-budget.json');path.write_text(json.dumps(seed,separators=(',',':')));self.c=Process(path)
  req=dict(protocol=0,request_id='\x00'*128,op='hello',domain=DOMAIN,display_epoch='\x00'*128);self.c.p.stdin.write(json.dumps(req).encode()+b'\n');self.c.p.stdin.flush();line=self.c.p.stdout.readline();self.assertLessEqual(len(line)-1,32768);r=json.loads(line);self.assertEqual(r['kind'],'unknown');self.assertEqual(r['reason'],'reply_limit');self.assertIsNone(r['snapshot'])
 def test_oversized_commitreply_retains_recoverable_ledger(self):
  self.c.close();seed=json.loads(SEED.read_text());rows=[]
  while True:
   candidate=rows+[dict(id='row-'+str(len(rows)),name='a'*200,revision='1')];seed['suppliers']=candidate
   if len(json.dumps(seed,separators=(',',':')).encode())>32650:break
   rows=candidate
  seed['suppliers']=rows;path=(EVIDENCE/'seed-effect-budget.json');path.write_text(json.dumps(seed,separators=(',',':')));self.c=Process(path)
  b=self.c.business(raw=[ord('a')]*200);b['object_id']='row-0';p=self.c.call('preview',**b);self.assertEqual(p['kind'],'prepared');b['plan_id']=p['plan']['id'];r=self.c.call('commit',request_id='\x00'*128,**b);self.assertEqual(r['kind'],'unknown');self.assertEqual(r['reason'],'reply_limit');self.assertIsNone(r['receipt']);r=self.c.call('lookup',**b);self.assertEqual(r['kind'],'committed');self.assertIsNone(r['snapshot']);self.assertEqual(r['receipt']['result_revision'],'2');self.assertEqual(r['receipt']['commit_cursor']['seq'],'1');first=r['receipt'];self.c.call('commit',request_id='\x00'*128,**b);self.assertEqual(self.c.call('lookup',**b)['receipt'],first)
if __name__=='__main__':unittest.main()
