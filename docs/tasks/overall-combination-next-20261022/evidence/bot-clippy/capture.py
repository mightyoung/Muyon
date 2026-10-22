#!/usr/bin/env python3
"""Audit the one-line fix on B's actual combination. Never copies an old provider/binding."""
import pathlib,subprocess,os,json,hashlib,datetime
root=pathlib.Path('/workspace/bot-clippy-combination')
owner=pathlib.Path('/workspace/bot-setup-draft')
out=owner/'docs/tasks/bot-setup-draft-20261022/clippy-equivalence-evidence'
base='b13af1124ed1b078609a3b36fcf4f56e5ec27567'
module='crates/muyon-core/src/bot_definitions.rs'
tests='crates/muyon-core/src/bot_definitions/tests.rs'
protected=['crates/muyon-core/src/bot_drafts.rs','crates/muyon-android-ffi/src/lib.rs','apps/muyon_android/app/src/main/kotlin/com/mightyoung/muyon/productbridge/muyon_android_product.kt']
def sha(b):return hashlib.sha256(b).hexdigest()
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()==base
meta={'combination':base,'patch_commit':'c65d6e3ec1ed1f50566bde705729c221f4c9f90a','started_utc':now(),'commands':[],'protected_sha256':{p:sha((root/p).read_bytes()) for p in protected},'module_sha256':sha((root/module).read_bytes()),'test_sha256':sha((root/tests).read_bytes()),'equivalence_cases':196608}
for p in protected:assert (root/p).read_bytes()==subprocess.check_output(['git','show',base+':'+p],cwd=root)
env=os.environ.copy();env.update(RUSTUP_HOME='/tmp/bot-rustup',CARGO_HOME='/tmp/bot-cargo',RUSTUP_TOOLCHAIN='1.93.0',CARGO_TARGET_DIR='/tmp/bot-clippy-current-target',LIBRARY_PATH='/tmp/bot-sqlite-link')
meta['environment_override']={k:env[k] for k in ['RUSTUP_HOME','CARGO_HOME','RUSTUP_TOOLCHAIN','CARGO_TARGET_DIR','LIBRARY_PATH']}
cargo='/tmp/bot-cargo/bin/cargo'
def capture(label,cmd):
 start=now();r=subprocess.run(cmd,cwd=root,env=env,capture_output=True)
 (out/(label+'.stdout.log')).write_bytes(r.stdout);(out/(label+'.stderr.log')).write_bytes(r.stderr)
 meta['commands'].append({'label':label,'argv':cmd,'cwd':str(root),'started_utc':start,'ended_utc':now(),'exit_code':r.returncode})
 return r
for name,cmd in [('rustc',['/tmp/bot-cargo/bin/rustc','--version']),('clippy',[cargo,'clippy','--version']),('fmt',['/tmp/bot-cargo/bin/rustfmt','--edition','2021','--check',module])]:assert capture(name,cmd).returncode==0
cmd=[cargo,'test','--manifest-path','crates/Cargo.toml','-p','muyon-core','--lib']
r=capture('baseline33',cmd+['bot_definitions','--','--test-threads=1','--nocapture']);assert r.returncode==0 and b'33 passed; 0 failed; 0 ignored' in r.stdout
original=(root/module).read_text();original_tests=(root/tests).read_text()
supp=json.loads((owner/'docs/tasks/bot-setup-draft-20261022/tail-recheck-evidence/independent-release/supplementary.metadata.json').read_text())
try:
 (root/tests).write_text(original_tests+supp['extra_test_source'])
 r=capture('extra5',cmd+['bot_definitions::tests::independent_','--','--test-threads=1','--nocapture']);assert r.returncode==0 and b'5 passed; 0 failed; 0 ignored' in r.stdout
 # Exact prior independent behavior mutations, retained on the current provider and binding.
 for label,before in [('delete-entry','verify_current(store, &key, id, &original, "pending", None)?;'),('delete-tail','verify_current(store, &key, id, &original, "committed", Some(&receipt))?;')]:
  assert original.count(before)==1;(root/module).write_text(original.replace(before,'/* omitted for negative test */'))
  r=capture(label,cmd+(['independent_entry_revoked_'] if label=='delete-entry' else ['bot_definitions'])+['--','--test-threads=1','--nocapture'])
  assert r.returncode!=0 and b'test result: FAILED' in r.stdout,label
 # Original eight author mutations, unchanged rules, on the actual new combination.
 prior=json.loads((owner/'docs/tasks/bot-setup-draft-20261022/tail-recheck-evidence/author-release/metadata.json').read_text())
 for mutation in prior['mutations']:
  before=mutation['before'];after=mutation['after'];label='prior-'+mutation['label']
  assert before in original,label
  (root/module).write_text(original.replace(before,after))
  r=capture(label,cmd+['bot_definitions','--','--test-threads=1','--nocapture'])
  assert r.returncode!=0 and b'test result: FAILED' in r.stdout,label
finally:
 (root/module).write_text(original);(root/tests).write_text(original_tests)
# Targeted lint proves this lint is closed; workspace strict still exposes other authors' errors.
assert capture('bot-nonminimal-lint',[cargo,'clippy','--manifest-path','crates/Cargo.toml','-p','muyon-core','--lib','--','-D','clippy::nonminimal_bool']).returncode==0
strict=capture('workspace-strict',[cargo,'clippy','--manifest-path','crates/Cargo.toml','--workspace','--all-targets','--','-D','warnings'])
meta['workspace_strict_exit_code']=strict.returncode
for p,h in meta['protected_sha256'].items():assert sha((root/p).read_bytes())==h
assert sha((root/module).read_bytes())==meta['module_sha256'] and sha((root/tests).read_bytes())==meta['test_sha256']
meta['ended_utc']=now();meta['log_sha256']={p.name:sha(p.read_bytes()) for p in sorted(out.glob('*.log'))}
(out/'metadata.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
print('PASS current-combination33+5 and prior entry/tail mutations; protected provider/binding unchanged',flush=True)
print('Workspace strict exit '+str(strict.returncode)+'; preserve other authors diagnostics',flush=True)
