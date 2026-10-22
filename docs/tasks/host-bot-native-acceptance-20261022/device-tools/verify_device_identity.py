import json,re,hashlib
from pathlib import Path
p=Path('/workspace/host-bot-native-tools');e=p/'evidence'
expected_id=(p/'native-final/build-id.txt').read_text().strip()
app_hash=(e/'apk-final.sha256').read_text().splitlines()[0].split()[0]
libs={}
for line in (p/'native-final/SHA256SUMS').read_text().splitlines():
 digest,name=line.split();libs['lib/'+name]=digest
records=[]
for line in (e/'device-identity-logcat.log').read_text().splitlines():
 if 'BotNativeAcceptance' in line and '{' in line:
  value=json.loads(line[line.index('{'):]);records.append(value)
assert len(records)==4,len(records)
for value in records:
 assert value['health']['build_id']==expected_id
 assert value['health']['synthetic'] is False
 assert value['health']['workspace']=='bot-native-acceptance'
 assert value['installed_apk_sha256']==app_hash
 assert value['packaged_native_sha256']==libs
expected={'installed-app':app_hash,'installed-test':(e/'apk-final.sha256').read_text().splitlines()[1].split()[0]}
journal=[json.loads(x) for x in (e/'device-install-journal.jsonl').read_text().splitlines()]
verified=[x for x in journal if x.get('state')=='VERIFIED_APK_SHA256']
assert len(verified)==2
assert {x['label']:x['sha256'] for x in verified}==expected
for kind in ('app','test'):
 replies=[x for x in journal if x.get('label')=='installed-sha-'+kind and x.get('state')=='RESPONSE']
 assert len(replies)==1 and replies[0]['output'].split()[0]==expected['installed-'+kind]
summary={'gate':'PASS','runtime_identity_records':len(records),'native_build_id':expected_id,'installed_app_apk_sha256':app_hash,'native_entry_sha256':libs,'boundary':'actual device runtime/install identity; three fixed Bot tests only; no production enablement'}
(e/'device-identity-verified.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary,indent=2))
