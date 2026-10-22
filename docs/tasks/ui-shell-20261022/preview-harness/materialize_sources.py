"""Materialize pinned real component sources/resources into a separate preview tree.
Never writes production repo; existing different output bytes are refused.
"""
import argparse,subprocess,json,hashlib
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument('--repo',required=True);parser.add_argument('--out',required=True);a=parser.parse_args();repo=Path(a.repo).resolve();out=Path(a.out).resolve();assert out!=repo
manifest=json.loads((Path(__file__).parent/'source-manifest.json').read_text());sha=manifest['product_source']
def raw(path):return subprocess.check_output(['git','show',sha+':'+path],cwd=repo)
def put(relative,data):
 p=out/relative;p.parent.mkdir(parents=True,exist_ok=True)
 if p.exists() and p.read_bytes()!=data:raise RuntimeError('Refuse overwriting different output: '+str(p))
 p.write_bytes(data)
for item in manifest['files']:
 name=item['source'];data=raw(name);assert hashlib.sha256(data).hexdigest()==item['sha256']
 for prefix,dest in [('apps/muyon_android/app/src/main/kotlin/','app/src/main/java/'),('apps/muyon_android/app/src/androidTest/kotlin/','app/src/androidTest/java/')]:
  if name.startswith(prefix):put(dest+name[len(prefix):],data);break
 else:raise ValueError('unsupported source path')
res='apps/muyon_android/app/src/main/res/'
for path in subprocess.check_output(['git','ls-tree','-r','--name-only',sha,res],cwd=repo,text=True).splitlines():put('app/src/main/res/'+path[len(res):],raw(path))
print('Pinned component sources and real resources materialized; preview scaffold must be copied separately')
