import os,sys,subprocess,json,hashlib,time
from pathlib import Path
root=Path('/workspace/leaderb-b3-b'); evidence=Path('/workspace/leaderb-b3-evidence/b')
def run(name,command,env=None):
 start=time.time(); log=evidence/(name+'.log');log.parent.mkdir(parents=True,exist_ok=True)
 with log.open('wb') as output:
  result=subprocess.run(command,cwd=root,env=env,stdout=output,stderr=subprocess.STDOUT)
 (evidence/(name+'.json')).write_text(json.dumps(dict(command=command,exit_code=result.returncode,seconds=time.time()-start,log=str(log),sha256=hashlib.sha256(log.read_bytes()).hexdigest()),indent=2)+'\n')
 print(name,result.returncode,flush=True);return result.returncode
if __name__=='__main__':
 for component,lab in [('core','core-agent-lab'),('plugin','plugin-contract-lab'),('host','rust-agent-host-lab')]:
  env=dict(os.environ,CARGO_TARGET_DIR=str(evidence/'targets'/component))
  run('test-list-'+component,['cargo','test','--offline','--locked','--manifest-path',str(root/'experiments/redesign'/lab/'core/Cargo.toml'),'--','--list'],env)
 for component in ['core','plugin','host']:
  env=dict(os.environ,CARGO_TARGET_DIR=str(evidence/'targets'/component),EVIDENCE_DIR=str(evidence/('full-'+component)))
  run('full-'+component,['bash',str(evidence/'runners/combined_full.sh'),component],env)
