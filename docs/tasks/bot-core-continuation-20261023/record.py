#!/usr/bin/env python3
import sys, os, subprocess, pathlib, datetime, json, hashlib
root=pathlib.Path(__file__).resolve().parents[3]
label=sys.argv[1]; args=sys.argv[2:]
out=pathlib.Path(__file__).parent/'evidence'
env=os.environ.copy(); env.update(RUSTUP_HOME='/workspace/bot-core-tools/rustup',CARGO_HOME='/workspace/bot-core-tools/cargo',CARGO_TARGET_DIR='/workspace/bot-core-tools/target-baseline',RUSTFLAGS='-Lnative=/workspace/bot-core-tools/native-links')
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
m={'head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'started_utc':now(),'argv':args,'environment_override':{k:env[k] for k in ['RUSTUP_HOME','CARGO_HOME','CARGO_TARGET_DIR','RUSTFLAGS']}}
r=subprocess.run(args,cwd=root,env=env,capture_output=True)
for stream,data in [('stdout',r.stdout),('stderr',r.stderr)]:
 p=out/(label+'.'+stream+'.log');p.write_bytes(data);m[stream+'_sha256']=hashlib.sha256(data).hexdigest()
m.update(ended_utc=now(),exit_code=r.returncode);(out/(label+'.json')).write_text(json.dumps(m,indent=2)+'\n')
print(label+': exit '+str(r.returncode)); print(r.stdout.decode(errors='replace')[-3500:]);print(r.stderr.decode(errors='replace')[-1500:]);sys.exit(r.returncode)
