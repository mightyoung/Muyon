"""Fresh raw inventory enumeration before the combined guard; requires locked Rust toolchain and restored frozen source manifest."""
import sys,json,hashlib,subprocess,re,os
from pathlib import Path
from orchestrate import root,evidence,run
sys.path.insert(0,str(root/'experiments/redesign/rust-agent-host-lab/checks'))
from http_batch import contract
from combined_guard import SOURCE,validate
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()==SOURCE
assert not subprocess.check_output(['git','status','--porcelain'],cwd=root,text=True).strip()
for line in (evidence/'source-fixture-sha256.txt').read_text().splitlines():
 expected,name=line.split('  ',1);assert hashlib.sha256((root/name).read_bytes()).hexdigest()==expected,name
c=contract();assert json.loads((evidence/'combined-cases.json').read_text())==c
rows=[]
for component,lab in [('core','core-agent-lab'),('plugin','plugin-contract-lab'),('host','rust-agent-host-lab')]:
 command=['cargo','test','--offline','--locked','--manifest-path',str(root/'experiments/redesign'/lab/'core/Cargo.toml'),'--','--list']
 assert run('test-list-'+component,command,dict(os.environ,CARGO_TARGET_DIR=str(evidence/'targets'/component)))==0
 text=(evidence/('test-list-'+component+'.log')).read_text();groups={};current=None
 for line in text.splitlines():
  m=re.match(r'\s*Running (unittests (\S+)|tests/(\S+)\.rs) \(',line)
  if m:current=('unit:'+m[2]) if m[2] else ('integration:'+m[3]);groups[current]=[]
  elif line.endswith(': test'):groups[current].append(line[:-6])
 expected=c['components'][component];valid=set(expected['groups']).issubset(groups) and all(set(groups[k])==set(v['names']) and len(groups[k])==len(v['names']) for k,v in expected['groups'].items()) and all(not names for k,names in groups.items() if k not in expected['groups']) and sum(map(len,groups.values()))==expected['expected_total']
 rows.append(dict(component=component,accepted=valid,total=sum(map(len,groups.values())),groups=groups,raw_sha256=hashlib.sha256(text.encode()).hexdigest()))
result=dict(accepted=all(r['accepted'] for r in rows),components=rows,contract_sha256=hashlib.sha256((evidence/'combined-cases.json').read_bytes()).hexdigest())
(evidence/'inventory-audit.json').write_text(json.dumps(result,indent=2)+'\n');assert result['accepted'];print(validate(root,evidence))
