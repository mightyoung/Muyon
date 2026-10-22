from pathlib import Path
import json,re,hashlib,zipfile
r=Path('/workspace/ui-shell-tools/3aae');s=r/'smoke';meta=json.loads((r/'artifacts.json').read_text());bid=meta['build_id'];expected=meta['artifacts'][0]['sha256']
raw=(s/'probe-instrumentation.log').read_text();assert 'OK (14 tests)' in raw and 'INSTRUMENTATION_CODE: -1' in raw
fields={};tests=[]
for line in raw.splitlines():
 if line.startswith('INSTRUMENTATION_STATUS: '):
  pair=line[len('INSTRUMENTATION_STATUS: '):].split('=',1)
  if len(pair)==2:fields[pair[0]]=pair[1]
 elif line.startswith('INSTRUMENTATION_STATUS_CODE: '):
  code=int(line.split(': ',1)[1])
  if code==0:tests.append({'class':fields['class'],'test':fields['test'],'status':'PASS'})
  elif code!=1:raise AssertionError(line)
  fields={}
assert len(tests)==14 and len({(x['class'],x['test']) for x in tests})==14
from collections import Counter
assert dict(Counter(x['class'].split('.')[-1] for x in tests))=={'ConversationShellTest':6,'DocumentReaderPlatformTest':4,'RuntimeHealthSmokeProbe':1,'BotNativeServiceAcceptanceTest':3}
healthlines=(s/'runtime-health.log').read_text().splitlines();health=[];bots=[]
for line in healthlines:
 if 'HEALTH=' in line:
  v=json.loads(line.split('HEALTH=',1)[1]);d=v['data']
  if d.get('build_id')==bid:assert d['synthetic'] is False;health.append(v)
 if 'BotNativeAcceptance: ' in line:
  v=json.loads(line.split('BotNativeAcceptance: ',1)[1])
  if v.get('health',{}).get('build_id')==bid:bots.append(v)
assert health and len(bots)>=3,(len(health),len(bots))
with zipfile.ZipFile(meta['artifacts'][0]['path']) as z:
 natives={n:hashlib.sha256(z.read(n)).hexdigest() for n in z.namelist() if n.startswith('lib/') and n.endswith(('/libmuyon_android_product.so','/libmuyon_local_embedding.so'))}
assert len(natives)==4
for bot in bots:
 assert bot['installed_apk_sha256']==expected
 assert bot['health']['synthetic'] is False and bot['health']['workspace']=='bot-native-acceptance'
 assert bot['packaged_native_sha256']==natives
result={'source_sha':meta['source_sha'],'build_id':bid,'installed_apk_sha256':expected,'test_count':14,'tests':tests,'normal_service_health_records':len(health),'real_native_debug_fixture_identity_records':len(bots),'four_native_hashes_match':True,'boundary':'isolated debug fixture; normal ProductService verified=false; no provider/inference/production Reader proof'}
(s/'device-results.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
