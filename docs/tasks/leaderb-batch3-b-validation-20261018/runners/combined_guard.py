import hashlib,json,subprocess
from pathlib import Path
SOURCE='d25a407830ef624802583983c0be2414bbd59dc4'
def validate(root, evidence):
 root=Path(root);evidence=Path(evidence)
 def git(*args): return subprocess.check_output(['git',*args],cwd=root,text=True).strip()
 if git('rev-parse','HEAD') != SOURCE or git('status','--porcelain'): raise RuntimeError('exact_clean_combined_source_required')
 for line in (evidence/'source-fixture-sha256.txt').read_text().splitlines():
  expected,name=line.split('  ',1)
  if hashlib.sha256((root/name).read_bytes()).hexdigest()!=expected: raise RuntimeError('combined_source_hash_mismatch:'+name)
 inventory=json.loads((evidence/'inventory-audit.json').read_text())
 if not inventory['accepted']:raise RuntimeError('combined_inventory_mismatch')
 return dict(source_sha=SOURCE,source_tree=git('rev-parse','HEAD^{tree}'),contract_sha256=inventory['contract_sha256'])
