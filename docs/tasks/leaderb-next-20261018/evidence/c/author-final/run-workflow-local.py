import json,os,subprocess,shutil,yaml
from pathlib import Path
root=Path('/workspace/leaderb-store');out=Path(__file__).parent
sha=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
assert sha=='fdc9aea120925229aa592c3551efab9b3f67a825'
workflow=yaml.safe_load((root/'.github/workflows/leaderb-store-readonly.yml').read_text())
runner=Path('/workspace/toolchains/store-rust/local-runner');runner.mkdir(exist_ok=True)
env=dict(os.environ,EXPECTED_SHA=sha,RUNNER_TEMP=str(runner),GITHUB_ENV=str(out/'github-env.txt'),CARGO_HOME='/workspace/toolchains/store-rust/cargo',RUSTUP_HOME='/workspace/toolchains/store-rust/rustup',PATH='/workspace/toolchains/store-rust/cargo/bin:'+os.environ['PATH'])
results=[]
for step in workflow['jobs']['readonly-supplier']['steps']:
 if 'run' not in step:continue
 command=['bash','--noprofile','--norc','-e','-o','pipefail','-c',step['run']]
 r=subprocess.run(command,cwd=root,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 name=step['name'].replace(' ','-').lower()
 (out/(name+'.log')).write_bytes(r.stdout)
 results.append(dict(name=step['name'],exit=r.returncode,source_sha=sha))
 print(name,r.returncode,flush=True)
 if Path(env['GITHUB_ENV']).exists():
  for line in Path(env['GITHUB_ENV']).read_text().splitlines():
   key,value=line.split('=',1);env[key]=value
 if r.returncode:break
(out/'local-workflow-results.json').write_text(json.dumps(results,indent=2)+'\n')
if (root/'store-read-evidence').exists():shutil.move(root/'store-read-evidence',out/'workflow-raw')
assert all(r['exit']==0 for r in results)
