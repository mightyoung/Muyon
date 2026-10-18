import json,subprocess,gzip,base64,re,hashlib
from pathlib import Path
run_id='39102012787'
expected='190477fe0e5008d473508e45d2d835ddd5e0c09c'
out=Path('/workspace/leaderb-record/docs/tasks/leaderb-next-20261018/evidence/b/sqlite-author')
def gh(*args):
 return subprocess.run(['gh',*args],capture_output=True)
r=gh('run','view',run_id,'--repo','mightyoung/Muyon','--json','status,conclusion,headSha,url,jobs,createdAt,startedAt,updatedAt')
if r.returncode:raise SystemExit(r.stderr.decode())
data=json.loads(r.stdout)
assert data['headSha']==expected,data
if data['status']!='completed':
 print(json.dumps({'status':data['status'],'conclusion':data['conclusion']}));raise SystemExit(2)
out.joinpath('ci-terminal.json').write_bytes(r.stdout)
r=gh('run','view',run_id,'--repo','mightyoung/Muyon','--log')
if r.returncode:
 out.joinpath('ci-log-download-error.log').write_bytes(r.stderr)
 raise SystemExit(r.returncode)
raw=r.stdout
out.joinpath('ci-full.log.gz').write_bytes(gzip.compress(raw,mtime=0))
text=raw.decode()
lines=[line for line in text.splitlines() if any(k in line for k in ['git log -1','--format=%H',expected,'Cache not found','Cache restored','Cache saved','test     ','analyze  ','CI SUMMARY:'])]
out.joinpath('ci-exact-source-summary.log').write_text('\n'.join(lines)+'\n')
found=re.search(r'COVERAGE_SNAPSHOT_GZIP_BASE64=([A-Za-z0-9+/=]+)',text)
if found:
 out.joinpath('ci-coverage-snapshot.json').write_bytes(gzip.decompress(base64.b64decode(found.group(1))))
manifest=json.loads(out.joinpath('MANIFEST.json').read_text())
manifest['ci']={'run_id':int(run_id),'source_sha':expected,'status':data['status'],'conclusion':data['conclusion'],'url':data['url'],'terminal':'ci-terminal.json','full_log':'ci-full.log.gz'}
manifest['files']=[{'path':p.name,'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(out.iterdir()) if p.is_file() and p.name!='MANIFEST.json']
out.joinpath('MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'source':expected,'status':data['status'],'conclusion':data['conclusion'],'log_bytes':len(raw),'coverage_snapshot':bool(found)}))
