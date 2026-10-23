#!/usr/bin/env python3
import os,subprocess,pathlib,json,datetime,hashlib
root=pathlib.Path(subprocess.check_output(['git','rev-parse','--show-toplevel'],text=True).strip());out=root/'docs/tasks/bot-core-continuation-20261023/evidence';out.mkdir(exist_ok=True)
env=os.environ.copy();env.update(RUSTUP_HOME='/workspace/bot-core-tools/rustup',CARGO_HOME='/workspace/bot-core-tools/cargo',CARGO_TARGET_DIR='/workspace/bot-core-tools/target-baseline',RUSTFLAGS='-Lnative=/workspace/bot-core-tools/native-links')
cargo='/workspace/bot-core-tools/cargo/bin/cargo'
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
meta={'head':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'started_utc':now(),'cwd':str(root),'environment_override':{k:env[k] for k in ['RUSTUP_HOME','CARGO_HOME','CARGO_TARGET_DIR','RUSTFLAGS']},'commands':[]}
def run(label,cmd):
 start=now();r=subprocess.run(cmd,cwd=root,env=env,capture_output=True);(out/(label+'.stdout.log')).write_bytes(r.stdout);(out/(label+'.stderr.log')).write_bytes(r.stderr);meta['commands'].append({'label':label,'argv':cmd,'started_utc':start,'ended_utc':now(),'exit_code':r.returncode});print(label+': exit '+str(r.returncode),flush=True);return r.returncode
run('rustc',['/workspace/bot-core-tools/cargo/bin/rustc','--version'])
cmd=[cargo,'test','--offline','--locked','--manifest-path','crates/Cargo.toml','-p','muyon-core','--lib','bot_definitions','--','--test-threads=1','--nocapture']
if run('initial-offline-bot',cmd)!=0:
 if run('cargo-fetch',[cargo,'fetch','--locked','--manifest-path','crates/Cargo.toml'])!=0:raise RuntimeError('dependency fetch failed')
 run('bot-baseline',cmd)
for target in ['bot_drafts','agent_owner','agent_product','agent_workflow','agent_tools','agent_child_tools']:
 run(target,[cargo,'test','--offline','--locked','--manifest-path','crates/Cargo.toml','-p','muyon-core','--test',target,'--','--test-threads=1','--nocapture'])
run('strict-current',[cargo,'clippy','--offline','--locked','--manifest-path','crates/Cargo.toml','--workspace','--all-targets','--','-D','warnings'])
meta['ended_utc']=now();meta['log_sha256']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(out.glob('*.log'))};(out/'metadata.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
