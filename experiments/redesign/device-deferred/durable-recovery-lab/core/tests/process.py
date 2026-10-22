#!/usr/bin/env python3
"""Linux private-directory, real independent process fault/reopen tests."""
import fcntl, hashlib, json, os, pathlib, select, shutil, signal, subprocess, tempfile, unittest
BIN=os.environ.get('RD_P06_BINARY','/tmp/rd-p06-target/debug/rd-p06-durable')
OBSERVATIONS=[]
D={'store':'synthetic-store','scope':'synthetic-scope','stream':'synthetic-stream'}
class DurableTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory(prefix='rd-p06-');self.base=pathlib.Path(self.temp.name);self.state=self.base/'state';self.effects=self.base/'external-effects'
 def tearDown(self):self.temp.cleanup()
 def req(self,op='submit',intent='intent-1',raw=None,epoch='epoch-0',**extra):
  r=dict(protocol=0,op=op,domain=D,epoch=epoch)
  if op in ['submit','lookup']:r.update(intent=intent,operation='synthetic_increment',args={'raw_utf16':raw if raw is not None else [0x7532]})
  r.update(extra);return r
 def command(self,req,fault=None):
  args=[BIN,'--state-dir',str(self.state),'--effect-dir',str(self.effects),'--request',json.dumps(req)]
  if fault:args+=['--fault',fault]
  return args
 def runreq(self,req=None,fault=None):
  p=subprocess.run(self.command(req or self.req(),fault),capture_output=True,timeout=5)
  if fault:self.assertEqual(p.returncode,90);self.assertEqual(p.stdout,b'');return None
  self.assertEqual(p.returncode,0,p.stderr.decode());return json.loads(p.stdout)
 def count(self):
  p=self.effects/'effects.json'
  
  if not p.exists():count=0;digest=None
  else:
   raw=p.read_bytes();count=int(json.loads(raw)['payload']['count']);digest=hashlib.sha256(raw).hexdigest()
  OBSERVATIONS.append({'test':self._testMethodName,'actual_external_count':str(count),'actual_effect_file_sha256':digest})
  return count
 def test_commit_reopen_duplicate_external_count(self):
  a=self.runreq();self.assertEqual(a['kind'],'committed');self.assertEqual(self.count(),1);b=self.runreq();self.assertEqual(b['receipt'],a['receipt']);self.assertEqual(self.count(),1)
 def test_sameintent_fullbinding_conflict(self):
  self.assertEqual(self.runreq()['kind'],'committed');r=self.runreq(self.req(raw=[0x4e59]));self.assertEqual(r['kind'],'conflict');self.assertEqual(self.count(),1)
 def test_foreign_domain_rejected(self):
  r=self.req();r['domain']=dict(D,stream='other');self.assertEqual(self.runreq(r)['kind'],'rejected');self.assertEqual(self.count(),0)
 def test_pending_durable_before_effect_and_unknown_never_retry(self):
  self.runreq(fault='before_effect');ledger=json.loads((self.state/'ledger.json').read_text());self.assertIn('intent-1',ledger['payload']['entries']);self.assertEqual(self.count(),0)
  self.assertEqual(self.runreq()['kind'],'unknown');self.assertEqual(self.runreq(self.req('lookup'))['kind'],'unknown');self.assertEqual(self.count(),0)
 def test_pending_before_effect_receipt_windows(self):
  for fault,count in [('after_pending',0),('before_effect',0),('after_effect',1),('before_receipt',1)]:
   with self.subTest(fault=fault):
    self.state=self.base/fault/'state';self.effects=self.base/fault/'effects';self.runreq(fault=fault);self.assertEqual(self.count(),count);self.assertEqual(self.runreq(self.req('lookup'))['kind'],'unknown');self.assertEqual(self.runreq()['kind'],'unknown');self.assertEqual(self.count(),count)
 def test_receipt_and_pair_fault_boundaries(self):
  for fault,seq in [('after_receipt','0'),('before_pair','0'),('during_pair_temp','0'),('after_pair','1')]:
   with self.subTest(fault=fault):
    self.state=self.base/fault/'state';self.effects=self.base/fault/'effects';self.runreq(fault=fault);r=self.runreq(self.req('lookup'));self.assertEqual(r['kind'],'committed');self.assertEqual(r['snapshot']['cursor']['seq'],seq);self.assertEqual(r['snapshot']['state'],'initial' if seq=='0' else 'effect:1');self.assertEqual(self.count(),1);self.assertEqual(self.runreq()['kind'],'committed');self.assertEqual(self.count(),1)
 def test_oldreceipt_does_not_replace_newprojection(self):
  initial=self.runreq();self.assertEqual(initial['kind'],'committed');first=initial['receipt'];self.runreq(self.req(intent='new'));self.runreq(self.req('reconnect',epoch='epoch-1'));r=self.runreq(self.req('lookup'));self.assertEqual(r['receipt'],first);self.assertEqual(r['display_admission'],'stale');self.assertEqual(r['snapshot']['cursor']['seq'],'2');self.assertEqual(r['snapshot']['state'],'effect:2')
 def test_slow_snapshot_does_not_erase_receipt(self):
  initial=self.runreq();self.assertEqual(initial['kind'],'committed');first=initial['receipt'];old={'cursor':dict(D,seq='0'),'state':'initial'};r=self.runreq(self.req('install_snapshot',snapshot=old));self.assertEqual(r['kind'],'rejected');r=self.runreq(self.req('lookup'));self.assertEqual(r['receipt'],first);self.assertEqual(r['snapshot']['cursor']['seq'],'1')
 def test_corrupt_files_failclosed_without_new_effect(self):
  for name in ['ledger.json','projection.json']:
   with self.subTest(name=name):
    self.state=self.base/name/'state';self.effects=self.base/name/'effects';self.assertEqual(self.runreq()['kind'],'committed');(self.state/name).write_text('{corrupt');r=self.runreq();self.assertEqual(r['kind'],'unavailable');self.assertEqual(self.count(),1)
 def test_missing_file_never_silently_reinitializes(self):
  self.assertEqual(self.runreq()['kind'],'committed');(self.state/'ledger.json').unlink();self.assertEqual(self.runreq()['kind'],'unavailable');self.assertEqual(self.count(),1)
 def test_effect_store_write_failure_retains_pending_no_effect(self):
  self.assertEqual(self.runreq(self.req('snapshot'))['kind'],'snapshot');(self.effects/'effects.json').unlink();(self.effects/'effects.json').mkdir();self.assertEqual(self.runreq()['kind'],'unavailable');(self.effects/'effects.json').rmdir();self.assertEqual(self.runreq()['kind'],'unavailable')
 def test_concurrent_sameintent_single_external_effect(self):
  ps=[subprocess.Popen(self.command(self.req()),stdout=subprocess.PIPE,stderr=subprocess.PIPE) for _ in range(6)]
  replies=[]
  for p in ps:out,err=p.communicate(timeout=10);self.assertEqual(p.returncode,0,err);replies.append(json.loads(out))
  self.assertEqual([r['kind'] for r in replies],['committed']*6);self.assertEqual(self.count(),1);self.assertEqual(len({r['receipt']['id'] for r in replies}),1)
 def test_crash_releases_lock(self):
  self.runreq(fault='after_effect');self.assertEqual(self.runreq(self.req('snapshot'))['kind'],'snapshot');self.assertEqual(self.count(),1)
 def test_strict_protocol_and_raw_binding(self):
  for delta in [dict(protocol=1),dict(unexpected=True),dict(args={'raw_utf16':[True]}),dict(args={'raw_utf16':[65536]}),dict(operation='other')]:
   r=self.req();r.update(delta);self.assertEqual(self.runreq(r)['kind'],'rejected');self.assertEqual(self.count(),0)
 def test_state_rollback_before_pending_cannot_redispatch(self):
  self.runreq(self.req('snapshot'));before=(self.state/'ledger.json').read_bytes();pair=(self.state/'projection.json').read_bytes();self.runreq();(self.state/'ledger.json').write_bytes(before);(self.state/'projection.json').write_bytes(pair)
  self.assertEqual(self.runreq()['kind'],'unknown');self.assertEqual(self.runreq(self.req('lookup'))['kind'],'unknown');self.assertEqual(self.count(),1)
 def test_state_rollback_changed_binding_conflicts(self):
  self.runreq(self.req('snapshot'));before=(self.state/'ledger.json').read_bytes();pair=(self.state/'projection.json').read_bytes();self.runreq();(self.state/'ledger.json').write_bytes(before);(self.state/'projection.json').write_bytes(pair)
  self.assertEqual(self.runreq(self.req(raw=[0x4e59]))['kind'],'conflict');self.assertEqual(self.count(),1)
 def test_changed_effect_source_same_path_is_rejected(self):
  self.runreq();original=self.effects;other=self.base/'other';other_effect=self.base/'other-effect';oldstate=self.state;self.state=other;self.effects=other_effect;self.runreq(self.req('snapshot'));foreign=(other_effect/'effects.json').read_bytes();self.state=oldstate;self.effects=original
  (original/'effects.json').write_bytes(foreign);self.assertEqual(self.runreq()['kind'],'unavailable')
 def test_alternate_effect_directory_and_cloned_state_failclosed(self):
  self.runreq();oldstate=self.state;old_effect=self.effects;self.effects=self.base/'new-effects';self.assertEqual(self.runreq()['kind'],'unavailable');self.assertFalse((self.effects/'effects.json').exists());clone=self.base/'clone';shutil.copytree(oldstate,clone);self.state=clone;self.assertEqual(self.runreq()['kind'],'unavailable');self.state=oldstate;self.effects=old_effect;self.assertEqual(self.count(),1)
 def test_projection_corruption_cannot_erase_verified_receipt_axis(self):
  first=self.runreq()['receipt'];(self.state/'projection.json').write_text('{bad');r=self.runreq(self.req('lookup'));self.assertEqual(r['kind'],'committed');self.assertEqual(r['receipt'],first);self.assertIsNone(r['snapshot']);self.assertEqual(self.runreq()['kind'],'unavailable');self.assertEqual(self.count(),1)
 def test_samewatermark_fork_rejected(self):
  first=self.runreq()['receipt'];r=self.runreq(self.req('install_snapshot',snapshot={'cursor':dict(D,seq='1'),'state':'fork'}));self.assertEqual(r['kind'],'rejected');self.assertEqual(self.runreq(self.req('lookup'))['receipt'],first)
 def test_real_effect_write_failure_keeps_durable_pending(self):
  self.runreq(self.req('snapshot'));lock=open(self.effects/'.lock','r+');fcntl.flock(lock,fcntl.LOCK_EX)
  p=subprocess.Popen(self.command(self.req()),stdout=subprocess.PIPE,stderr=subprocess.PIPE);(self.effects/('.write-'+str(p.pid))).mkdir();fcntl.flock(lock,fcntl.LOCK_UN);lock.close();out,err=p.communicate(timeout=5);self.assertEqual(p.returncode,0,err);self.assertEqual(json.loads(out)['kind'],'unavailable');self.assertEqual(self.count(),0);self.assertIn('intent-1',json.loads((self.state/'ledger.json').read_text())['payload']['entries']);self.assertEqual(self.runreq()['kind'],'unknown');self.assertEqual(self.count(),0)
 def test_effect_pair_id_replacement_not_path_only(self):
  self.runreq(self.req('snapshot'));original=self.effects;oldstate=self.state;self.state=self.base/'replacement-state';self.effects=self.base/'replacement-effects';self.runreq(self.req('snapshot'));foreign=json.loads((self.effects/'effects.json').read_text());foreign['payload']['owner']=str(oldstate.resolve());foreign['checksum']=hashlib.sha256(json.dumps(foreign['payload'],separators=(',',':'),ensure_ascii=False).encode()).hexdigest();self.state=oldstate;self.effects=original;(original/'effects.json').write_text(json.dumps(foreign));self.assertEqual(self.runreq()['kind'],'unavailable')
 def test_fresh_lookup_strict_readonly_no_dirs_or_identity(self):
  r=self.runreq(self.req('lookup'));self.assertEqual(r['kind'],'unknown');self.assertEqual(r['reason'],'not_found');self.assertFalse(self.state.exists());self.assertFalse(self.effects.exists())
 def test_degraded_lookup_never_rewrites_projection_or_ledger(self):
  self.runreq();(self.state/'projection.json').write_text('{bad');before={p:str(p.stat().st_mtime_ns)+':'+p.read_bytes().hex() for p in [self.state/'ledger.json',self.state/'projection.json',self.effects/'effects.json',self.state/'owner.json']};self.assertEqual(self.runreq(self.req('lookup'))['kind'],'committed');self.assertEqual(before,{p:str(p.stat().st_mtime_ns)+':'+p.read_bytes().hex() for p in before})
 def test_real_sigkill_releases_lock_and_never_retries(self):
  for point,count in [('after_pending',0),('after_effect',1)]:
   with self.subTest(point=point):
    self.state=self.base/point/'state';self.effects=self.base/point/'effects';p=subprocess.Popen(self.command(self.req(),'pause_'+point),stdout=subprocess.PIPE,stderr=subprocess.PIPE);ready,_,_=select.select([p.stderr],[],[],3);self.assertTrue(ready);self.assertEqual(p.stderr.readline(),b'fault_barrier\n');p.kill();out,err=p.communicate(timeout=5);self.assertEqual(p.returncode,-signal.SIGKILL);self.assertEqual(out,b'');self.assertEqual(self.count(),count);self.assertEqual(self.runreq()['kind'],'unknown');self.assertEqual(self.count(),count)
 def test_null_optional_not_omission(self):
  for key in ['intent','operation','args','snapshot']:
   r=self.req('snapshot');r[key]=None;self.assertEqual(self.runreq(r)['kind'],'rejected');self.assertFalse(self.state.exists());self.assertFalse(self.effects.exists())
if __name__=='__main__':
 result=unittest.main(exit=False).result
 evidence=pathlib.Path(os.environ.get('RD_P06_EVIDENCE_DIR','/tmp/rd-p06a-evidence-20261014')).resolve()
 if evidence.is_relative_to(pathlib.Path(__file__).resolve().parents[6]):raise ValueError('evidence must remain outside repository')
 evidence.mkdir(parents=True,exist_ok=True)
 (evidence/'actual-effect-observations.json').write_text(json.dumps(OBSERVATIONS,indent=2)+'\n')
 raise SystemExit(0 if result.wasSuccessful() else 1)
