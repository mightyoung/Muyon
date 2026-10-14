"""Five compiling inverse mutations. Preserve byte restoration and intended assertion logs.
Run only in an isolated author/review checkout; source is restored after every mutant.
"""
import argparse, hashlib, json, os, pathlib, subprocess, sys
CORE=pathlib.Path(__file__).resolve().parent
SOURCE=CORE/'src/main.rs'
CARGO=pathlib.Path('/tmp/muyon-spike01-toolchain/cargo/bin/cargo')
def sha(data): return hashlib.sha256(data).hexdigest()
def replace(text,old,new):
    if text.count(old)!=1: raise RuntimeError('mutation anchor not unique: '+old)
    return text.replace(old,new)
def transaction(s):
    s=replace(s,'let tx=db.transaction()?; // MUTATION_TRANSACTION','let tx=(); // MUTATION_TRANSACTION')
    return s.replace('tx.commit()?;','let _=tx;')
def cas(s):
    s=replace(s,'edit_candidate(&snap,&b.scope,&b.supplier,revision(&b.expected_revision)?,&b.raw_utf16)', 'edit_candidate(&snap,&b.scope,&b.supplier,snap.revision,&b.raw_utf16)')
    s=replace(s,'AND revision=?",&[&c.normalized_name,&next,&b.supplier,&b.scope,&b.expected_revision]', '",&[&c.normalized_name,&next,&b.supplier,&b.scope]')
    return s
def duplicate(s):
    return replace(s,'if let Some(result)=existing(db,domain,b)? {return Ok(result);} // MUTATION_DUPLICATE','let _=existing(db,domain,b)?; // MUTATION_DUPLICATE')
def binding(s):
    return replace(s,'if original!=*b {return Ok(Some(json!({"status":"conflict"})));} // MUTATION_BINDING','if false {return Ok(Some(json!({"status":"conflict"})));} // MUTATION_BINDING')
def unknown(s):
    s=replace(s,'"pending"=>json!({"status":"unknown"}), // MUTATION_UNKNOWN','"pending"=>return Ok(None), // MUTATION_UNKNOWN')
    return replace(s,'let mut claim_facts=Facts::capture(db)?;', 'db.exec("DELETE FROM intents WHERE intent=? AND status=\'pending\'",&[&b.intent])?;\n        let mut claim_facts=Facts::capture(db)?;')
MUTANTS=[('shared_transaction',transaction,'Process.test_receipt_insert_failure','Lists differ'),('cas_guard',cas,'Process.test_cas_rejection','unavailable: final consistency: invalid history effect'),('duplicate_guard',duplicate,'Process.test_replay_before_stale_cas_and_current_separate','UNIQUE constraint failed: intents.intent'),('binding_comparison',binding,'Process.test_pending_binding_and_absent_receipt',"'unknown' != 'conflict'"),('unknown_no_dispatch',unknown,'Process.test_sql_exit_faults',"'committed' != 'unknown'")]
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--evidence-dir',required=True);a=parser.parse_args()
    evidence=pathlib.Path(a.evidence_dir);evidence.mkdir(parents=True,exist_ok=True)
    original=SOURCE.read_bytes();env=dict(os.environ,CARGO_HOME='/tmp/muyon-spike01-toolchain/cargo',RUSTUP_HOME='/tmp/muyon-spike01-toolchain/rustup',RUSTUP_TOOLCHAIN='1.99.0')
    target=evidence/'mutation-target';build=[str(CARGO),'build','--offline','--locked','--manifest-path',str(CORE/'Cargo.toml'),'--target-dir',str(target)]
    records=[]
    try:
        for name,mutate,test,intended in MUTANTS:
            mutated=mutate(original.decode()).encode();SOURCE.write_bytes(mutated)
            record=dict(name=name,source_before=sha(original),source_mutated=sha(mutated),build_command=build,test_command=[sys.executable,str(CORE/'tests/process.py'),test])
            try:
                p=subprocess.run(build,env=env,capture_output=True,text=True,timeout=120)
                (evidence/(name+'-build.log')).write_text(p.stdout+p.stderr);record['build_exit']=p.returncode
                if p.returncode!=0: raise RuntimeError(name+' build failed: setup failure, not inverse RED')
                tenv=dict(env,RD_P07_BIN=str(target/'debug/rd-p07-atomic'),RD_P07_SQL_EVIDENCE=str(evidence/(name+'-physical.jsonl')))
                q=subprocess.run(record['test_command'],env=tenv,capture_output=True,text=True,timeout=60)
                output=q.stdout+q.stderr;(evidence/(name+'-assertion.log')).write_text(output);record['test_exit']=q.returncode
                record['intended_assertion']=intended;record['intended_assertion_observed']=intended in output and 'AssertionError' in output
                if q.returncode==0 or not record['intended_assertion_observed']: raise RuntimeError(name+' did not fail intended assertion')
            finally:
                SOURCE.write_bytes(original);record['source_restored']=sha(SOURCE.read_bytes());record['restoration_equal']=SOURCE.read_bytes()==original;records.append(record)
            print(name+': build 0, intended assertion failed, bytes restored',flush=True)
    finally:
        SOURCE.write_bytes(original);(evidence/'mutation-results.json').write_text(json.dumps(records,indent=2)+'\n')
    # Rebuild canonical source in a separate normal target; then full GREEN, never mutant executable.
    normal=evidence/'restored-target';final_build=build[:-1]+[str(normal)]
    p=subprocess.run(final_build,env=env,capture_output=True,text=True,timeout=120)
    (evidence/'restored-build.log').write_text(p.stdout+p.stderr)
    if p.returncode: raise RuntimeError('restored build failed')
    q=subprocess.run([sys.executable,str(CORE/'tests/process.py')],env=dict(env,RD_P07_BIN=str(normal/'debug/rd-p07-atomic'),RD_P07_SQL_EVIDENCE=str(evidence/'restored-physical.jsonl')),capture_output=True,text=True,timeout=60)
    (evidence/'restored-green.log').write_text(q.stdout+q.stderr)
    if q.returncode: raise RuntimeError('restored full suite failed')
    print('canonical source restored; complete process suite GREEN',flush=True)
if __name__=='__main__': main()
