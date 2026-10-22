import sys,json,hashlib,shlex,re,traceback
from pathlib import Path
sys.path.insert(0,'/workspace/host-bot-native-tools')
from task_adb_transport import shell,push
root=Path('/workspace/Muyon-host-bot-native-acceptance-20261022')
e=Path('/workspace/host-bot-native-tools/evidence')
journal=e/'device-install-journal.jsonl'
def record(x):
 with journal.open('a') as f:f.write(json.dumps(x)+'\n');f.flush()
def command(label,c):
 record({'label':label,'command':c,'state':'DISPATCH_ONCE'})
 try:
  out=shell(c,e/(label+'.log'));record({'label':label,'state':'RESPONSE','output':out});return out
 except Exception as ex:record({'label':label,'state':'UNKNOWN_NO_RETRY','error':repr(ex)});raise
assert command('device-sdk','getprop ro.build.version.sdk').strip()=='26'
assert command('device-abi','getprop ro.product.cpu.abi').strip()=='x86_64'
assert command('device-boot','getprop sys.boot_completed').strip()=='1'
assert command('before-install','pm path com.mightyoung.muyon.product').strip()==''
for kind,relative,pkg in [('app','debug/app-debug.apk','com.mightyoung.muyon.product'),('test','androidTest/debug/app-debug-androidTest.apk','com.mightyoung.muyon.product.test')]:
 source=root/'apps/muyon_android/app/build/outputs/apk'/relative
 with source.open('rb') as f:digest=hashlib.file_digest(f,'sha256').hexdigest()
 target='/data/local/tmp/muyon-bot-f2f9928a-'+kind+'.apk'
 record({'label':'push-'+kind,'state':'DISPATCH_ONCE','source':str(source),'sha256':digest,'target':target})
 try:record({'label':'push-'+kind,'state':'SYNC_OKAY','result':push(source,target)})
 except Exception as ex:record({'label':'push-'+kind,'state':'UNKNOWN_NO_RETRY','error':repr(ex)});raise
 staged=command('staged-sha-'+kind,'sha256sum '+target)
 assert staged.split()[0]==digest,staged
 installed=command('install-'+kind,'pm install -t '+target)
 assert installed.strip()=='Success',installed
 path=command('installed-path-'+kind,'pm path '+pkg).strip()
 match=re.fullmatch(r'package:(/data/app/[A-Za-z0-9._/+=-]+/base\.apk)',path)
 assert match,path
 actual=command('installed-sha-'+kind,'sha256sum '+shlex.quote(match.group(1)))
 assert actual.split()[0]==digest,actual
 record({'label':'installed-'+kind,'state':'VERIFIED_APK_SHA256','sha256':digest,'path':match.group(1)})
print('Both APKs installed Success; staged and actual installed APK SHA256 independently match sealed host APKs. No tests dispatched yet.')
