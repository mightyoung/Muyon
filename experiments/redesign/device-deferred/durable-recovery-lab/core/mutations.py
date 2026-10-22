#!/usr/bin/env python3
"""Compile each inverse mutation, then detect a real subprocess behavior failure.
Ready binary is never replaced. Original source restored byte-for-byte in finally.
"""
import hashlib,json,os,pathlib,subprocess,sys
CORE=pathlib.Path(__file__).resolve().parent;SOURCE=CORE/'src/main.rs';original=SOURCE.read_bytes();OUT=pathlib.Path(sys.argv[1]).resolve();OUT.mkdir(parents=True,exist_ok=True)
env=dict(os.environ,CARGO_HOME='/tmp/muyon-spike01-toolchain/cargo',RUSTUP_HOME='/tmp/muyon-spike01-toolchain/rustup',CARGO_TARGET_DIR='/tmp/rd-p06-mutant-target',RD_P06_BINARY='/tmp/rd-p06-mutant-target/debug/rd-p06-durable');env.pop('MUYON_EVAL_REAL',None)
build=['/tmp/muyon-spike01-toolchain/cargo/bin/cargo','+1.99.0','build','--offline','--locked','--manifest-path',str(CORE/'Cargo.toml')]
mutants=[
 ('pending_after_effect','write(&self.state.join("ledger.json"),&self.ledger,"")?;\n   die(fault,"after_pending");','die(fault,"after_pending");','test_pending_durable_before_effect_and_unknown_never_retry'),
 ('unknown_redispatch','return Ok(self.reply(&req.epoch,"unknown",Some("pending_without_receipt"),None));','self.ledger.entries.remove(&c.intent);','test_pending_durable_before_effect_and_unknown_never_retry'),
 ('snapshot_erases_receipt','let candidate=req.snapshot.unwrap();let seq=num(&candidate.cursor.seq)?;','self.ledger.entries.clear();write(&self.state.join("ledger.json"),&self.ledger,"")?;let candidate=req.snapshot.unwrap();let seq=num(&candidate.cursor.seq)?;','test_slow_snapshot_does_not_erase_receipt'),
 ('rollback_ignores_external_history','if let Some(existing)=self.effects.entries.iter().find(|e|e.command.intent==c.intent){','if let Some(existing)=None::<&EffectRecord>{','test_state_rollback_before_pending_cannot_redispatch'),
]
rows=[]
try:
 for name,before,after,test in mutants:
  env['RD_P06_EVIDENCE_DIR']=str(OUT/name);text=original.decode();assert text.count(before)==1,name;SOURCE.write_text(text.replace(before,after))
  p=subprocess.run(build,env=env,capture_output=True);(OUT/(name+'-build.log')).write_bytes(p.stdout+p.stderr);assert p.returncode==0,name
  p=subprocess.run([sys.executable,str(CORE/'tests/process.py'),'DurableTests.'+test],env=env,capture_output=True);log=p.stdout+p.stderr;(OUT/(name+'.log')).write_bytes(log)
  assert p.returncode==1 and b'AssertionError' in log and b'failures=1' in log and b'errors=' not in log,name
  rows.append(dict(mutant=name,test=test,build_exit=0,test_exit=1,assertion_detected=True))
finally:SOURCE.write_bytes(original)
assert SOURCE.read_bytes()==original
(OUT/'mutations.json').write_text(json.dumps(dict(source_sha256=hashlib.sha256(original).hexdigest(),restored=True,mutants=rows),indent=2)+'\n')
print('Four semantic mutants compiled, failed real assertions, restored original source')
