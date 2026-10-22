"""Add pinned actual Reader sources to the existing isolated component harness.
Run after preview-harness/materialize_sources.py. Never overwrites different bytes.
"""
import argparse,hashlib,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--repo',required=True);p.add_argument('--out',required=True);a=p.parse_args()
repo=Path(a.repo).resolve();out=Path(a.out).resolve();assert repo!=out
m=json.loads(Path(__file__).with_name('source-manifest.json').read_text())
for item in m['files']:
 name=item['source'];data=subprocess.check_output(['git','show',m['fixed_source']+':'+name],cwd=repo)
 assert hashlib.sha256(data).hexdigest()==item['sha256']
 rel=name.removeprefix('apps/muyon_android/')
 rel=rel.replace('/kotlin/','/java/',1)
 target=out/rel;target.parent.mkdir(parents=True,exist_ok=True)
 if target.exists() and target.read_bytes()!=data:raise RuntimeError('Refuse differing output: '+str(target))
 target.write_bytes(data)
print('Pinned actual Reader sources/test copied; synthetic harness, not product Host/FFI')
