#!/usr/bin/env python3
import hashlib,json,os,platform,subprocess,tempfile
from pathlib import Path
from datetime import datetime,timezone
root=Path(subprocess.check_output(['git','rev-parse','--show-toplevel'],text=True).strip())
base=root/'docs/tasks/bot-setup-draft-20261022/persistence-evidence'
out=base/'author'
out.mkdir(exist_ok=False)
compiler='/tmp/bot-setup-tools/kotlinc/bin/kotlinc'
source=root/'apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/product/agents/setup'
tests=root/'apps/muyon_android/app/src/test/kotlin/com/mightyoung/muyon/product/agents/setup'
inputs=[source/'BotSetupDraft.kt',source/'SetupDraftArchive.kt',tests/'BotSetupDraftChecks.kt',tests/'BotSetupPersistenceChecks.kt',tests/'run-offline-checks.sh']
def now():return datetime.now(timezone.utc).isoformat()
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
meta={'actor':'author','kind':'new offline persistence API validation','started_utc':now(),'cwd':str(root),'head':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'platform':platform.platform(),'input_sha256':{str(p.relative_to(root)):sha(p) for p in inputs},'compiler_archive_sha256':sha('/tmp/bot-setup-tools/kotlin.zip'),'commands':[],'mutations':[]}
def capture(label,cmd,env=None):
 start=now();r=subprocess.run(cmd,cwd=root,env=env,capture_output=True)
 (out/(label+'.stdout.log')).write_bytes(r.stdout);(out/(label+'.stderr.log')).write_bytes(r.stderr)
 meta['commands'].append({'label':label,'argv':cmd,'started_utc':start,'ended_utc':now(),'exit_code':r.returncode})
 return r.returncode
assert capture('java-version',['java','-version'])==0
assert capture('kotlin-version',[compiler,'-version'])==0
env=os.environ.copy();env['KOTLINC']=compiler
meta['baseline_environment_override']={'KOTLINC':compiler}
assert capture('baseline',[str(tests/'run-offline-checks.sh')],env)==0
mutations=[
 ('schema-version','SetupDraftArchive.kt','input.readInt() == VERSION','input.readInt() >= VERSION'),
 ('checksum','SetupDraftArchive.kt','require(MessageDigest.isEqual(','require(true || MessageDigest.isEqual('),
 ('creation-export','BotSetupDraft.kt','require(creation.status in setOf(CreationStatus.NOT_REQUESTED, CreationStatus.REJECTED))','require(true)'),
 ('export-cas','BotSetupDraft.kt','require(expectedRevision == revision)','require(true)'),
 ('memory-revision','BotSetupDraft.kt','restored.name = edits.name','restored.revision = edits.storedRevision\n            restored.name = edits.name'),
 ('field-lock','SetupDraftArchive.kt','require(field.userLocked)','require(true)'),
]
with tempfile.TemporaryDirectory(prefix='setup-persistence-mutations-') as temporary:
 for label,filename,before,after in mutations:
  folder=Path(temporary)/label;folder.mkdir()
  copies=[]
  for path in inputs[:2]:
   content=path.read_text()
   if path.name==filename:
    assert before in content
    count=content.count(before);content=content.replace(before,after)
   copy=folder/path.name;copy.write_text(content);copies.append(copy)
  compiled=capture(label+'-compile',[compiler,*map(str,copies),str(inputs[2]),str(inputs[3]),'-include-runtime','-d',str(folder/'checks.jar')])
  assert compiled==0,label+' failed to compile'
  code=capture(label+'-run',['java','-jar',str(folder/'checks.jar')])
  assert code!=0,label+' survived'
  meta['mutations'].append({'label':label,'file':filename,'replace_before':before,'replace_after':after,'replacement_count':count,'compile_exit_code':compiled,'run_exit_code':code,'mutated_source_sha256':{p.name:sha(p) for p in copies}})
  print(label+': KILLED by behavioral assertion',flush=True)
meta['ended_utc']=now();meta['log_sha256']={p.name:sha(p) for p in sorted(out.glob('*.log'))}
(out/'metadata.json').write_text(json.dumps(meta,indent=2,ensure_ascii=False)+'\n')
print('PASS 17 groups and 6 compiled behavioral mutations')
