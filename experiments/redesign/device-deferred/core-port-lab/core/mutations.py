#!/usr/bin/env python3
"""Real process inverse mutations. Ready client binary is never replaced.
Only owned source is temporarily changed; original bytes restored in finally.
"""
import hashlib, json, os, pathlib, subprocess, sys
CORE=pathlib.Path(__file__).resolve().parent
SOURCE=CORE/'src/main.rs'
ORIGINAL=SOURCE.read_bytes()
OUT=pathlib.Path(sys.argv[1]).resolve();OUT.mkdir(parents=True,exist_ok=True)
TARGET=pathlib.Path('/tmp/rd-p05-core-mutant-target')
env=dict(os.environ,CARGO_HOME='/tmp/muyon-spike01-toolchain/cargo',RUSTUP_HOME='/tmp/muyon-spike01-toolchain/rustup',CARGO_TARGET_DIR=str(TARGET),RD_P05_CORE_BINARY=str(TARGET/'debug/rd-p05-core'),RD_P05_EVIDENCE_DIR=str(OUT));env.pop('MUYON_EVAL_REAL',None)
build=['/tmp/muyon-spike01-toolchain/cargo/bin/cargo','+1.99.0','build','--offline','--locked','--manifest-path',str(CORE/'Cargo.toml')]
old_projection='''r.snapshot=Some(self.snapshot());
        // Verified effect'''
regressed='''r.snapshot=Some(self.snapshot());
        let receipt=r.receipt.as_ref().unwrap();
        for row in &mut r.snapshot.as_mut().unwrap().suppliers {if row.id==receipt.object_id {row.name=receipt.normalized_name.clone();row.revision=receipt.result_revision.clone();}}
        // Verified effect'''
mutants=[
 ('duplicate_replay_disabled','if let Some(effect)=self.effects.get(&business.intent) {','if let Some(effect)=None::<&Effect> {','test_duplicate_original_command_is_oneeffect'),
 ('cas_uses_current_instead_of_original','// CAS_GUARD: actual current row is revalidated at the execution boundary.\n        let candidate=match edit_candidate(&source,&self.domain.scope,&business.object_id,decimal(&business.expected_revision).unwrap(),&business.raw_utf16)', '// CAS_GUARD: actual current row is revalidated at the execution boundary.\n        let candidate=match edit_candidate(&source,&self.domain.scope,&business.object_id,source.revision,&business.raw_utf16)','test_stale_cas_plan_cannot_write'),
 ('unknown_lookup_dispatches','let Some(effect)=self.effects.get(&business.intent).cloned() else {return r;};','let Some(effect)=self.effects.get(&business.intent).cloned() else {return self.commit(req,business);};','test_lookup_absent_is_unknown_noeffect'),
 ('old_receipt_regresses_projection',old_projection,regressed,'test_oldreceipt_independent_ofepoch_no_projection_regression'),
]
rows=[]
try:
 for name,before,after,test in mutants:
  text=ORIGINAL.decode();assert text.count(before)==1,name;SOURCE.write_text(text.replace(before,after))
  p=subprocess.run(build,env=env,capture_output=True);(OUT/(name+'-build.log')).write_bytes(p.stdout+p.stderr);assert p.returncode==0,name
  p=subprocess.run([sys.executable,str(CORE/'tests/process.py'),'CoreTests.'+test],env=env,capture_output=True);log=p.stdout+p.stderr;(OUT/(name+'.log')).write_bytes(log)
  assert p.returncode==1 and b'AssertionError' in log and b'failures=1' in log,name
  rows.append(dict(mutant=name,test=test,build_exit=0,test_exit=1,assertion_detected=True))
finally:SOURCE.write_bytes(ORIGINAL)
assert SOURCE.read_bytes()==ORIGINAL
(OUT/'mutations.json').write_text(json.dumps(dict(source_sha256=hashlib.sha256(ORIGINAL).hexdigest(),restored=True,mutants=rows),indent=2)+'\n')
print('Four semantic mutants detected at named process assertions; original source restored')
