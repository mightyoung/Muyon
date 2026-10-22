#!/usr/bin/env python3
import pathlib,subprocess,tempfile,json,hashlib,os,datetime
root=pathlib.Path(subprocess.check_output(['git','rev-parse','--show-toplevel'],text=True).strip())
out=root/'docs/tasks/bot-setup-draft-20261022/tail-recheck-evidence/author-final';out.mkdir(exist_ok=False)
module='crates/muyon-core/src/bot_definitions.rs';test='crates/muyon-core/src/bot_definitions/tests.rs';runner='docs/tasks/bot-setup-draft-20261022/run-creation-checks.py'
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def sha(b):return hashlib.sha256(b).hexdigest()
meta={'head':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'kind':'new latest-protocol transaction-tail regression verification','started_utc':now(),'inputs_sha256':{r:sha((root/r).read_bytes()) for r in [module,test,runner]},'dependency_commit':'098d9aca214e6642c1b3ffde64921ebedbae335d','commands':[],'mutations':[]}
meta['dependency_source_sha256']=sha(subprocess.check_output(['git','show',meta['dependency_commit']+':crates/muyon-core/src/bot_drafts.rs']))
def capture(label,cmd,cwd):
 start=now();r=subprocess.run(cmd,cwd=cwd,capture_output=True)
 (out/(label+'.stdout.log')).write_bytes(r.stdout);(out/(label+'.stderr.log')).write_bytes(r.stderr)
 meta['commands'].append({'label':label,'argv':cmd,'cwd':str(cwd),'started_utc':start,'ended_utc':now(),'exit_code':r.returncode})
 return r
assert capture('baseline',['python3',runner],root).returncode==0
original=(root/module).read_text()
variants=[('tail-verification', 'verify_current(store, &key, id, &original, "committed", Some(&receipt))?;', '/* omitted tail verification */'), ('live-project', 'ReadScope::current(store, project).map_err(|_| "bot_scope")?;', '/* omitted current project read */'), ('source-scope-key', '|| cell(r, 8)? != key', ''), ('tail-epoch', '|| current.epoch != original.epoch\n        || current.epoch != store.owner_epoch()', ''), ('source-registry-version', '|| cell(&ns[0], 1)? != "1"', ''), ('persistent-workspace', '|| cell(&workspace[0], 0)? != store.workspace_id()', '')]
for label,before,after in variants:
 assert before in original,label
 with tempfile.TemporaryDirectory(prefix='bot-create-mutation-') as temp:
  copy=pathlib.Path(temp)/'repo';subprocess.run(['git','clone','--quiet','--shared','--no-hardlinks',str(root),str(copy)],check=True)
  modified=original.replace(before,after);(copy/module).write_text(modified)
  r=capture(label,['python3',runner],copy)
  assert r.returncode!=0 and b'test result: FAILED' in r.stdout,label+' did not fail at a behavioral assertion'
  meta['mutations'].append({'label':label,'before':before,'after':after,'replacement_count':original.count(before),'mutated_source_sha256':sha(modified.encode()),'result':'compiled, failed behavioral tests','exit_code':r.returncode})
  print(label+': KILLED by behavioral assertion',flush=True)
meta['ended_utc']=now();meta['log_sha256']={p.name:sha(p.read_bytes()) for p in sorted(out.glob('*.log'))}
(out/'metadata.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
